defmodule WalEx.Replication.Supervisor do
  use Supervisor

  alias WalEx.Replication.Server

  def start_link(opts) do
    app_name = Keyword.get(opts, :app_name)
    name = WalEx.Config.Registry.set_name(:set_supervisor, __MODULE__, app_name)

    Supervisor.start_link(__MODULE__, configs: opts, name: name)
  end

  @impl true
  def init(opts) do
    app_name =
      opts
      |> Keyword.get(:configs)
      |> Keyword.get(:app_name)

    children = [{Server, app_name: app_name}]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
