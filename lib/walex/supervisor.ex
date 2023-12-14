defmodule WalEx.Supervisor do
  use Supervisor

  alias WalEx.Config, as: WalExConfig
  alias WalExConfig.Registry, as: WalExRegistry
  alias WalEx.Replication.Supervisor, as: ReplicationSupervisor
  alias WalEx.{Destinations, Events}
  alias Destinations.{EventRelay, Webhooks}

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    app_name = Keyword.get(opts, :name)
    modules = Keyword.get(opts, :modules, [])
    subscriptions = Keyword.get(opts, :subscriptions)
    module_names = WalExConfig.build_module_names(app_name, modules, subscriptions)
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

  defp validate_opts(opts) do
    db_configs = [:hostname, :username, :password, :port, :database]
    other_configs = [:subscriptions, :publication, :modules, :name]

    missing_db_configs =
      case Keyword.get(opts, :url) do
        nil ->
          Enum.filter(db_configs, &(not Keyword.has_key?(opts, &1)))

        _has_url ->
          []
      end

    missing_other_configs = Enum.filter(other_configs, &(not Keyword.has_key?(opts, &1)))
    missing_configs = missing_db_configs ++ missing_other_configs

    if not Enum.empty?(missing_configs) do
      raise "Following configs are missing: #{inspect(missing_configs)}"
    end
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
