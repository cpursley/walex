# This file steals liberally from https://github.com/chasers/postgrex_replication_demo/blob/main/lib/replication.ex
# which in turn draws on https://hexdocs.pm/postgrex/Postgrex.ReplicationConnection.html#module-logical-replication

defmodule WalEx.ReplicationServer do
  use Postgrex.ReplicationConnection

  alias WalEx.Postgres.Decoder
  alias WalEx.ReplicationPublisher

  @publication Application.compile_env(:walex, WalEx)[:publication]

  def start_link(opts) do
    # Automatically reconnect if we lose connection.
    extra_opts = [
      auto_reconnect: true,
      name: __MODULE__
    ]

    Postgrex.ReplicationConnection.start_link(__MODULE__, :ok, extra_opts ++ opts)
  end

  @impl true
  def init(:ok) do
    IO.inspect("ReplicationServer init")
    {:ok, _pid} = ReplicationPublisher.start_link([])
    {:ok, %{step: :disconnected}}
  end

  @impl true
  def handle_connect(state) do
    IO.inspect("ReplicationServer handle_connect")
    query = "CREATE_REPLICATION_SLOT postgrex TEMPORARY LOGICAL pgoutput NOEXPORT_SNAPSHOT"
    {:query, query, %{state | step: :create_slot}}
  end

  @impl true
  def handle_result(results, %{step: :create_slot} = state) when is_list(results) do
    IO.inspect("ReplicationServer handle_result")

    query =
      "START_REPLICATION SLOT postgrex LOGICAL 0/0 (proto_version '1', publication_names '#{@publication}')"

    {:stream, query, [], %{state | step: :streaming}}
  end

  @impl true
  # https://www.postgresql.org/docs/14/protocol-replication.html
  def handle_data(<<?w, _wal_start::64, _wal_end::64, _clock::64, rest::binary>>, state) do
    IO.inspect("ReplicationServer handle_data 1")
    message = Decoder.decode_message(rest)

    ReplicationPublisher.process_message(message)

    {:noreply, state}
  end

  def handle_data(<<?k, wal_end::64, _clock::64, reply>>, state) do
    IO.inspect("ReplicationServer handle_data 2")

    messages =
      case reply do
        1 -> [<<?r, wal_end + 1::64, wal_end + 1::64, wal_end + 1::64, current_time()::64, 0>>]
        0 -> []
      end

    {:noreply, messages, state}
  end

  @epoch DateTime.to_unix(~U[2000-01-01 00:00:00Z], :microsecond)
  defp current_time(), do: System.os_time(:microsecond) - @epoch
end
