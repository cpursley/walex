defmodule WalEx.Replication.QueryBuilder do
  def publication_exists(%{publication: publication}) do
    "SELECT 1 FROM pg_publication WHERE pubname = '#{publication}' LIMIT 1;"
  end

  def slot_exists(%{slot_name: slot_name}) do
    "SELECT active FROM pg_replication_slots WHERE slot_name = '#{slot_name}' LIMIT 1;"
  end

  def create_temporary_slot(%{slot_name: slot_name}) do
    "CREATE_REPLICATION_SLOT #{slot_name} TEMPORARY LOGICAL pgoutput NOEXPORT_SNAPSHOT;"
  end

  def create_durable_slot(%{slot_name: slot_name}) do
    "CREATE_REPLICATION_SLOT #{slot_name} LOGICAL pgoutput NOEXPORT_SNAPSHOT;"
  end

  def start_replication_slot(%{slot_name: slot_name, publication: publication}) do
    "START_REPLICATION SLOT #{slot_name} LOGICAL 0/0 (proto_version '1', publication_names '#{publication}')"
  end
end
