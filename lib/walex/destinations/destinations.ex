defmodule WalEx.Destinations do
  @moduledoc """
  Process destinations
  """

  use GenServer

  alias WalEx.Replication.Progress
  alias WalEx.{Destinations, Config, Event, TransactionFilter}
  alias Config.Registry
  alias Destinations.{EventModules, EventRelay, Webhooks}
  alias WalEx.Changes.Transaction

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
  def handle_call({:process, txn, app_name}, _from, state) do
    process_destinations(txn, app_name)

    {:reply, :ok, state}
  end

  defp filter_subscribed(txn, app_name) do
    txn
    |> TransactionFilter.filter_subscribed(app_name)
    |> Event.cast_events(app_name)
  end

  defp process_destinations(%Transaction{lsn: lsn} = txn, app_name) do
    # TODO: EventModules should be dynamic (only if modules exist)
    EventModules.process(txn, app_name)

    filtered_events = filter_subscribed(txn, app_name)
    destinations = Config.get_configs(app_name, :destinations)

    if Config.has_config?(destinations, :webhooks) do
      process_webhooks(filtered_events, app_name)
    end

    if Config.has_config?(destinations, :event_relay_topic) do
      process_event_relay(filtered_events, app_name)
    end

    Progress.done(app_name, lsn)
  end

  defp process_event_relay([], _app_name), do: :ok

  defp process_event_relay(filtered_events, app_name) do
    event_relay_topic = Config.get_event_relay_topic(app_name)

    if is_binary(event_relay_topic) and event_relay_topic != "" do
      EventRelay.process(filtered_events, app_name)
    end
  end

  defp process_webhooks([], _app_name), do: :ok

  defp process_webhooks(filtered_events, app_name) do
    webhooks = Config.get_webhooks(app_name)

    if is_list(webhooks) and webhooks != [] do
      Webhooks.process(filtered_events, app_name)
    end
  end
end
