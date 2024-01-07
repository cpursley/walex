defmodule WalEx.Destinations.Supervisor do
  @moduledoc false

  use Supervisor

  alias WalEx.Config
  alias WalEx.Destinations
  alias Destinations.{EventModules, EventRelay, Webhooks}

  def start_link(opts) do
    app_name = Keyword.get(opts, :app_name)
    name = Config.Registry.set_name(:set_supervisor, __MODULE__, app_name)

    Supervisor.start_link(__MODULE__, configs: opts, name: name)
  end

  @impl true
  def init(opts) do
    app_name =
      opts
      |> Keyword.get(:configs)
      |> Keyword.get(:name)

    children =
      [{Destinations, app_name: app_name}]
      |> maybe_event_modules(app_name)
      |> maybe_webhooks(app_name)
      |> maybe_event_relay(app_name)

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp maybe_event_modules(children, app_name) do
    modules = Config.get_event_modules(app_name)
    has_module_config = is_list(modules) and modules != []

    maybe_set_child(children, has_module_config, {EventModules, app_name: app_name})
  end

  defp maybe_webhooks(children, app_name) do
    webhooks = Config.get_webhooks(app_name)
    has_webhook_config = is_list(webhooks) and webhooks != []

    maybe_set_child(children, has_webhook_config, {Webhooks, app_name: app_name})
  end

  defp maybe_event_relay(children, app_name) do
    event_relay = Config.get_event_relay_topic(app_name)
    has_event_relay_config = is_binary(event_relay) and event_relay != ""

    maybe_set_child(children, has_event_relay_config, {EventRelay, app_name: app_name})
  end

  defp maybe_set_child(children, true, child), do: children ++ [child]
  defp maybe_set_child(children, false, _child), do: children
end
