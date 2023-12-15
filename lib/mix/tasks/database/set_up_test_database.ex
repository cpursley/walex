defmodule Mix.Tasks.SetUpTestDatabase do
  use Mix.Task

  alias Mix.Tasks.Helpers

  @test_database "todos_test"

  @shortdoc "Set up test database and tables"
  def run(_) do
    Mix.Task.run("app.start")
    setup_test_database()
  end

  defp setup_test_database do
    Helpers.create_database(@test_database)

    {:ok, pid} =
      Postgrex.start_link(
        hostname: "localhost",
        username: "postgres",
        password: "postgres",
        database: @test_database
      )

    create_database_logic(pid)
    create_database_tables(pid)
    set_up_logical_replication(pid)
  end

  defp create_database_logic(pid) do
    Helpers.create_extension(pid, "citext")
    Helpers.create_extension(pid, "uuid-ossp")
    create_updated_at_function(pid)
  end

  defp create_database_tables(pid) do
    create_user_table(pid)
    create_updated_at_trigger(pid, "user")
    create_todo_table(pid)
    create_updated_at_trigger(pid, "todo")
  end

  defp set_up_logical_replication(pid) do
    set_wal_level_to_logical(pid)
    set_event_publications(pid)
    set_replica_identity(pid, "user")
    set_replica_identity(pid, "todo")
  end

  defp set_wal_level_to_logical(pid) do
    set_wal_level = "ALTER SYSTEM SET wal_level = \'logical\';"

    Postgrex.query!(pid, set_wal_level, [])
  end

  defp set_event_publications(pid) do
    event_publications = "CREATE PUBLICATION events FOR TABLE \"user\", \"todo\";"

    Postgrex.query!(pid, event_publications, [])
  end

  defp set_replica_identity(pid, table_name) do
    replica_identity = "ALTER TABLE \"#{table_name}\" REPLICA IDENTITY FULL;"

    Postgrex.query!(pid, replica_identity, [])
  end

  defp create_updated_at_function(pid) do
    create_updated_at_function_statement = """
      CREATE OR REPLACE FUNCTION set_current_timestamp_updated_at()
      RETURNS TRIGGER AS $$
      DECLARE
        _new record;
      BEGIN
        _new := NEW;
        _new."updated_at" = NOW();
        RETURN _new;
      END;
      $$ LANGUAGE plpgsql;
    """

    Postgrex.query!(pid, create_updated_at_function_statement, [])
  end

  defp create_updated_at_trigger(pid, table_name) do
    create_updated_at_trigger_statement = """
      CREATE TRIGGER set_#{table_name}_updated_at
      BEFORE UPDATE ON \"#{table_name}\"
      FOR EACH ROW
      EXECUTE PROCEDURE set_current_timestamp_updated_at();
    """

    Postgrex.query!(pid, create_updated_at_trigger_statement, [])
  end

  defp create_user_table(pid) do
    create_user_table_statement = """
      CREATE TABLE "user" (
        id SERIAL PRIMARY KEY,
        email citext UNIQUE NOT NULL,
        name VARCHAR  NOT NULL,
        age INTEGER DEFAULT 0,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
      );
    """

    Postgrex.query!(pid, create_user_table_statement, [])
  end

  defp create_todo_table(pid) do
    create_table_statement = """
      CREATE TABLE todo (
          id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
          user_id INTEGER REFERENCES "user"(id) ON DELETE CASCADE,
          description TEXT NOT NULL,
          due_date DATE,
          is_completed BOOLEAN DEFAULT FALSE,
          priority INTEGER DEFAULT 0,
          tags VARCHAR[] DEFAULT '{}'::VARCHAR[],
          rules JSONB,
          created_at TIMESTAMPTZ DEFAULT NOW(),
          updated_at TIMESTAMPTZ DEFAULT NOW()
      );
    """

    Postgrex.query!(pid, create_table_statement, [])
  end
end
