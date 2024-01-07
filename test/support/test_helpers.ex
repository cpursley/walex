defmodule WalEx.Support.TestHelpers do
  def find_worker_pid(supervisor_pid, child_module) do
    supervisor_pid
    |> Supervisor.which_children()
    |> find_pid(child_module)
  end

  defp find_pid(children, module_name) do
    {_, pid, _, _} = Enum.find(children, fn {module, _, _, _} -> module == module_name end)
    pid
  end

  def update_user(database_pid) do
    update_user = """
      UPDATE \"user\" SET age = 30 WHERE id = 1
    """

    Postgrex.query!(database_pid, update_user, [])
  end
end
