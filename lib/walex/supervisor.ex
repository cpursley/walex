defmodule WalEx.Supervisor do
  use Supervisor

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
    # Hostname must be a char list for some reason
    # Use this var to convert to sigil at connection
    host = Application.get_env(:walex, :db_host)

    epgsql_params = %{
      host: ~c(#{host}),
      username: Application.get_env(:walex, :db_user),
      database: Application.get_env(:walex, :db_name),
      password: Application.get_env(:walex, :db_password),
      port: Application.get_env(:walex, :db_port),
      ssl: Application.get_env(:walex, :db_ssl)
    }

    epgsql_params =
      with {:ok, ip_version} <- Application.get_env(:walex, :db_ip_version),
           {:error, :einval} <- :inet.parse_address(epgsql_params.host) do
        # only add :tcp_opts to epgsql_params when ip_version is present and host
        # is not an IP address.
        Map.put(epgsql_params, :tcp_opts, [ip_version])
      else
        _ -> epgsql_params
      end

    publications = Application.get_env(:walex, :publications)

    # Use a named replication slot if you want services to pickup from where
    # it left after a restart because of, for example, a crash.
    # This will always be converted to lower-case.
    # You can get a list of active replication slots with
    # `select * from pg_replication_slots`
    slot_name = Application.get_env(:walex, :slot_name)

    max_replication_lag_in_mb = Application.get_env(:walex, :max_replication_lag_in_mb)

    modules = Application.get_env(:walex, :modules)

    children = [
      # Listener
      {
        WalEx.DatabaseReplicationSupervisor,
        # You can provide a different WAL position if desired, or default to
        # allowing Postgres to send you what it thinks you need
        epgsql_params: epgsql_params,
        publications: publications,
        slot_name: slot_name,
        wal_position: {"0", "0"},
        max_replication_lag_in_mb: max_replication_lag_in_mb
      },
      # Events
      {
        WalEx.Events,
        module: modules
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
