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
      def events(txn, table, type), do: Event.events(txn, table, type, unquote(app_name))
      def events(txn, table), do: Event.events(txn, table, unquote(app_name))

      defmacro on_event(table, do_block) do
        quote do
          def process(txn) do
            case events(txn, unquote(table)) do
              events when is_list(events) and events != [] ->
                Logger.info("on_event fired")
                unquote(do_block).(events)

              _ ->
                Logger.info("on_event fired but no events!")
                {:error, :no_events}
            end
          end
        end
      end

      # TODO: Dry these up
      defmacro on_insert(table, do_block) do
        quote do
          def process_insert(txn) do
            Logger.info("process_insert called")

            case events(txn, unquote(table), :insert) do
              events when is_list(events) and events != [] ->
                Logger.info("on_insert fired")
                unquote(do_block).(events)

              _ ->
                {:error, :no_events}
            end
          end
        end
      end

      defmacro on_update(table, do_block) do
        quote do
          def process_update(txn) do
            Logger.info("process_update called")

            case events(txn, unquote(table), :update) do
              events when is_list(events) and events != [] ->
                Logger.info("on_update fired")
                unquote(do_block).(events)

              _ ->
                Logger.info("on_update fired but no events!")
                {:error, :no_events}
            end
          end
        end
      end

      defmacro on_delete(table, do_block) do
        quote do
          def process_delete(txn) do
            Logger.info("process_delete called")

            case events(txn, unquote(table), :delete) do
              events when is_list(events) and events != [] ->
                Logger.info("on_delete fired")
                unquote(do_block).(events)

              _ ->
                Logger.info("on_delete fired but no events!")
                {:error, :no_events}
            end
          end
        end
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
  def events(txn, table, type, app_name) do
    txn
    |> filter_changes(table, type, app_name)
    |> Enum.map(&cast(&1))
  end

  def events(txn, table, app_name) do
    txn
    |> filter_changes(table, app_name)
    |> Enum.map(&cast(&1))
  end
end
