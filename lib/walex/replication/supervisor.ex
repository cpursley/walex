defmodule WalEx.Replication.Supervisor do
  @moduledoc false

  use Supervisor

  alias WalEx.Replication.Progress
  alias WalEx.Replication.{Publisher, Server}

  def start_link(opts) do
    app_name = Keyword.get(opts, :app_name)
    name = WalEx.Config.Registry.set_name(:set_supervisor, __MODULE__, app_name)

    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    app_name =
      opts
      |> Keyword.get(:app_name)

    children = [
      {Progress, app_name: app_name},
      {Publisher, app_name: app_name},
      {Server, app_name: app_name}
    ]

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 10)
  end
end
