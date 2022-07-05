# This file steals liberally from https://github.com/supabase/realtime,
# which in turn draws on https://github.com/cainophile/cainophile

defmodule WalEx.Replication do
  defmodule(State,
    do:
      defstruct(
        relations: %{},
        transaction: nil,
        types: %{}
      )
  )

  use GenServer

  alias WalEx.Adapters.Postgres.EpgsqlServer
  alias WalEx.Events
  alias WalEx.Types

  alias WalEx.Adapters.Changes.{
    Transaction,
    NewRecord,
    UpdatedRecord,
    DeletedRecord,
    TruncatedRelation
  }

  alias WalEx.Adapters.Postgres.Decoder.Messages.{
    Begin,
    Commit,
    Relation,
    Insert,
    Update,
    Delete,
    Truncate,
    Type
  }

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, %State{}}
  end

  @doc """
  Database adapter's exit signal will be converted to {:EXIT, From, Reason}
  message when, for example, there's a database connection error.
  https://elixirschool.com/blog/til-genserver-handle-continue/
  """
  @impl true
  def handle_info({:epgsql, _pid, {:x_log_data, _start_lsn, _end_lsn, binary_msg}}, state) do
    decoded = WalEx.Adapters.Postgres.Decoder.decode_message(binary_msg)

    {:noreply, process_message(decoded, state)}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp process_message(%Begin{final_lsn: final_lsn, commit_timestamp: commit_timestamp}, state) do
    %State{
      state
      | transaction: {final_lsn, %Transaction{changes: [], commit_timestamp: commit_timestamp}}
    }
  end

  # FYI: this will be the last function called before returning to the client
  defp process_message(
         %Commit{lsn: commit_lsn, end_lsn: end_lsn},
         %State{
           transaction: {current_txn_lsn, _txn},
           relations: _relations
         } = state
       )
       when commit_lsn == current_txn_lsn do
    process_events(state)

    :ok = EpgsqlServer.acknowledge_lsn(end_lsn)

    %{state | transaction: nil}
  end

  # Any unknown types will now be populated into state.types
  # This will be utilised later on when updating unidentified data types
  defp process_message(%Type{} = msg, state) do
    %{state | types: Map.put(state.types, msg.id, msg.name)}
  end

  defp process_message(%Relation{} = msg, state) do
    updated_columns =
      Enum.map(msg.columns, fn message ->
        if Map.has_key?(state.types, message.type) do
          %{message | type: state.types[message.type]}
        else
          message
        end
      end)

    updated_relations = %{msg | columns: updated_columns}

    %{state | relations: Map.put(state.relations, msg.id, updated_relations)}
  end

  defp process_message(
         %Insert{relation_id: relation_id, tuple_data: tuple_data},
         %State{
           transaction: {lsn, %{commit_timestamp: commit_timestamp, changes: changes} = txn},
           relations: relations
         } = state
       )
       when is_map(relations) do
    case Map.fetch(relations, relation_id) do
      {:ok, %{columns: columns, namespace: namespace, name: name}} when is_list(columns) ->
        data = data_tuple_to_map(columns, tuple_data)

        new_record = %NewRecord{
          type: "INSERT",
          schema: namespace,
          table: name,
          columns: columns,
          record: data,
          commit_timestamp: commit_timestamp
        }

        %State{state | transaction: {lsn, %{txn | changes: [new_record | changes]}}}

      _ ->
        state
    end
  end

  defp process_message(
         %Update{
           relation_id: relation_id,
           old_tuple_data: old_tuple_data,
           tuple_data: tuple_data
         },
         %State{
           relations: relations,
           transaction: {lsn, %{commit_timestamp: commit_timestamp, changes: changes} = txn}
         } = state
       )
       when is_map(relations) do
    case Map.fetch(relations, relation_id) do
      {:ok, %{columns: columns, namespace: namespace, name: name}} when is_list(columns) ->
        old_data = data_tuple_to_map(columns, old_tuple_data)
        data = data_tuple_to_map(columns, tuple_data)

        updated_record = %UpdatedRecord{
          type: "UPDATE",
          schema: namespace,
          table: name,
          columns: columns,
          old_record: old_data,
          record: data,
          commit_timestamp: commit_timestamp
        }

        %State{
          state
          | transaction: {lsn, %{txn | changes: [updated_record | changes]}}
        }

      _ ->
        state
    end
  end

  defp process_message(
         %Delete{
           relation_id: relation_id,
           old_tuple_data: old_tuple_data,
           changed_key_tuple_data: changed_key_tuple_data
         },
         %State{
           relations: relations,
           transaction: {lsn, %{commit_timestamp: commit_timestamp, changes: changes} = txn}
         } = state
       )
       when is_map(relations) do
    case Map.fetch(relations, relation_id) do
      {:ok, %{columns: columns, namespace: namespace, name: name}} when is_list(columns) ->
        data = data_tuple_to_map(columns, old_tuple_data || changed_key_tuple_data)

        deleted_record = %DeletedRecord{
          type: "DELETE",
          schema: namespace,
          table: name,
          columns: columns,
          old_record: data,
          commit_timestamp: commit_timestamp
        }

        %State{state | transaction: {lsn, %{txn | changes: [deleted_record | changes]}}}

      _ ->
        state
    end
  end

  defp process_message(
         %Truncate{truncated_relations: truncated_relations},
         %State{
           relations: relations,
           transaction: {lsn, %{commit_timestamp: commit_timestamp, changes: changes} = txn}
         } = state
       )
       when is_list(truncated_relations) and is_list(changes) and is_map(relations) do
    new_changes =
      Enum.reduce(truncated_relations, changes, fn truncated_relation, acc ->
        case Map.fetch(relations, truncated_relation) do
          {:ok, %{namespace: namespace, name: name}} ->
            [
              %TruncatedRelation{
                type: "TRUNCATE",
                schema: namespace,
                table: name,
                commit_timestamp: commit_timestamp
              }
              | acc
            ]

          _ ->
            acc
        end
      end)

    %State{
      state
      | transaction: {lsn, %{txn | changes: new_changes}}
    }
  end

  defp process_message(_msg, state) do
    state
  end

  defp data_tuple_to_map(columns, tuple_data) when is_list(columns) and is_tuple(tuple_data) do
    columns
    |> Enum.with_index()
    |> Enum.reduce_while(%{}, fn {column_map, index}, acc ->
      case column_map do
        %Relation.Column{name: column_name, type: column_type}
        when is_binary(column_name) and is_binary(column_type) ->
          try do
            {:ok, Kernel.elem(tuple_data, index)}
          rescue
            ArgumentError -> :error
          end
          |> case do
            {:ok, record} ->
              {:cont, Map.put(acc, column_name, Types.cast_record(record, column_type))}

            :error ->
              {:halt, acc}
          end

        _ ->
          {:cont, acc}
      end
    end)
    |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
  end

  defp data_tuple_to_map(_columns, _tuple_data), do: %{}

  # defp cast_record("t", "bool"), do: true
  # defp cast_record("f", "bool"), do: false

  # defp cast_record(record, "int2") when is_binary(record), do: String.to_integer(record)
  # defp cast_record(record, "int4") when is_binary(record), do: String.to_integer(record)
  # defp cast_record(record, "int8") when is_binary(record), do: String.to_integer(record)

  # defp cast_record(record, "numeric") when is_binary(record) do
  #   if String.contains?(record, ".") do
  #     String.to_float(record)
  #   else
  #     String.to_integer(record)
  #   end
  # end

  # defp cast_record(record, "timestamp") when is_binary(record) do
  #   with {:ok, %NaiveDateTime{} = naive_date_time} <- Timex.parse(record, "{RFC3339}"),
  #        %DateTime{} = date_time <- Timex.to_datetime(naive_date_time) do
  #     date_time
  #   else
  #     _ -> record
  #   end
  # end

  # defp cast_record(record, "timestamptz") when is_binary(record) do
  #   case Timex.parse(record, "{RFC3339}") do
  #     {:ok, %DateTime{} = date_time} ->
  #       date_time

  #     _ ->
  #       record
  #   end
  # end

  # defp cast_record(record, "json") when is_binary(record) do
  #   case Jason.decode(record) do
  #     {:ok, json} ->
  #       Jason.decode!(json)

  #     _ ->
  #       record
  #   end
  # end

  # defp cast_record(record, "jsonb") when is_binary(record) do
  #   case Jason.decode(record) do
  #     {:ok, json} ->
  #       json

  #     _ ->
  #       record
  #   end
  # end

  # # Integer Array - this assumes a single non-nested array
  # # This is brittle, I imagine there's a safer way to handle arrays..
  # defp cast_record(<<123>> <> record, "_int4") when is_binary(record) do
  #   record
  #   |> String.replace(["{", "}"], "")
  #   |> String.split(",")
  #   |> Enum.map(&String.to_integer/1)
  # end

  # # Text Array - this assumes a single non-nested array
  # defp cast_record(<<123>> <> record, "_text") when is_binary(record) do
  #   record
  #   |> String.replace(["{", "}"], "")
  #   |> String.split(",")
  # end

  # # TODO: Before extracting out WalEx, create a dynamic function that can take custom decoders
  # defp cast_record(record, "geography") when is_binary(record) do
  #   case Geo.WKB.decode(record) do
  #     {:ok, geo} ->
  #       geo

  #     _ ->
  #       record
  #   end
  # end

  # defp cast_record(record, _column_type) do
  #   record
  # end

  # can we pass Events.process so that we can extract this out to lib?
  defp process_events(%State{transaction: {_current_txn_lsn, txn}}) do
    Events.process(txn)
  end
end
