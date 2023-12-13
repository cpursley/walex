defmodule WalEx.Destinations.Webhooks do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def process(changes, app_name) do
    GenServer.call(__MODULE__, {:process, changes, app_name}, :infinity)
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

  defp process_events(changes, app_name), do: Enum.map(changes, &process_event(&1, app_name))

  defp process_event(change, app_name) do
    webhooks = get_webhooks(app_name)
    signing_secret = get_signing_secret(app_name)

    send_webhooks(webhooks, signing_secret, change)
  end

  defp get_webhooks(app_name) do
    case WalEx.Config.get_configs(app_name, :destinations) do
      destinations when is_list(destinations) and destinations != [] ->
        destinations
        |> Keyword.get(:webhooks, nil)

      _ ->
        nil
    end
  end

  defp get_signing_secret(app_name),
    do: WalEx.Config.get_configs(app_name, :webhook_signing_secret)

  defp send_webhooks(nil, _signing_secret, _change), do: :ok

  defp send_webhooks(webhooks, signing_secret, change) do
    Enum.each(webhooks, &send_webhook(&1, signing_secret, change))
  end

  defp send_webhook(webhook_url, signing_secret, change) do
    body = set_body(change)

    headers =
      body
      |> Jason.encode!()
      |> set_headers(signing_secret)

    Req.post!(webhook_url, json: body, headers: headers)
  end

  defp set_body(event = %{table: table, type: type}) do
    table
    |> set_type(type)
    |> event_body(event)
  end

  defp set_type(table, :insert), do: to_string(table) <> ".created"
  defp set_type(table, :update), do: to_string(table) <> ".updated"
  defp set_type(table, :delete), do: to_string(table) <> ".updated"

  def event_body(type, data) do
    event_id = Uniq.UUID.uuid4()
    timestamp = Timex.now() |> Timex.format!("{ISO:Extended:Z}")

    %{
      id: event_id,
      type: type,
      data: Map.from_struct(data),
      timestamp: timestamp
    }
  end

  defp set_headers(body, signing_secret) do
    user_agent = set_user_agent()
    signature = generate_signature(body, signing_secret)

    [
      "Content-Type": "application/json",
      "User-Agent": user_agent,
      signature: signature
    ]
  end

  defp generate_signature(body, signing_secret) do
    :crypto.mac(:hmac, :sha256, signing_secret, body)
    |> Base.encode64()
  end

  defp set_user_agent(agent \\ "WalEx/"), do: agent <> walex_version()

  defp walex_version, do: Application.spec(:walex)[:vsn] |> to_string()
end
