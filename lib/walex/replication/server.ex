# This file steals liberally from https://github.com/chasers/postgrex_replication_demo/blob/main/lib/replication.ex
# which in turn draws on https://hexdocs.pm/postgrex/Postgrex.ReplicationConnection.html#module-logical-replication

defmodule WalEx.Replication.Server do
  @moduledoc """
  This module is responsible for setting up the replication connection
  """

  use Postgrex.ReplicationConnection

  alias WalEx.Config.Registry, as: WalExRegistry
  alias WalEx.Postgres.Decoder
  alias WalEx.Replication.Publisher

  def start_link(opts) do
    app_name = Keyword.get(opts, :app_name)
    opts = set_pgx_replication_conn_opts(app_name)

    Postgrex.ReplicationConnection.start_link(__MODULE__, [app_name: app_name], opts)
  end

  defp set_pgx_replication_conn_opts(app_name) do
    database_configs_keys = [:hostname, :username, :password, :port, :database, :ssl, :ssl_opts]
    extra_opts = [auto_reconnect: true]
    database_configs = WalEx.Config.get_configs(app_name, database_configs_keys)

    replications_name = [
      name: WalExRegistry.set_name(:set_gen_server, __MODULE__, app_name)
    ]

    extra_opts ++ database_configs ++ replications_name
  end

  @impl true
  def init(opts) do
    app_name = Keyword.get(opts, :app_name)

    if is_nil(Process.whereis(Publisher)) do
      {:ok, _pid} = Publisher.start_link([])
    end

    {:ok, %{step: :disconnected, app_name: app_name}}
  end

  @impl true
  def handle_connect(state) do
    temp_slot = "walex_temp_slot_" <> Integer.to_string(:rand.uniform(9_999))

    query = "CREATE_REPLICATION_SLOT #{temp_slot} TEMPORARY LOGICAL pgoutput NOEXPORT_SNAPSHOT;"

    {:query, query, %{state | step: :create_slot}}
  end

  @impl true
  def handle_result([%Postgrex.Result{rows: rows} | _results], state = %{step: :create_slot}) do
    slot_name = rows |> hd |> hd

    publication =
      state.app_name
      |> WalEx.Config.get_configs([:publication])
      |> Keyword.get(:publication)

    query =
      "START_REPLICATION SLOT #{slot_name} LOGICAL 0/0 (proto_version '1', publication_names '#{publication}')"

    {:stream, query, [], %{state | step: :streaming}}
  end

  @impl true
  # https://www.postgresql.org/docs/14/protocol-replication.html
  def handle_data(<<?w, _wal_start::64, _wal_end::64, _clock::64, rest::binary>>, state) do
    rest
    |> Decoder.decode_message()
    |> Publisher.process_message(state.app_name)

    {:noreply, state}
  end

  def handle_data(<<?k, wal_end::64, _clock::64, reply>>, state) do
    messages =
      case reply do
        1 -> [<<?r, wal_end + 1::64, wal_end + 1::64, wal_end + 1::64, current_time()::64, 0>>]
        0 -> []
      end

    {:noreply, messages, state}
  end

  @epoch DateTime.to_unix(~U[2000-01-01 00:00:00Z], :microsecond)
  defp current_time, do: System.os_time(:microsecond) - @epoch
end
