defmodule WalEx.Replication.QueryBuilder do
  def create_temporary_slot(state) do
    "CREATE_REPLICATION_SLOT #{state.slot_name} TEMPORARY LOGICAL pgoutput NOEXPORT_SNAPSHOT;"
  end

  def start_replication_slot(state) do
    "START_REPLICATION SLOT #{state.slot_name} LOGICAL 0/0 (proto_version '1', publication_names '#{state.publication}')"
  end
end
