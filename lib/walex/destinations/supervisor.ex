defmodule WalEx.Destinations.Supervisor do
  @moduledoc false

  use Supervisor

  alias WalEx.Config
  alias WalEx.Destinations
  alias Destinations.EventModules

  def start_link(opts) do
    app_name = Keyword.get(opts, :name)
    name = Config.Registry.set_name(:set_supervisor, __MODULE__, app_name)

    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    app_name =
      opts
      |> Keyword.get(:name)

    children =
      [{Destinations, app_name: app_name}]
      |> maybe_event_modules(app_name)

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 10)
  end

  defp maybe_event_modules(children, app_name) do
    modules = Config.get_event_modules(app_name)
    has_module_config = is_list(modules) and modules != []

    maybe_set_child(children, has_module_config, {EventModules, app_name: app_name})
  end

  defp maybe_set_child(children, true, child), do: children ++ [child]
  defp maybe_set_child(children, false, _child), do: children
end
