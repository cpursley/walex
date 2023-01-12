defmodule WalEx.Event do
  defstruct(
    table: nil,
    type: nil,
    new_record: nil,
    old_record: nil,
    changes: nil,
    commit_timestamp: nil
  )

  import WalEx.TransactionFilter

  alias WalEx.Event
  alias WalEx.Changes

  @doc """
  Behaviour for processing event
  """
  @callback process(payload :: %Changes.Transaction{}) :: :ok | {:error, any()}

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
  def event(table_name, txn) do
    with true <- has_tables?(table_name, txn),
         [table] <- table(table_name, txn),
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
  def events(table_name, txn) do
    with true <- has_tables?(table_name, txn),
         tables <- table(table_name, txn),
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
