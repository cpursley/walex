defmodule WalEx.Destinations do
  use GenServer

  alias WalEx.{Event, TransactionFilter}
  alias WalEx.Destinations.{EventRelay, Helpers, Webhooks}

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
    filtered_events = filter_subscribed(txn, app_name)

    if is_list(filtered_events) and filtered_events != [] do
      if is_binary(Helpers.get_event_relay_topic(app_name)) != "" do
        EventRelay.process(filtered_events, app_name)
      end

      if is_list(Helpers.get_webhooks(app_name)) != [] do
        Webhooks.process(filtered_events, app_name)
      end
    end

    {:reply, :ok, state}
  end

  defp filter_subscribed(txn, app_name) do
    txn
    |> TransactionFilter.filter_subscribed(app_name)
    |> Enum.map(&Event.cast(&1))
  end
end
