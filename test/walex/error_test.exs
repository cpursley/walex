defmodule WalEx.ErrorTest do
  use ExUnit.Case, async: false

  alias WalEx.Supervisor, as: WalExSupervisor

  require Logger

  @test_database "todos_test"

  describe "errors in event handlers" do
    @tag :skip_ci
    test "should restart the publisher process" do
      {:ok, pid} = start_database()
      configs = get_configs()
      {:ok, _} = WalExSupervisor.start_link(configs)

      users = """
        INSERT INTO \"user\" (email, name, age)
        VALUES
          ('test.user@example.com', 'Test User', 28);
      """

      Postgrex.query!(pid, users, [])

      :timer.sleep(1000)

      publisher_pid = Process.whereis(WalEx.Replication.Publisher)
      assert is_pid(publisher_pid)

      delete_users = """
        DELETE FROM "user" WHERE email = 'test.user@example.com';
      """

      Postgrex.query!(pid, delete_users, [])

      :timer.sleep(1000)

      publisher_pid = Process.whereis(WalEx.Replication.Publisher)
      assert is_pid(publisher_pid)
    end
  end

  defp start_database() do
    Postgrex.start_link(
      hostname: "localhost",
      username: "postgres",
      password: "postgres",
      database: @test_database
    )
  end

  defp get_configs(keys \\ []) do
    configs = [
      name: :test_name,
      hostname: "localhost",
      username: "postgres",
      password: "postgres",
      database: @test_database,
      port: 5432,
      subscriptions: [:user, :todo],
      publication: ["events"],
      modules: [WalEx.TestModule]
    ]

    case keys do
      [] -> configs
      _keys -> Keyword.take(configs, keys)
    end
  end
end

defmodule WalEx.TestModule do
  use WalEx.Event, name: :test_name

  def process_all(_transaction) do
    raise "test error"
  end
end
