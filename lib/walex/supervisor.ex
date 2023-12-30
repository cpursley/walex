defmodule WalEx.Supervisor do
  @moduledoc false

  use Supervisor

  alias WalEx.Config, as: WalExConfig
  alias WalEx.Replication.Supervisor, as: ReplicationSupervisor
  alias WalEx.{Destinations, Events}
  alias WalExConfig.Registry, as: WalExRegistry
  alias Destinations.{EventRelay, Webhooks}

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    app_name = Keyword.get(opts, :name)
    module_names = build_module_names(app_name, opts)
    supervisor_opts = Keyword.put(opts, :modules, module_names)

    validate_opts(supervisor_opts)

    {:ok, _pid} = WalExRegistry.start_registry()

    name = WalExRegistry.set_name(:set_supervisor, __MODULE__, app_name)

    Supervisor.start_link(__MODULE__, configs: supervisor_opts, name: name)
  end

  @impl true
  def init(opts) do
    opts
    |> set_children()
    |> Supervisor.init(strategy: :one_for_one)
  end

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

  defp set_children(opts) do
    configs = Keyword.get(opts, :configs)
    app_name = Keyword.get(configs, :name)

    walex_configs = [{WalExConfig, configs: configs}]
    walex_db_replication_supervisor = [{ReplicationSupervisor, app_name: app_name}]
    walex_event = process_check(Events, [{Events, []}])
    destinations = process_check(Destinations, [{Destinations, []}])
    webhooks = process_check(Webhooks, [{Webhooks, []}])
    event_relay = process_check(EventRelay, [{EventRelay, []}])

    walex_configs ++
      walex_db_replication_supervisor ++
      walex_event ++
      destinations ++
      webhooks ++
      event_relay
  end

  defp process_check(module, default) do
    case Process.whereis(module) do
      nil ->
        default

      _ ->
        []
    end
  end
end
