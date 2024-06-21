defmodule WalEx.Destinations do
  @moduledoc """
  Process destinations
  """

  use GenServer

  alias WalEx.{Destinations, Config}
  alias Config.Registry
  alias Destinations.EventModules

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

  defp process_destinations(txn, app_name) do
    # TODO: EventModules should be dynamic (only if modules exist)
    EventModules.process(txn, app_name)
  end
end
