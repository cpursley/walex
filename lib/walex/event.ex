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
      def events(txn, table, type, filters) do
        Event.filter_and_cast(unquote(app_name), txn, table, type, filters)
      end

      defmacro on_event(table, filters \\ %{}, do_block) do
        quote do
          def process_all(txn) do
            case events(txn, unquote(table), unquote(nil), unquote(filters)) do
              events when is_list(events) and events != [] ->
                unquote(do_block).(events)

                {:ok, events}

              _ ->
                {:error, :no_events}
            end
          end
        end
      end

      defp process_event(table, type, filters, do_block) do
        quote do
          def unquote(:"process_#{type}")(txn) do
            case events(txn, unquote(table), unquote(type), unquote(filters)) do
              events when is_list(events) and events != [] ->
                unquote(do_block).(events)

              _ ->
                {:error, :no_events}
            end
          end
        end
      end

      defmacro on_insert(table, filters \\ %{}, do_block) do
        process_event(table, :insert, filters, do_block)
      end

      defmacro on_update(table, filters \\ %{}, do_block) do
        process_event(table, :update, filters, do_block)
      end

      defmacro on_delete(table, filters \\ %{}, do_block) do
        process_event(table, :delete, filters, do_block)
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
  def filter_and_cast(app_name, txn, table, type, %{
        unwatched_records: unwatched_records,
        unwatched_fields: unwatched_fields
      }) do
    txn
    |> filter_changes(table, type, app_name)
    |> Enum.map(&cast(&1))
    |> filter_unwatched_records(unwatched_records)
    |> filter_unwatched_fields(unwatched_fields)
  end

  def filter_and_cast(app_name, txn, table, type, %{unwatched_records: unwatched_records}) do
    txn
    |> filter_changes(table, type, app_name)
    |> Enum.map(&cast(&1))
    |> filter_unwatched_records(unwatched_records)
  end

  def filter_and_cast(app_name, txn, table, type, %{unwatched_fields: unwatched_fields}) do
    txn
    |> filter_changes(table, type, app_name)
    |> Enum.map(&cast(&1))
    |> filter_unwatched_fields(unwatched_fields)
  end

  def filter_and_cast(app_name, txn, table, type, _filters) do
    txn
    |> filter_changes(table, type, app_name)
    |> Enum.map(&cast(&1))
  end
end
