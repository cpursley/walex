defmodule WalEx.Support.TestHelpers do
  def find_worker_pid(supervisor_pid, child_module) do
    case Supervisor.which_children(supervisor_pid) do
      children when is_list(children) ->
        find_pid(children, child_module)

      _ ->
        {:error, :supervisor_not_running}
    end
  end

  defp find_pid(children, module_name) do
    {_, pid, _, _} = Enum.find(children, fn {module, _, _, _} -> module == module_name end)
    pid
  end
end
