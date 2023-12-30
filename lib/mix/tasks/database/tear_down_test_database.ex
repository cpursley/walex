defmodule Mix.Tasks.TearDownTestDatabase do
  @moduledoc false

  use Mix.Task

  alias Mix.Tasks.Helpers

  @test_database "todos_test"

  @shortdoc "Tear down test database and tables"
  def run(_) do
    Mix.Task.run("app.start")
    Helpers.drop_database(@test_database)
  end
end
