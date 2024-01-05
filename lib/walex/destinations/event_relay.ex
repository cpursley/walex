defmodule WalEx.Destinations.EventRelay do
  @moduledoc """
  Responsible for sending events to EventRelay: https://github.com/eventrelay/eventrelay
  """
  use GenServer
  require Logger

  alias ERWeb.Grpc.Eventrelay
  alias Eventrelay.Events.Stub, as: Client
  alias Eventrelay.{NewEvent, PublishEventsRequest}

  alias WalEx.{Config, Helpers}
  alias Config.Registry

  def start_link(opts) do
    name =
      opts
      |> Keyword.get(:app_name)
      |> registry_name

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def process(changes, app_name) do
    name = registry_name(app_name)

    GenServer.call(name, {:process, changes, app_name}, :infinity)
  end

  defp registry_name(app_name) do
    Registry.set_name(:set_gen_server, __MODULE__, app_name)
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:process, changes, app_name}, _from, state) do
    process_events(changes, app_name)

    {:reply, :ok, state}
  end

  def process_events(changes, app_name) do
    case connect(app_name) do
      {:ok, channel} ->
        topic = Helpers.get_event_relay_topic(app_name)
        events = build_events(changes)

        request =
          %PublishEventsRequest{
            topic: topic,
            durable: true,
            events: events
          }

        Client.publish_events(channel, request)

      error ->
        Logger.error("EventRelay.process_events error=#{inspect(error)}")
        error
    end
  end

  defp connect(app_name) do
    config = Config.get_configs(app_name, :event_relay)
    host = Keyword.get(config, :host)
    port = Keyword.get(config, :port)
    token = Keyword.get(config, :token)

    GRPC.Stub.connect("#{host}:#{port}", headers: [{"authorization", "Bearer #{token}"}])
  end

  def build_events(changes) do
    changes
    |> Enum.map(&Map.from_struct(&1))
    |> Enum.map(&build_event(&1))
  end

  def build_event(event = %{type: type, source: %{table: table}}) do
    case Jason.encode(event) do
      {:ok, data} ->
        source = Helpers.set_source()
        name = Helpers.set_type(table, type)

        %NewEvent{
          source: source,
          name: name,
          data: data
        }

      error ->
        Logger.error("EventRelay.process_events error=#{inspect(error)}")
    end
  end
end
