defmodule WalEx.Replication.QueryBuilder do
  def publication_exists(state) do
    "SELECT 1 FROM pg_publication WHERE pubname = '#{state.publication}' LIMIT 1;"
  end

  def slot_exists(state) do
    "SELECT active FROM pg_replication_slots WHERE slot_name = '#{state.slot_name}' LIMIT 1;"
  end

  def create_temporary_slot(state) do
    "CREATE_REPLICATION_SLOT #{state.slot_name} TEMPORARY LOGICAL pgoutput NOEXPORT_SNAPSHOT;"
  end

  def create_durable_slot(state) do
    "CREATE_REPLICATION_SLOT #{state.slot_name} LOGICAL pgoutput NOEXPORT_SNAPSHOT;"
  end

  def start_replication_slot(state) do
    "START_REPLICATION SLOT #{state.slot_name} LOGICAL 0/0 (proto_version '1', publication_names '#{state.publication}')"
  end
end
