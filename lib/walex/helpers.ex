defmodule WalEx.Helpers do
  @moduledoc """
  Helper functions for WalEx
  """
  def set_type(table, :insert), do: to_string(table) <> ".insert"
  def set_type(table, :update), do: to_string(table) <> ".update"
  def set_type(table, :delete), do: to_string(table) <> ".delete"

  def set_source, do: get_source_name() <> "/" <> get_source_version()

  def get_source_name, do: "WalEx"

  def get_source_version, do: Application.spec(:walex)[:vsn] |> to_string()
end
