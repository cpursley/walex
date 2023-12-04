defmodule WalEx.Events do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def process(txn, server) do
    GenServer.call(__MODULE__, {:process, txn, server}, :infinity)
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:process, txn, server}, _from, state) do
    server
    |> WalEx.Configs.get_configs([:modules])
    |> process_events(txn)

    {:reply, :ok, state}
  end

  defp process_events(nil, %{changes: [], commit_timestamp: _}), do: nil

  defp process_events([modules: modules], txn) when is_list(modules) do
    process_modules(modules, txn)
  end

  defp process_modules(modules, txn) do
    functions = ~w(process process_insert process_update process_delete)a

    Enum.each(modules, &process_module(&1, functions, txn))
  end

  defp process_module(module_name, functions, txn) do
    case Code.ensure_compiled(module_name) do
      {:module, module} ->
        Enum.each(functions, &apply_process_macro(&1, module, txn))

      {:error, :nofile} ->
        :ok
    end
  end

  defp apply_process_macro(function, module, txn) do
    if Keyword.has_key?(module.__info__(:functions), function) do
      apply(module, function, [txn])
    end
  end
end
