defmodule WalEx.Replication.Publisher do
  @moduledoc """
  Publishes messages from Replication to Events & Destinations
  """
  use GenServer

  alias WalEx.{Changes, Config, Destinations, Types}
  alias WalEx.Decoder.Messages

  defmodule(State,
    do:
      defstruct(
        relations: %{},
        transaction: nil,
        types: %{}
      )
  )

  defstruct [:relations]

  def start_link(opts) do
    name =
      opts
      |> Keyword.get(:app_name)
      |> registry_name

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def process_message(message, app_name) do
    name = registry_name(app_name)

    GenServer.cast(name, %{message: message, app_name: app_name})
  end

  defp registry_name(app_name) do
    Config.Registry.set_name(:set_gen_server, __MODULE__, app_name)
  end

  @impl true
  def init(_opts) do
    Process.flag(:message_queue_data, :off_heap)

    {:ok, %State{}}
  end

  @impl true
  def handle_cast(
        %{message: %Messages.Begin{final_lsn: final_lsn, commit_timestamp: commit_timestamp}},
        state
      ) do
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
        %{message: %Messages.Commit{lsn: commit_lsn}, app_name: app_name},
        %State{transaction: {current_txn_lsn, txn}, relations: _relations} = state
      )
      when commit_lsn == current_txn_lsn do
    Destinations.process(txn, app_name)
    {:noreply, state}
  end

  @impl true
  def handle_cast(%{message: %Messages.Type{} = msg}, state) do
    updated_state = %{state | types: Map.put(state.types, msg.id, msg.name)}

    {:noreply, updated_state}
  end

  @impl true
  def handle_cast(%{message: %Messages.Relation{} = msg}, state) do
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
        %{message: %Messages.Insert{relation_id: relation_id, tuple_data: tuple_data}},
        state = %State{
          transaction: {lsn, %{commit_timestamp: commit_timestamp, changes: changes} = txn},
          relations: relations
        }
      )
      when is_map(relations) do
    case Map.fetch(relations, relation_id) do
      {:ok, %{columns: columns, namespace: namespace, name: name}} when is_list(columns) ->
        data = data_tuple_to_map(columns, tuple_data)

        new_record = %Changes.NewRecord{
          type: "INSERT",
          schema: namespace,
          table: name,
          columns: columns,
          record: data,
          commit_timestamp: commit_timestamp,
          lsn: lsn
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
        %{
          message: %Messages.Update{
            relation_id: relation_id,
            old_tuple_data: old_tuple_data,
            tuple_data: tuple_data
          }
        },
        state = %State{
          relations: relations,
          transaction: {lsn, %{commit_timestamp: commit_timestamp, changes: changes} = txn}
        }
      )
      when is_map(relations) do
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
          commit_timestamp: commit_timestamp,
          lsn: lsn
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
        %{
          message: %Messages.Delete{
            relation_id: relation_id,
            old_tuple_data: old_tuple_data,
            changed_key_tuple_data: changed_key_tuple_data
          }
        },
        state = %State{
          relations: relations,
          transaction: {lsn, %{commit_timestamp: commit_timestamp, changes: changes} = txn}
        }
      )
      when is_map(relations) do
    case Map.fetch(relations, relation_id) do
      {:ok, %{columns: columns, namespace: namespace, name: name}} when is_list(columns) ->
        data = data_tuple_to_map(columns, old_tuple_data || changed_key_tuple_data)

        deleted_record = %Changes.DeletedRecord{
          type: "DELETE",
          schema: namespace,
          table: name,
          columns: columns,
          old_record: data,
          commit_timestamp: commit_timestamp,
          lsn: lsn
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
        %{message: %Messages.Truncate{truncated_relations: truncated_relations}},
        state = %State{
          relations: relations,
          transaction: {lsn, %{commit_timestamp: commit_timestamp, changes: changes} = txn}
        }
      )
      when is_list(truncated_relations) and is_list(changes) and is_map(relations) do
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
  def handle_cast(%{message: _message}, state) do
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
          validate_tuple_and_handle_response(tuple_data, index, acc, column_name, column_type)

        _ ->
          {:cont, acc}
      end
    end)
    |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
  end

  defp data_tuple_to_map(_columns, _tuple_data), do: %{}

  defp validate_tuple_and_handle_response(tuple_data, index, acc, column_name, column_type) do
    case validate_tuple(tuple_data, index) do
      {:ok, record} ->
        {:cont, Map.put(acc, column_name, Types.cast_record(record, column_type))}

      :error ->
        {:halt, acc}
    end
  end

  defp validate_tuple(tuple_data, index) do
    {:ok, Kernel.elem(tuple_data, index)}
  rescue
    ArgumentError -> :error
  end
end
