defmodule WalEx.Supervisor do
  use Supervisor

  alias WalEx.Configs, as: WalExConfigs
  alias WalEx.DatabaseReplicationSupervisor
  alias WalEx.Events

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    WalEx.Registry.start_registry()

    app_name = Keyword.get(opts, :name)

    name = WalEx.Registry.set_name(:set_supervisor, __MODULE__, app_name)

    Supervisor.start_link(__MODULE__, configs: opts, name: name)
  end

  @impl true
  def init(opts) do
    opts
    |> set_children()
    |> Supervisor.init(strategy: :one_for_one)
  end

  defp set_children(opts) do
    configs = Keyword.get(opts, :configs)
    app_name = Keyword.get(configs, :name)

    walex_configs = [{WalExConfigs, configs: configs}]
    walex_db_replication_supervisor = [{DatabaseReplicationSupervisor, app_name: app_name}]
    walex_event = if is_nil(Process.whereis(Events)), do: [{Events, []}], else: []

    walex_configs ++ walex_db_replication_supervisor ++ walex_event
  end
end
