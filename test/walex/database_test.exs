defmodule WalEx.DatabaseTest do
  use ExUnit.Case, async: false
  import WalEx.Support.TestHelpers
  alias WalEx.Supervisor, as: WalExSupervisor

  require Logger

  @hostname "localhost"
  @username "postgres"
  @password "postgres"
  @database "todos_test"

  @base_configs [
    name: :todos,
    hostname: @hostname,
    username: @username,
    password: @password,
    database: @database,
    port: 5432,
    subscriptions: ["user", "todo"],
    publication: "events",
    destinations: [modules: [TestModule]]
  ]

  @replication_slot %{"active" => true, "slot_name" => "todos_walex", "slot_type" => "logical"}

  describe "logical replication" do
    setup do
      {:ok, database_pid} = start_database()

      %{database_pid: database_pid}
    end

    test "should have logical replication set up", %{database_pid: pid} do
      assert is_pid(pid)
      assert [%{"wal_level" => "logical"}] == query(pid, "SHOW wal_level;")
    end

    test "should start replication slot", %{database_pid: database_pid} do
      assert {:ok, replication_pid} = WalExSupervisor.start_link(@base_configs)
      assert is_pid(replication_pid)
      assert [@replication_slot | _replication_slots] = pg_replication_slots(database_pid)
    end

    test "should re-initiate after forcing database process termination" do
      assert {:ok, supervisor_pid} = TestSupervisor.start_link(@base_configs)
      database_pid = get_database_pid(supervisor_pid)

      assert is_pid(database_pid)
      assert [@replication_slot | _replication_slots] = pg_replication_slots(database_pid)

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

      wait_for_restart()

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
