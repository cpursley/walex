defmodule WalEx.EventDslTest do
  use ExUnit.Case, async: false
  import WalEx.Support.TestHelpers

  alias WalEx.Destinations.EventModules, as: DestinationsEventModules
  alias WalEx.Destinations.Supervisor, as: DestinationsSupervisor
  alias WalEx.Supervisor, as: WalExSupervisor

  @app_name :test_app
  @hostname "localhost"
  @username "postgres"
  @password "postgres"
  @database "todos_test"

  @dsl_base_configs [
    name: @app_name,
    hostname: @hostname,
    username: @username,
    password: @password,
    database: @database,
    port: 5432,
    subscriptions: ["user", "todo"],
    publication: ["events"],
    destinations: [modules: [TestApp.DslTestModule]]
  ]

  describe "on_event/2" do
    setup do
      {:ok, database_pid} = start_database()
      {:ok, supervisor_pid} = WalExSupervisor.start_link(@dsl_base_configs)

      %{database_pid: database_pid, supervisor_pid: supervisor_pid}
    end

    test "should receive and return all Events", %{
      supervisor_pid: supervisor_pid,
      database_pid: database_pid
    } do
      destinations_supervisor_pid = find_worker_pid(supervisor_pid, DestinationsSupervisor)

      assert is_pid(destinations_supervisor_pid)

      events_pid =
        find_worker_pid(destinations_supervisor_pid, DestinationsEventModules)

      assert is_pid(events_pid)

      capture_log =
        ExUnit.CaptureLog.capture_log(fn ->
          update_user(database_pid)

          :timer.sleep(1000)
        end)

      assert capture_log =~ "on_event event occurred"
      assert capture_log =~ "%WalEx.Event"
    end
  end

  describe "on_update/4" do
    setup do
      {:ok, database_pid} = start_database()
      {:ok, supervisor_pid} = WalExSupervisor.start_link(@dsl_base_configs)

      %{database_pid: database_pid, supervisor_pid: supervisor_pid}
    end

    test "should receive and return 'user' update Events", %{
      supervisor_pid: supervisor_pid,
      database_pid: database_pid
    } do
      destinations_supervisor_pid = find_worker_pid(supervisor_pid, DestinationsSupervisor)

      assert is_pid(destinations_supervisor_pid)

      events_pid =
        find_worker_pid(destinations_supervisor_pid, DestinationsEventModules)

      assert is_pid(events_pid)

      capture_log =
        ExUnit.CaptureLog.capture_log(fn ->
          update_user(database_pid)

          :timer.sleep(1000)
        end)

      assert capture_log =~ "on_update event occurred"
      assert capture_log =~ "%WalEx.Event"
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
end

defmodule TestApp.DslTestModule do
  require Logger
  use WalEx.Event, name: :test_app

  on_event(
    :all,
    fn events -> Logger.info("on_event event occurred: #{inspect(events, pretty: true)}") end
  )

  on_update(
    :user,
    [],
    fn events -> Logger.info("on_update event occurred: #{inspect(events, pretty: true)}") end
  )
end
