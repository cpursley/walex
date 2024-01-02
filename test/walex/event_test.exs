defmodule WalEx.EventTest do
  use ExUnit.Case, async: false

  alias WalEx.Supervisor, as: WalExSupervisor

  require Logger

  @app_name :test_name
  @hostname "localhost"
  @username "postgres"
  @password "postgres"
  @database "todos_test"

  describe "errors in event handlers" do
    test "should restart the publisher process" do
      assert {:ok, database_pid} = start_database()
      assert is_pid(database_pid)
      {:ok, supervisor_pid} = WalExSupervisor.start_link(get_configs())
      assert is_pid(supervisor_pid)

      update_user = """
        UPDATE \"user\" SET age = 30 WHERE id = 1
      """

      Postgrex.query!(database_pid, update_user, [])

      # How can we test this? TestModule does not seem to get called.
    end
  end

  defp start_database() do
    Postgrex.start_link(
      hostname: @hostname,
      username: @username,
      password: @password,
      database: @database
    )
  end

  defp get_configs(keys \\ []) do
    configs = [
      name: @app_name,
      hostname: @hostname,
      username: @username,
      password: @password,
      database: @database,
      port: 5432,
      subscriptions: [:user, :todo],
      publication: ["events"],
      modules: [TestName.TestModule]
    ]

    case keys do
      [] ->
        configs

      _keys ->
        Keyword.take(configs, keys)
    end
  end
end

defmodule TestName.TestModule do
  use WalEx.Event, name: :test_name

  require Logger

  def process_all(transaction) do
    Logger.error(transaction)
    raise "test error"
  end
end
