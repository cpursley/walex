defmodule WalEx.Supervisor do
  @moduledoc false

  use Supervisor

  alias WalEx.Config, as: WalExConfig
  alias WalEx.Destinations.Supervisor, as: DestinationsSupervisor
  alias WalEx.Replication.Supervisor, as: ReplicationSupervisor
  alias WalExConfig.Registry, as: WalExRegistry

  def start_link(opts) do
    app_name = Keyword.get(opts, :name)
    module_names = build_module_names(app_name, opts)
    supervisor_opts = Keyword.put(opts, :modules, module_names)

    validate_opts(supervisor_opts)

    {:ok, _pid} = WalExRegistry.start_registry()

    name = WalExRegistry.set_name(:set_supervisor, __MODULE__, app_name)

    Supervisor.start_link(__MODULE__, supervisor_opts, name: name)
  end

  @impl true
  def init(opts) do
    opts
    |> set_children()
    |> Supervisor.init(strategy: :one_for_one)
  end

  # TODO: EventModules should be dynamic (only if modules exist)
  defp build_module_names(app_name, opts) do
    modules = Keyword.get(opts, :modules, [])
    subscriptions = Keyword.get(opts, :subscriptions)

    WalExConfig.build_module_names(app_name, modules, subscriptions)
  end

  defp validate_opts(opts) do
    missing_configs = missing_db_configs(opts) ++ missing_event_configs(opts)

    unless Enum.empty?(missing_configs) do
      raise "Following required configs are missing: #{inspect(missing_configs)}"
    end
  end

  defp missing_db_configs(opts) do
    db_configs = [:hostname, :username, :password, :port, :database]

    case Keyword.get(opts, :url) do
      nil ->
        Enum.filter(db_configs, &(not Keyword.has_key?(opts, &1)))

      _has_url ->
        []
    end
  end

  defp missing_event_configs(opts) do
    other_configs = [:subscriptions, :publication, :name]

    Enum.filter(other_configs, &(not Keyword.has_key?(opts, &1)))
  end

  defp set_children(configs) do
    app_name = Keyword.get(configs, :name)

    [
      {WalExConfig, configs: configs},
      {ReplicationSupervisor, app_name: app_name},
      {DestinationsSupervisor, configs}
    ]
  end
end
