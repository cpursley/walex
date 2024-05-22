defmodule WalEx.DatabaseTest do
  use ExUnit.Case, async: false
  import WalEx.Support.TestHelpers
  alias WalEx.Replication.Progress
  alias WalEx.Supervisor, as: WalExSupervisor

  require Logger

  @hostname "localhost"
  @username "postgres"
  @password "postgres"
  @database "todos_test"
  @app_name :todos

  @base_configs [
    name: @app_name,
    hostname: @hostname,
    username: @username,
    password: @password,
    database: @database,
    port: 5432,
    subscriptions: ["user", "todo"],
    publication: "events",
    destinations: [modules: [TestModule]]
  ]

  @replication_slot %{
    "active" => true,
    "slot_name" => "todos_walex",
    "slot_type" => "logical",
    "temporary" => true
  }

  describe "logical replication" do
    setup do
      {:ok, database_pid} = start_database()
      pg_drop_slots(database_pid)

      %{database_pid: database_pid}
    end

    test "should have logical replication set up", %{database_pid: pid} do
      assert is_pid(pid)
      assert [%{"wal_level" => "logical"}] == query(pid, "SHOW wal_level;")
    end

    test "error early if publication doesn't exists" do
      Process.flag(:trap_exit, true)
      config = Keyword.put(@base_configs, :publication, "non_existent_publication")

      {_pid, ref} =
        spawn_monitor(fn -> WalExSupervisor.start_link(config) end)

      assert_receive {:DOWN, ^ref, _, _, {:shutdown, _}}
    end

    test "should start replication slot", %{database_pid: database_pid} do
      assert {:ok, replication_pid} = WalExSupervisor.start_link(@base_configs)
      assert is_pid(replication_pid)
      assert [@replication_slot] = pg_replication_slots(database_pid)
    end

    test "user-defined slot_name", %{database_pid: database_pid} do
      slot_name = "userdefined"

      config = Keyword.put(@base_configs, :slot_name, slot_name)

      assert {:ok, replication_pid} = WalExSupervisor.start_link(config)

      assert is_pid(replication_pid)
      assert [slot] = pg_replication_slots(database_pid)
      assert Map.fetch!(slot, "slot_name") == slot_name
    end

    test "should re-initiate after forcing database process termination" do
      assert {:ok, supervisor_pid} = TestSupervisor.start_link(@base_configs)
      database_pid = get_database_pid(supervisor_pid)

      assert is_pid(database_pid)
      assert [@replication_slot] = pg_replication_slots(database_pid)

      assert Process.exit(database_pid, :kill)
             |> tap_debug("Forcefully killed database connection: ")

      refute Process.info(database_pid)

      new_database_pid = get_database_pid(supervisor_pid)

      assert is_pid(new_database_pid)
      refute database_pid == new_database_pid
      assert_update_user(new_database_pid)
    end

    test "should re-initiate after database connection restarted by supervisor" do
      assert {:ok, supervisor_pid} = TestSupervisor.start_link(@base_configs)
      database_pid = get_database_pid(supervisor_pid)

      Supervisor.terminate_child(supervisor_pid, DBConnection.ConnectionPool)
      |> tap_debug("Supervisor terminated database connection: ")

      assert :undefined == get_database_pid(supervisor_pid)

      refute Process.info(database_pid)

      Supervisor.restart_child(supervisor_pid, DBConnection.ConnectionPool)
      |> tap_debug("Supervisor restarted database connection: ")

      wait_for_restart()

      restarted_database_pid = get_database_pid(supervisor_pid)

      assert is_pid(restarted_database_pid)
      refute database_pid == restarted_database_pid
      assert_update_user(restarted_database_pid)

      assert [@replication_slot | _replication_slots] =
               pg_replication_slots(restarted_database_pid)
    end

    test "should re-initiate after database connection terminated" do
      assert {:ok, supervisor_pid} = TestSupervisor.start_link(@base_configs)
      database_pid = get_database_pid(supervisor_pid)

      assert {:error,
              %DBConnection.ConnectionError{
                message: "tcp recv: closed",
                severity: :error,
                reason: :error
              }} == terminate_database_connection(database_pid, @username)

      assert_update_user(database_pid)

      assert [@replication_slot | _replication_slots] = pg_replication_slots(database_pid)
    end

    test "should re-initiate after database restart" do
      assert {:ok, supervisor_pid} = TestSupervisor.start_link(@base_configs)
      database_pid = get_database_pid(supervisor_pid)

      assert is_pid(database_pid)
      assert [@replication_slot | _replication_slots] = pg_replication_slots(database_pid)

      assert Process.exit(database_pid, :kill)
             |> tap_debug("Forcefully killed database connection: ")

      assert :ok == pg_restart()

      new_database_pid = get_database_pid(supervisor_pid)

      assert is_pid(new_database_pid)
      refute database_pid == new_database_pid
      assert_update_user(new_database_pid)
    end

    test "durable replication slot", %{database_pid: database_pid} do
      assert [] = pg_replication_slots(database_pid)

      slot_name = "durable_slot"
      durable_opts = Keyword.merge(@base_configs, durable_slot: true, slot_name: slot_name)

      durable_slot = %{
        "active" => true,
        "slot_name" => slot_name,
        "slot_type" => "logical",
        "temporary" => false
      }

      stopped_slot = Map.replace(durable_slot, "active", false)

      start_supervised!({WalExSupervisor, durable_opts},
        restart: :temporary,
        id: :ok_supervisor
      )

      assert [^durable_slot] = pg_replication_slots(database_pid)

      other_app_opts = Keyword.replace!(durable_opts, :name, :other_app)

      assert {:error, {{:shutdown, error}, _}} =
               start_supervised({WalExSupervisor, other_app_opts},
                 restart: :temporary,
                 id: :other_app_supervisor
               )

      assert {:failed_to_start_child, WalEx.Replication.Supervisor, {:shutdown, error}} = error
      assert {:failed_to_start_child, WalEx.Replication.Server, error} = error
      assert %RuntimeError{message: "Durable slot already active"} = error

      stop_supervised(:ok_supervisor)
      # sleep to make sure that Postgres detect that the connection is closed
      Process.sleep(1_000)
      assert [^stopped_slot] = pg_replication_slots(database_pid)

      start_supervised!({WalExSupervisor, durable_opts},
        restart: :temporary,
        id: :ok_supervisor
      )

      assert [^durable_slot] = pg_replication_slots(database_pid)
    end

    test "wal_end in keep-alive is server's wal_end+1 when no transaction are in progress" do
      TestSupervisor.start_link(@base_configs)
      Progress.start_link(app_name: @app_name)

      server_wal_end = 6846
      clock = 42
      keep_alive_request = <<?k, server_wal_end::64, clock::64, 1>>
      state = %{app_name: @app_name}

      assert {:noreply, [reply], ^state} =
               WalEx.Replication.Server.handle_data(keep_alive_request, state)

      <<?r, wal_end::64, wal_end::64, wal_end::64, _clock::64, 0>> = reply
      assert wal_end == server_wal_end + 1
    end

    test "wal_end in keep-alive reply matches last in progress transaction" do
      TestSupervisor.start_link(@base_configs)
      Progress.start_link(app_name: @app_name)

      not_finished = 123
      server_wal_end = 568
      clock = 42
      keep_alive_request = <<?k, server_wal_end::64, clock::64, 1>>
      state = %{app_name: @app_name}

      Progress.begin(@app_name, {0, not_finished})

      assert {:noreply, [reply], ^state} =
               WalEx.Replication.Server.handle_data(keep_alive_request, state)

      <<?r, wal_end::64, wal_end::64, wal_end::64, _clock::64, 0>> = reply
      assert wal_end == not_finished

      Progress.done(@app_name, {0, not_finished})
    end
  end

  @linux_path "/usr/lib/postgresql"
  @mac_homebrew_path "/usr/local/Cellar/postgresql"
  @mac_apple_silicon_homebrew_path "/opt/homebrew/Cellar/postgresql"
  @mac_app_path "/Applications/Postgres.app/Contents/Versions"

  def pg_restart do
    if uses_docker_compose() do
      Logger.debug("Restarting docker postgres.")
      pg_restart(:docker)
    else
      Logger.debug("Restarting system postgres.")
      pg_restart(:system)
    end
  end

  def uses_docker_compose do
    case(System.shell("docker compose -f docker-compose.dbs.yml ps db")) do
      {_, 0} -> true
      _ -> false
    end
  end

  def pg_restart(:docker) do
    case(System.shell("docker compose -f docker-compose.dbs.yml restart db")) do
      {_, 0} ->
        :ok

      {output, _} ->
        Logger.error("Error restarting PostgreSQL via docker-compose: #{inspect(output)}")
        raise "Error restarting PostgreSQL via docker-compose."
    end
  end

  def pg_restart(:system) do
    case :os.type() do
      {:unix, :darwin} ->
        Logger.debug("MacOS detected.")

        restart_postgres()

      {:unix, :linux} ->
        Logger.debug("Linux detected.")

        restart_postgres()

      other ->
        Logger.debug("Unsupported operating system: #{inspect(other)}")
        :ok
    end
  end

  defp pg_installation_type do
    cond do
      File.exists?(@linux_path) ->
        :linux

      File.exists?(@mac_homebrew_path) ->
        :mac_homebrew

      File.exists?(@mac_apple_silicon_homebrew_path) ->
        :mac_apple_silicon_homebrew

      File.exists?(@mac_app_path) ->
        :mac_app
    end
  end

  defp pg_ctl_path do
    case pg_installation_type() do
      :linux ->
        Logger.debug("PostgreSQL installed via Linux.")
        @linux_path

      :mac_homebrew ->
        Logger.debug("PostgreSQL installed via homebrew.")
        @mac_homebrew_path

      :mac_apple_silicon_homebrew ->
        Logger.debug("PostgreSQL installed via apple silicon homebrew.")
        @mac_apple_silicon_homebrew_path

      :mac_app ->
        Logger.debug("PostgreSQL installed via Postgres.app.")
        @mac_app_path

      true ->
        raise "PostgreSQL not installed via Postgres.app or homebrew."
    end
  end

  defp pg_data_directory(version) do
    postgres_data_directory =
      case pg_installation_type() do
        :linux ->
          "/var/lib/postgresql/#{version}/main/"

        :mac_homebrew ->
          "/usr/local/var/postgres-#{version}"

        :mac_apple_silicon_homebrew ->
          "/opt/homebrew/var/postgresql"

        :mac_app ->
          System.user_home!() <> "/Library/Application\ Support/Postgres/var-#{version}"
      end

    if File.exists?(postgres_data_directory) do
      postgres_data_directory
    else
      raise "pg data directory not found. Make sure PostgreSQL is installed correctly."
    end
  end

  defp pg_bin_path(postgres_path, version) do
    postgres_bin_path = Path.join([postgres_path, version, "bin", "pg_ctl"])

    if File.exists?(postgres_bin_path) do
      postgres_bin_path
    else
      raise "pg_ctl binary not found. Make sure PostgreSQL is installed correctly."
    end
  end

  defp restart_postgres do
    postgres_path = pg_ctl_path()
    version = pg_version(postgres_path)
    postgres_bin_path = pg_bin_path(postgres_path, version)
    data_directory = pg_data_directory(version)

    case pg_stop(postgres_bin_path, data_directory) do
      {:ok,
       %Rambo{
         status: 0,
         out: _message,
         err: ""
       }} ->
        unless pg_isready?() do
          pg_start(postgres_bin_path, data_directory)
          Logger.debug("Waiting after pg_start")
          :timer.sleep(4000)
          pg_isready?()
        end

      {:error,
       %Rambo{
         status: 1,
         out: "",
         err: error
       }} ->
        Logger.debug("PostgreSQL not stopped: " <> inspect(error))

      _ ->
        Logger.debug("PostgreSQL not stopped.")
    end

    :ok
  end

  defp pg_stop(postgres_bin_path, data_directory) do
    Logger.debug("PostgreSQL stopping.")

    case pg_installation_type() do
      :mac_apple_silicon_homebrew ->
        Rambo.run("brew", ["services", "stop", "postgresql"])

      _ ->
        Rambo.run(postgres_bin_path, [
          "stop",
          "-m",
          "immediate",
          "-D",
          "#{data_directory}"
        ])
    end
  end

  defp pg_start(postgres_bin_path, data_directory) do
    Logger.debug("PostgreSQL starting.")

    case pg_installation_type() do
      :mac_apple_silicon_homebrew ->
        Rambo.run("brew", ["services", "start", "postgresql"])

      _ ->
        # For some reason starting pg hangs so we run in async as not to block...
        Task.async(fn ->
          Rambo.run(
            postgres_bin_path,
            [
              "start",
              "-D",
              "#{data_directory}"
            ]
          )
        end)
    end
  end

  defp pg_isready? do
    case Rambo.run("pg_isready", ["-h", "localhost", "-p", "5432"]) do
      {:ok, %Rambo{status: 0, out: "localhost:5432 - accepting connections\n", err: ""}} ->
        Logger.debug("PostgreSQL is running.")
        true

      {:error, %Rambo{status: 2, out: "localhost:5432 - no response\n", err: ""}} ->
        Logger.debug("PostgreSQL is not running.")
        false

      error ->
        Logger.debug("PostgreSQL is not running: " <> inspect(error))
        false
    end
  end

  defp pg_version(postgres_path) do
    case Rambo.run("ls", [postgres_path]) do
      {:ok, %Rambo{status: 0, out: versions, err: ""}} when is_binary(versions) ->
        versions
        |> String.split("\n")
        |> Enum.filter(&String.match?(&1, ~r/^[0-9._]+$/))
        |> Enum.max()

      _error ->
        raise "PostgreSQL version not found."
    end
  end

  defp start_database do
    Postgrex.start_link(
      hostname: @hostname,
      username: @username,
      password: @password,
      database: @database
    )
  end

  defp assert_update_user(database_pid) do
    capture_log =
      ExUnit.CaptureLog.capture_log(fn ->
        update_user(database_pid)

        :timer.sleep(1000)
      end)

    assert capture_log =~ "on_update event occurred"
    assert capture_log =~ "%WalEx.Event"
  end
end

defmodule TestSupervisor do
  use Supervisor

  def start_link(configs) do
    Supervisor.start_link(__MODULE__, configs, name: __MODULE__)
  end

  def init(configs) do
    children = [
      {Postgrex, configs},
      {WalEx.Supervisor, configs}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

defmodule TestModule do
  require Logger
  use WalEx.Event, name: :todos

  on_update(
    :user,
    [],
    fn events -> Logger.info("on_update event occurred: #{inspect(events, pretty: true)}") end
  )
end
