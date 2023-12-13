defmodule WalEx.Destinations do
  use GenServer

  alias WalEx.{Event, TransactionFilter}
  alias WalEx.Destinations.Webhooks

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
    txn
    |> filter_subscribed(app_name)
    |> Webhooks.process(app_name)

    {:reply, :ok, state}
  end

  defp filter_subscribed(txn, app_name) do
    txn
    |> TransactionFilter.filter_subscribed(app_name)
    |> Enum.map(&Event.cast(&1))
  end
end
