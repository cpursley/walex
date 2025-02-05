defmodule WalEx.Events.EventModules do
  @moduledoc """
  Process events (call modules containing process functions)
  """
  use GenServer

  alias WalEx.Config.Registry

  def start_link(opts) do
    name =
      opts
      |> Keyword.get(:app_name)
      |> registry_name

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def process(txn, app_name) do
    name = registry_name(app_name)

    GenServer.call(name, {:process, txn, app_name}, :infinity)
  end

  defp registry_name(app_name) do
    Registry.set_name(:set_gen_server, __MODULE__, app_name)
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:process, txn, server}, _from, state) do
    resp =
      server
      |> WalEx.Config.get_configs(:modules)
      |> process_events(txn)

    {:reply, resp, state}
  end

  defp process_events(nil, %{changes: [], commit_timestamp: _}), do: :ok

  defp process_events(modules, txn) when is_list(modules) do
    process_modules(modules, txn)
  end

  defp process_modules(modules, txn) do
    functions = ~w(process_all process_insert process_update process_delete)a

    Enum.reduce_while(modules, :ok, fn module_name, _acc ->
      case process_module(module_name, functions, txn) do
        :ok -> {:cont, :ok}
        {:ok, _} = term -> {:cont, term}
        term -> {:halt, term}
      end
    end)
  end

  defp process_module(module_name, functions, txn) do
    Enum.reduce_while(functions, :ok, fn function, _acc ->
      case apply_process_macro(function, module_name, txn) do
        :ok -> {:cont, :ok}
        {:ok, _} = term -> {:cont, term}
        term -> {:halt, term}
      end
    end)
  end

  defp apply_process_macro(function, module, txn) do
    if Keyword.has_key?(module.__info__(:functions), function) do
      apply(module, function, [txn])
    else
      :ok
    end
  end
end
