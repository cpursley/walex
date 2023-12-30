defmodule WalEx.Destinations do
  @moduledoc """
  Process destinations
  """

  use GenServer

  alias WalEx.{Destinations, Event, Helpers, TransactionFilter}
  alias Destinations.{EventRelay, Webhooks}

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def process(txn, app_name) do
    GenServer.call(__MODULE__, {:process, txn, app_name}, :infinity)
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

  defp process_destinations(txn, app_name) do
    filtered_events = filter_subscribed(txn, app_name)

    process_event_relay(filtered_events, app_name)
    process_webhooks(filtered_events, app_name)
  end

  defp process_event_relay([], _app_name), do: :ok

  defp process_event_relay(filtered_events, app_name) do
    event_relay_topic = Helpers.get_event_relay_topic(app_name)

    if is_binary(event_relay_topic) and event_relay_topic != "" do
      EventRelay.process(filtered_events, app_name)
    end
  end

  defp process_webhooks([], _app_name), do: :ok

  defp process_webhooks(filtered_events, app_name) do
    webhooks = Helpers.get_webhooks(app_name)

    if is_list(webhooks) and webhooks != [] do
      Webhooks.process(filtered_events, app_name)
    end
  end
end
