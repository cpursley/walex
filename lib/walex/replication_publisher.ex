# This file steals liberally from https://github.com/supabase/realtime,
# which in turn draws on https://github.com/cainophile/cainophile

defmodule WalEx.ReplicationPublisher do
  @moduledoc """
  Publishes messages from Replication to Events
  """
  defmodule(State,
    do:
      defstruct(
        relations: %{},
        transaction: nil,
        types: %{}
      )
  )

  defstruct [:relations]

  use GenServer

  alias WalEx.{Events, Types}
  alias WalEx.Changes
  alias WalEx.Postgres.Decoder.Messages

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def process_message(message) do
    GenServer.cast(__MODULE__, {:message, message})
  end

  @impl true
  def init(_) do
    IO.inspect("ReplicationPublisher init")
    Process.flag(:message_queue_data, :off_heap)

    {:ok, %State{}}
  end

  @impl true
  def handle_cast(
        {:message, %Messages.Begin{final_lsn: final_lsn, commit_timestamp: commit_timestamp}},
        state
      ) do
    IO.inspect("ReplicationPublisher handle_cast Messages.Begin")

    updated_state = %State{
      state
      | transaction: {
          final_lsn,
          %Changes.Transaction{changes: [], commit_timestamp: commit_timestamp}
        }
    }

    {:noreply, updated_state}
  end

  @impl true
  def handle_cast(
        {:message, %Messages.Commit{lsn: commit_lsn}},
        %State{transaction: {current_txn_lsn, txn}, relations: _relations} = state
      )
      when commit_lsn == current_txn_lsn do
    IO.inspect("ReplicationPublisher handle_cast Messages.Commit")
    Events.process(txn)

    %{state | transaction: nil}

    {:noreply, state}
  end

  @impl true
  def handle_cast({:message, %Messages.Type{} = msg}, state) do
    IO.inspect("ReplicationPublisher handle_cast Messages.Type")
    updated_state = %{state | types: Map.put(state.types, msg.id, msg.name)}

    {:noreply, updated_state}
  end

  @impl true
  def handle_cast({:message, %Messages.Relation{} = msg}, state) do
    IO.inspect("ReplicationPublisher handle_cast Messages.Relation")

    updated_columns =
      Enum.map(msg.columns, fn message ->
        if Map.has_key?(state.types, message.type) do
          %{message | type: state.types[message.type]}
        else
          message
        end
      end)

    updated_relations = %{msg | columns: updated_columns}
    updated_state = %{state | relations: Map.put(state.relations, msg.id, updated_relations)}

    {:noreply, updated_state}
  end

  @impl true
  def handle_cast(
        {:message, %Messages.Insert{relation_id: relation_id, tuple_data: tuple_data}},
        %State{
          transaction: {lsn, %{commit_timestamp: commit_timestamp, changes: changes} = txn},
          relations: relations
        } = state
      )
      when is_map(relations) do
    IO.inspect("ReplicationPublisher handle_cast Messages.Insert")

    case Map.fetch(relations, relation_id) do
      {:ok, %{columns: columns, namespace: namespace, name: name}} when is_list(columns) ->
        data = data_tuple_to_map(columns, tuple_data) |> IO.inspect()

        new_record = %Changes.NewRecord{
          type: "INSERT",
          schema: namespace,
          table: name,
          columns: columns,
          record: data,
          commit_timestamp: commit_timestamp
        }

        updated_state = %State{
          state
          | transaction: {lsn, %{txn | changes: [new_record | changes]}}
        }

        {:noreply, updated_state}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(
        {:message,
         %Messages.Update{
           relation_id: relation_id,
           old_tuple_data: old_tuple_data,
           tuple_data: tuple_data
         }},
        %State{
          relations: relations,
          transaction: {lsn, %{commit_timestamp: commit_timestamp, changes: changes} = txn}
        } = state
      )
      when is_map(relations) do
    IO.inspect("ReplicationPublisher handle_cast Messages.Update")

    case Map.fetch(relations, relation_id) do
      {:ok, %{columns: columns, namespace: namespace, name: name}} when is_list(columns) ->
        old_data = data_tuple_to_map(columns, old_tuple_data)
        data = data_tuple_to_map(columns, tuple_data)

        updated_record = %Changes.UpdatedRecord{
          type: "UPDATE",
          schema: namespace,
          table: name,
          columns: columns,
          old_record: old_data,
          record: data,
          commit_timestamp: commit_timestamp
        }

        updated_state = %State{
          state
          | transaction: {lsn, %{txn | changes: [updated_record | changes]}}
        }

        {:noreply, updated_state}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(
        {:message,
         %Messages.Delete{
           relation_id: relation_id,
           old_tuple_data: old_tuple_data,
           changed_key_tuple_data: changed_key_tuple_data
         }},
        %State{
          relations: relations,
          transaction: {lsn, %{commit_timestamp: commit_timestamp, changes: changes} = txn}
        } = state
      )
      when is_map(relations) do
    IO.inspect("ReplicationPublisher handle_cast Messages.Delete")

    case Map.fetch(relations, relation_id) do
      {:ok, %{columns: columns, namespace: namespace, name: name}} when is_list(columns) ->
        data = data_tuple_to_map(columns, old_tuple_data || changed_key_tuple_data)

        deleted_record = %Changes.DeletedRecord{
          type: "DELETE",
          schema: namespace,
          table: name,
          columns: columns,
          old_record: data,
          commit_timestamp: commit_timestamp
        }

        updated_state = %State{
          state
          | transaction: {lsn, %{txn | changes: [deleted_record | changes]}}
        }

        {:noreply, updated_state}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(
        {:message, %Messages.Truncate{truncated_relations: truncated_relations}},
        %State{
          relations: relations,
          transaction: {lsn, %{commit_timestamp: commit_timestamp, changes: changes} = txn}
        } = state
      )
      when is_list(truncated_relations) and is_list(changes) and is_map(relations) do
    IO.inspect("ReplicationPublisher handle_cast Messages.Truncate")

    new_changes =
      Enum.reduce(truncated_relations, changes, fn truncated_relation, acc ->
        case Map.fetch(relations, truncated_relation) do
          {:ok, %{namespace: namespace, name: name}} ->
            [
              %Changes.TruncatedRelation{
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

  @impl true
  def handle_cast({:message, _message}, state) do
    IO.inspect("ReplicationPublisher handle_cast All Others")
    :noop

    {:noreply, state}
  end

  defp data_tuple_to_map(columns, tuple_data) when is_list(columns) and is_tuple(tuple_data) do
    columns
    |> Enum.with_index()
    |> Enum.reduce_while(%{}, fn {column_map, index}, acc ->
      case column_map do
        %Messages.Relation.Column{name: column_name, type: column_type}
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
end
