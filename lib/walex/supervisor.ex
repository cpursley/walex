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
    app_name = Keyword.get(opts, :name)
    modules = Keyword.get(opts, :modules, [])
    subscriptions = Keyword.get(opts, :subscriptions)

    supervisor_opts =
      opts
      |> Keyword.put(:modules, WalExConfigs.build_module_names(app_name, modules, subscriptions))

    validate_opts(supervisor_opts)

    {:ok, _pid} = WalEx.Registry.start_registry()

    name = WalEx.Registry.set_name(:set_supervisor, __MODULE__, app_name)

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

    missing_other_configs = Enum.filter(other_configs, &(not Keyword.has_key?(opts, &1)))

    missing_db_configs =
      case Keyword.get(opts, :url) do
        nil -> Enum.filter(db_configs, &(not Keyword.has_key?(opts, &1)))
        _has_url -> []
      end

    missing_configs = missing_db_configs ++ missing_other_configs

    if not Enum.empty?(missing_configs) do
      raise "Following configs are missing: #{inspect(missing_configs)}"
    end
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
