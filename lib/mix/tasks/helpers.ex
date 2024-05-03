defmodule Mix.Tasks.Walex.Helpers do
  @config %{
    hostname: "localhost",
    username: "postgres",
    password: "postgres",
    port: 5432
  }

  @moduledoc false
  def create_database(database_name) do
    "-c \"CREATE DATABASE #{database_name};\""
    |> database_cmd()
  end

  def drop_database(database_name) do
    "-c \"DROP DATABASE #{database_name};\""
    |> database_cmd()
  end

  def create_extension(pid, extension) do
    extension_query = "CREATE EXTENSION IF NOT EXISTS \"#{extension}\";"

    Postgrex.query!(pid, extension_query, [])
  end

  def database_cmd(cmd) do
    db_cmd = "psql " <> cmd

    env = [
      {"PGHOST", @config.hostname},
      {"PGUSER", @config.username},
      {"PGPASSWORD", @config.password},
      {"PGPORT", Integer.to_string(@config.port)}
    ]

    case System.shell(db_cmd, env: env) do
      {output, 0} ->
        output

      {output, _status} ->
        output
    end
  end
end
