defmodule WalEx.Destinations.Supervisor do
  @moduledoc false

  use Supervisor

  alias WalEx.Config
  alias WalEx.Destinations
  alias Destinations.{EventModules, EventRelay, Webhooks}

  def start_link(opts) do
    app_name = Keyword.get(opts, :app_name)
    name = WalEx.Config.Registry.set_name(:set_supervisor, __MODULE__, app_name)

    Supervisor.start_link(__MODULE__, configs: opts, name: name)
  end

  @impl true
  def init(opts) do
    configs = Keyword.get(opts, :configs)
    app_name = Keyword.get(configs, :name)

    children =
      [
        {Destinations, app_name: app_name},
        # TODO: EventModules should be dynamic (only if modules exist)
        {EventModules, app_name: app_name}
      ]
      |> maybe_webhooks(configs)
      |> maybe_event_relay(configs)

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp maybe_webhooks(children, configs) do
    app_name = Keyword.get(configs, :name)
    destinations = Keyword.get(configs, :destinations)
    has_webhook_config = Config.has_config?(destinations, :webhooks)

    maybe_set_child(children, has_webhook_config, {Webhooks, app_name: app_name})
  end

  defp maybe_event_relay(children, configs) do
    app_name = Keyword.get(configs, :name)
    destinations = Keyword.get(configs, :destinations)
    has_event_relay_config = Config.has_config?(destinations, :event_relay_topic)

    maybe_set_child(children, has_event_relay_config, {EventRelay, app_name: app_name})
  end

  defp maybe_set_child(children, true, child), do: children ++ [child]
  defp maybe_set_child(children, false, _child), do: children
end
