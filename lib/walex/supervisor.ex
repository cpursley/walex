defmodule WalEx.Supervisor do
  use Supervisor

  @config Application.compile_env(:walex, WalEx)

  def child_spec(config) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [config]}
    }
  end

  def start_link(config) do
    Supervisor.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
      {
        WalEx.DatabaseReplicationSupervisor,
        hostname: @config[:hostname],
        username: @config[:username],
        password: @config[:password],
        port: @config[:port],
        database: @config[:database],
        subscriptions: @config[:subscriptions],
        publication: @config[:publication]
      },
      {
        WalEx.Events,
        module: @config[:modules]
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
