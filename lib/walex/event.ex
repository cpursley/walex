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
  Macros for processing event
  """
  defmacro __using__(opts) do
    app_name = Keyword.get(opts, :name)

    quote do
      def event(table, txn), do: Event.event(table, txn, unquote(app_name))
      def events(table, txn), do: Event.events(table, txn, unquote(app_name))

      defmacro on_event(table, do_block) do
        quote do
          def process(txn) do
            case event(unquote(table), txn) do
              event = {:ok, %WalEx.Event{}} ->
                Logger.info("on_event fired")
                unquote(do_block).(event)

              no_event ->
                no_event
            end
          end
        end
      end

      # TODO: Dry these up
      defmacro on_insert(table, do_block) do
        quote do
          def process_insert(txn) do
            case event(unquote(table), txn) do
              filtered_event = {:ok, %WalEx.Event{type: :insert}} ->
                Logger.info("on_insert fired")
                unquote(do_block).(filtered_event)

              no_event ->
                no_event
            end
          end
        end
      end

      defmacro on_update(table, do_block) do
        quote do
          def process_update(txn) do
            case event(unquote(table), txn) do
              filtered_event = {:ok, %WalEx.Event{type: :update}} ->
                Logger.info("on_update fired")
                unquote(do_block).(filtered_event)

              no_event ->
                no_event
            end
          end
        end
      end

      defmacro on_delete(table, do_block) do
        quote do
          def process_delete(txn) do
            case event(unquote(table), txn) do
              filtered_event = {:ok, %WalEx.Event{type: :delete}} ->
                Logger.info("on_delete fired")
                unquote(do_block).(filtered_event)

              no_event ->
                no_event
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
  When single event per table is expected
  """
  def event(table, txn, app_name) do
    with true <- has_tables?(table, txn, app_name),
         [table] <- table(table, txn),
         casted_event <- cast(table),
         true <- Map.has_key?(casted_event, :__struct__) do
      {:ok, casted_event}
    else
      {:error, error} ->
        {:error, error}

      _ ->
        {:error, :no_event}
    end
  end

  @doc """
  When multiple events per table is expected (transaction)
  """
  def events(table, txn, app_name) do
    with true <- has_tables?(table, txn, app_name),
         tables <- table(table, txn),
         casted_events <- Enum.map(tables, &cast(&1)) do
      {:ok, casted_events}
    else
      {:error, error} ->
        {:error, error}

      _ ->
        {:error, :no_events}
    end
  end
end
