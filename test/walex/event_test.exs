defmodule WalEx.EventTest do
  use ExUnit.Case, async: false

  alias WalEx.Supervisor, as: WalExSupervisor
  alias WalEx.Replication.Publisher, as: ReplicationPublisher

  @app_name :test_app
  @hostname "localhost"
  @username "postgres"
  @password "postgres"
  @database "todos_test"

  describe "process_all/1" do
    setup do
      assert {:ok, database_pid} = start_database()
      assert is_pid(database_pid)
      assert {:ok, supervisor_pid} = WalExSupervisor.start_link(get_configs())
      assert is_pid(supervisor_pid)

      %{database_pid: database_pid}
    end

    test "should successfully receive Transaction", %{database_pid: database_pid} do
      events_pid = Process.whereis(WalEx.Events)
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

      assert is_pid(Process.whereis(ReplicationPublisher))
    end

    test "should restart the Publisher & Events processes when error", %{
      database_pid: database_pid
    } do
      events_pid = Process.whereis(WalEx.Events)
      assert is_pid(events_pid)

      replication_publisher_pid = Process.whereis(ReplicationPublisher)
      assert is_pid(replication_publisher_pid)

      update_user(database_pid)

      # https://smartlogic.io/blog/test-process-monitoring/
      process_ref = Process.monitor(events_pid)

      assert_receive {
        :DOWN,
        ^process_ref,
        :process,
        ^events_pid,
        {%RuntimeError{message: "Process error"}, _stacktrace}
      }

      # Wait for supervisor to restart Events GenServer and Publisher
      :timer.sleep(500)

      new_events_pid = Process.whereis(WalEx.Events)

      assert is_pid(new_events_pid)
      assert events_pid != new_events_pid

      new_replication_publisher_pid = Process.whereis(ReplicationPublisher)

      assert is_pid(new_replication_publisher_pid)
      assert replication_publisher_pid != new_replication_publisher_pid
    end
  end

  defp update_user(database_pid) do
    update_user = """
      UPDATE \"user\" SET age = 30 WHERE id = 1
    """

    Postgrex.query!(database_pid, update_user, [])
  end

  defp start_database() do
    Postgrex.start_link(
      hostname: @hostname,
      username: @username,
      password: @password,
      database: @database
    )
  end

  defp get_configs do
    [
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
  end
end

defmodule TestApp.TestModule do
  use WalEx.Event, name: :test_app

  def process_all(%WalEx.Changes.Transaction{}) do
    raise RuntimeError, "Process error"
  end
end
