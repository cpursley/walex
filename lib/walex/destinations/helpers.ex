defmodule WalEx.Destinations.Helpers do
  alias WalEx.Config

  def set_source(source \\ "WalEx/") do
    walex_version = Application.spec(:walex)[:vsn] |> to_string()

    source <> walex_version
  end

  def set_type(table, :insert), do: to_string(table) <> ".created"
  def set_type(table, :update), do: to_string(table) <> ".updated"
  def set_type(table, :delete), do: to_string(table) <> ".deleted"

  def get_destination(app_name, destination) do
    case Config.get_configs(app_name, :destinations) do
      destinations when is_list(destinations) and destinations != [] ->
        destinations
        |> Keyword.get(destination, nil)

      _ ->
        nil
    end
  end

  def get_webhooks(app_name), do: get_destination(app_name, :webhooks)
  def get_event_relay_topic(app_name), do: get_destination(app_name, :event_relay_topic)
end
