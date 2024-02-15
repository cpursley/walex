defmodule WalEx.Config.Registry do
  @moduledoc """
  Configuration Registry
  """

  @walex_registry :walex_registry

  require Logger

  def start_registry do
    Logger.info("Starting Registry")

    case Process.whereis(@walex_registry) do
      nil ->
        Logger.info("No registry found, starting new one")
        Registry.start_link(keys: :unique, name: @walex_registry)

      pid ->
        Logger.info("Registry already running with pid: #{inspect(pid)}")
        {:ok, pid}
    end
  end

  def set_name(:set_agent, module, app_name), do: set_name(module, app_name)
  def set_name(:set_gen_server, module, app_name), do: set_name(module, app_name)
  def set_name(:set_supervisor, module, app_name), do: set_name(module, app_name)

  defp set_name(module, app_name), do: {:via, Registry, {@walex_registry, {module, app_name}}}

  def get_state(:get_agent, module, app_name) do
    Agent.get({:via, Registry, {@walex_registry, {module, app_name}}}, & &1)
  end
end
