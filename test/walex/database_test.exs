defmodule WalEx.DatabaseTest do
  use ExUnit.Case, async: false

  alias WalEx.Supervisor, as: WalExSupervisor

  @hostname "localhost"
  @username "postgres"
  @password "postgres"
  @database "todos_test"

  describe "logical replication" do
    setup do
      {:ok, database_pid} = start_database()

      %{database_pid: database_pid}
    end

    test "should have logical replication set up", %{database_pid: pid} do
      show_wall_level = "SHOW wal_level;"

      assert is_pid(pid)
      assert [%{"wal_level" => "logical"}] == query(pid, show_wall_level)
    end

    test "should start replication slot", %{database_pid: database_pid} do
      assert {:ok, replication_pid} = WalExSupervisor.start_link(get_configs())
      assert is_pid(replication_pid)

      pg_replication_slots = "SELECT slot_name, slot_type, active FROM \"pg_replication_slots\";"

      assert [
               %{"active" => true, "slot_name" => slot_name, "slot_type" => "logical"}
               | _replication_slots
             ] = query(database_pid, pg_replication_slots)

      assert String.contains?(slot_name, "walex_temp_slot")
    end
  end

  def get_configs do
    [
      name: :todos,
      hostname: @hostname,
      username: @username,
      password: @password,
      database: @database,
      port: 5432,
      subscriptions: ["user", "todo"],
      publication: "events"
    ]
  end

  def start_database do
    Postgrex.start_link(
      hostname: @hostname,
      username: @username,
      password: @password,
      database: @database
    )
  end

  def query(pid, query) do
    pid
    |> Postgrex.query!(query, [])
    |> map_rows_to_columns()
  end

  def map_rows_to_columns(%Postgrex.Result{columns: columns, rows: rows}) do
    Enum.map(rows, fn row -> Enum.zip(columns, row) |> Map.new() end)
  end

  def map_rows_to_columns(_result), do: []
end
