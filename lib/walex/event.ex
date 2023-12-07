defmodule WalEx.Event do
  require Logger
  import WalEx.TransactionFilter

  alias WalEx.Changes
  alias WalEx.Event

  defstruct(
    table: nil,
    type: nil,
    new_record: nil,
    old_record: nil,
    changes: nil,
    commit_timestamp: nil
  )

  @doc """
  Macros for processing events
  """
  defmacro __using__(opts) do
    app_name = Keyword.get(opts, :name)

    quote do
      def events(txn, table, type, unwatched_changes) do
        Event.events(unquote(app_name), txn, table, type, unwatched_changes)
      end

      def events(txn, table, unwatched_changes) do
        Event.events(unquote(app_name), txn, table, unwatched_changes)
      end

      defmacro on_event(table, unwatched_changes \\ [], do_block) do
        quote do
          def process_all(txn) do
            case events(txn, unquote(table), unquote(unwatched_changes)) do
              events when is_list(events) and events != [] ->
                unquote(do_block).(events)

                {:ok, events}

              _ ->
                {:error, :no_events}
            end
          end
        end
      end

      defp process_event(type, table, unwatched_changes, do_block) do
        quote do
          def unquote(:"process_#{type}")(txn) do
            case events(txn, unquote(table), unquote(type), unquote(unwatched_changes)) do
              events when is_list(events) and events != [] ->
                unquote(do_block).(events)

              _ ->
                {:error, :no_events}
            end
          end
        end
      end

      defmacro on_insert(table, unwatched_changes \\ [], do_block) do
        process_event(:insert, table, unwatched_changes, do_block)
      end

      defmacro on_update(table, unwatched_changes \\ [], do_block) do
        process_event(:update, table, unwatched_changes, do_block)
      end

      defmacro on_delete(table, unwatched_changes \\ [], do_block) do
        process_event(:delete, table, unwatched_changes, do_block)
      end
    end
  end

  def cast(%Changes.NewRecord{
        table: table,
        type: "INSERT",
        record: record,
        commit_timestamp: commit_timestamp
      }) do
    %Event{
      table: String.to_atom(table),
      type: :insert,
      new_record: record,
      old_record: nil,
      changes: nil,
      commit_timestamp: commit_timestamp
    }
  end

  def cast(%Changes.UpdatedRecord{
        table: table,
        type: "UPDATE",
        record: record,
        old_record: old_record,
        commit_timestamp: commit_timestamp
      }) do
    %Event{
      table: String.to_atom(table),
      type: :update,
      new_record: record,
      old_record: old_record,
      changes: changes(old_record, record),
      commit_timestamp: commit_timestamp
    }
  end

  def cast(%Changes.DeletedRecord{
        table: table,
        type: "DELETE",
        old_record: old_record,
        commit_timestamp: commit_timestamp
      }) do
    %Event{
      table: String.to_atom(table),
      type: :delete,
      new_record: nil,
      old_record: old_record,
      changes: nil,
      commit_timestamp: commit_timestamp
    }
  end

  def cast(_event), do: nil

  @doc """
  Filter out events by table and type (optional) from transaction and cast to Event struct
  """
  def events(app_name, txn, table, type, unwatched_changes) do
    txn
    |> filter_changes(table, type, app_name)
    |> Enum.map(&cast(&1))
    |> filter_unwatched_changes(unwatched_changes)
  end

  def events(app_name, txn, table, unwatched_changes) do
    txn
    |> filter_changes(table, app_name)
    |> Enum.map(&cast(&1))
    |> filter_unwatched_changes(unwatched_changes)
  end
end
