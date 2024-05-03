# This file steals liberally from https://github.com/chasers/postgrex_replication_demo/blob/main/lib/replication.ex
# which in turn draws on https://hexdocs.pm/postgrex/Postgrex.ReplicationConnection.html#module-logical-replication

defmodule WalEx.Replication.Server do
  @moduledoc """
  This module is responsible for setting up the replication connection
  """
  use Postgrex.ReplicationConnection

  alias WalEx.Config.Registry, as: WalExRegistry
  alias WalEx.Decoder
  alias WalEx.Replication.Publisher
  alias WalEx.Replication.QueryBuilder

  def start_link(opts) do
    app_name = Keyword.get(opts, :app_name)
    opts = set_pgx_replication_conn_opts(app_name)

    Postgrex.ReplicationConnection.start_link(__MODULE__, [app_name: app_name], opts)
  end

  defp set_pgx_replication_conn_opts(app_name) do
    database_configs_keys = [
      :hostname,
      :username,
      :password,
      :port,
      :database,
      :ssl,
      :ssl_opts,
      :socket_options
    ]

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

    [slot_name: slot_name, publication: publication] =
      WalEx.Config.get_configs(app_name, [
        :slot_name,
        :publication
      ])

    state = %{
      step: :disconnected,
      app_name: app_name,
      slot_name: slot_name,
      publication: publication
    }

    {:ok, state}
  end

  @impl true
  def handle_connect(state) do
    query = QueryBuilder.publication_exists(state)
    {:query, query, %{state | step: :publication_exists}}
  end

  @impl true
  def handle_result([%Postgrex.Result{num_rows: 1}], state = %{step: :publication_exists}) do
    query = QueryBuilder.create_temporary_slot(state)
    {:query, query, %{state | step: :create_slot}}
  end

  @impl true
  def handle_result(results, %{step: :publication_exists}) do
    raise "Publication does not exist. #{inspect(results)}"
  end

  @impl true
  def handle_result([%Postgrex.Result{} | _results], state = %{step: :create_slot}) do
    query = QueryBuilder.start_replication_slot(state)
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
