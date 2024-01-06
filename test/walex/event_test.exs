defmodule WalEx.EventTest do
  use ExUnit.Case, async: false
  import WalEx.Support.TestHelpers

  alias WalEx.Destinations.EventModules, as: DestinationsEventModules
  alias WalEx.Destinations.Supervisor, as: DestinationsSupervisor
  alias WalEx.Supervisor, as: WalExSupervisor
  alias WalEx.Replication.Supervisor, as: ReplicationSupervisor
  alias WalEx.Replication.Publisher, as: ReplicationPublisher

  @app_name :test_app
  @hostname "localhost"
  @username "postgres"
  @password "postgres"
  @database "todos_test"

  @base_configs [
    name: @app_name,
    hostname: @hostname,
    username: @username,
    password: @password,
    database: @database,
    port: 5432,
    subscriptions: ["user", "todo"],
    publication: ["events"],
    modules: [TestApp.TestModule]
  ]

  @dsl_base_configs [
    name: @app_name,
    hostname: @hostname,
    username: @username,
    password: @password,
    database: @database,
    port: 5432,
    subscriptions: ["user", "todo"],
    publication: ["events"],
    modules: [TestApp.DslTestModule]
  ]

  describe "process_all/1" do
    setup do
      {:ok, database_pid} = start_database()
      {:ok, supervisor_pid} = WalExSupervisor.start_link(@base_configs)

      %{database_pid: database_pid, supervisor_pid: supervisor_pid}
    end

    test "should successfully receive Transaction", %{
      database_pid: database_pid,
      supervisor_pid: supervisor_pid
    } do
      destinations_supervisor_pid = find_worker_pid(supervisor_pid, DestinationsSupervisor)

      assert is_pid(destinations_supervisor_pid)

      events_pid =
        find_worker_pid(destinations_supervisor_pid, DestinationsEventModules)

      assert is_pid(events_pid)

      update_user(database_pid)

      # https://www.thegreatcodeadventure.com/testing-genservers-with-erlang-trace/
      :erlang.trace(events_pid, true, [:receive])

      assert_receive {
        :trace,
        ^events_pid,
        :receive,
        {:"$gen_call", _pid_and_ref,
         {
           :process,
           %WalEx.Changes.Transaction{
             changes: [
               %WalEx.Changes.UpdatedRecord{
                 type: "UPDATE",
                 old_record: _old_record,
                 record: %{
                   id: 1,
                   name: "John Doe",
                   age: 30,
                   created_at: _created_at,
                   email: "john.doe@example.com",
                   updated_at: _updated_at
                 },
                 schema: "public",
                 table: "user",
                 columns: _columns,
                 commit_timestamp: _updated_record_commit_timestamp
               }
             ],
             commit_timestamp: _transaction_commit_timestamp
           },
           :test_app
         }}
      }
    end

    test "should restart the Publisher & Events processes when error", %{
      database_pid: database_pid,
      supervisor_pid: supervisor_pid
    } do
      destinations_supervisor_pid = find_worker_pid(supervisor_pid, DestinationsSupervisor)

      assert is_pid(destinations_supervisor_pid)

      events_pid = find_worker_pid(destinations_supervisor_pid, DestinationsEventModules)

      assert is_pid(events_pid)

      replication_supervisor_pid = find_worker_pid(supervisor_pid, ReplicationSupervisor)

      assert is_pid(replication_supervisor_pid)

      replication_publisher_pid =
        find_worker_pid(replication_supervisor_pid, ReplicationPublisher)

      assert is_pid(replication_publisher_pid)

      update_user(database_pid)

      # https://smartlogic.io/blog/test-process-monitoring/
      _process_ref = Process.monitor(events_pid)

      assert_receive {
        :DOWN,
        _process_ref,
        :process,
        ^events_pid,
        {%RuntimeError{message: "Process error"}, _stacktrace}
      }

      # Wait for supervisor to restart Events GenServer and Publisher
      :timer.sleep(500)

      new_events_pid =
        find_worker_pid(destinations_supervisor_pid, DestinationsEventModules)

      assert is_pid(new_events_pid)
      refute events_pid == new_events_pid

      new_replication_publisher_pid =
        find_worker_pid(replication_supervisor_pid, ReplicationPublisher)

      assert is_pid(new_replication_publisher_pid)
      refute replication_publisher_pid == new_replication_publisher_pid
    end
  end

  describe "dsl" do
    setup do
      {:ok, database_pid} = start_database()
      {:ok, supervisor_pid} = WalExSupervisor.start_link(@dsl_base_configs)

      %{database_pid: database_pid, supervisor_pid: supervisor_pid}
    end

    test "listening all events", %{database_pid: database_pid} do
      events_pid = Process.whereis(WalEx.Events)
      assert is_pid(events_pid)

      capture_log =
        ExUnit.CaptureLog.capture_log(fn ->
          update_user(database_pid)

          :timer.sleep(1000)
        end)

      assert capture_log =~ "event occured"
    end
  end

  defp update_user(database_pid) do
    update_user = """
      UPDATE \"user\" SET age = 30 WHERE id = 1
    """

    Postgrex.query!(database_pid, update_user, [])
  end

  defp start_database do
    Postgrex.start_link(
      hostname: @hostname,
      username: @username,
      password: @password,
      database: @database
    )
  end
end

defmodule TestApp.TestModule do
  use WalEx.Event, name: :test_app

  def process_all(%WalEx.Changes.Transaction{}) do
    raise RuntimeError, "Process error"
  end
end

defmodule TestApp.DslTestModule do
  require Logger
  use WalEx.Event, name: :test_app

  on_event(
    :all,
    fn event -> Logger.info("event occured: #{inspect(event, pretty: true)}") end
  )
end
