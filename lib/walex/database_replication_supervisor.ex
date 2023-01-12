defmodule WalEx.DatabaseReplicationSupervisor do
  use Supervisor

  def start_link(config) do
    Supervisor.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(config) do
    children = [{WalEx.ReplicationServer, config}]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
