defmodule WalEx.Helpers do
  alias WalEx.Config

  def set_type(table, :insert), do: to_string(table) <> ".insert"
  def set_type(table, :update), do: to_string(table) <> ".update"
  def set_type(table, :delete), do: to_string(table) <> ".delete"

  def set_source, do: get_source_name() <> "/" <> get_source_version()

  def get_source_name, do: "WalEx"

  def get_source_version, do: Application.spec(:walex)[:vsn] |> to_string()

  def get_database(app_name), do: Config.get_configs(app_name, :database)

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
