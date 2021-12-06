defmodule WalEx.Event do
  defstruct(
    type: nil,
    record: nil,
    changes: nil,
    commit_timestamp: nil
  )

  import WalEx.TransactionFilter

  alias WalEx.Event

  def cast(%{
        type: "INSERT",
        record: record,
        commit_timestamp: commit_timestamp
      }) do
    %Event{
      type: :insert,
      record: record,
      changes: nil,
      commit_timestamp: commit_timestamp
    }
  end

  def cast(%{
        type: "UPDATE",
        record: record,
        old_record: old_record,
        commit_timestamp: commit_timestamp
      }) do
    %Event{
      type: :update,
      record: record,
      changes: changes(old_record, record),
      commit_timestamp: commit_timestamp
    }
  end

  def cast(%{
        type: "DELETE",
        record: nil,
        old_record: old_record,
        commit_timestamp: commit_timestamp
      }) do
    %Event{
      type: :delete,
      record: nil,
      changes: old_record,
      commit_timestamp: commit_timestamp
    }
  end

  def cast(_event), do: nil

  def event(table_name, txn) do
    with {:ok, [table]} <- events(table_name, txn),
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

  defp events(table_name, txn) do
    with true <- has_tables?(table_name, txn),
         tables <- table(table_name, txn) do
      {:ok, tables}
    else
      _ ->
        {:error, :no_events}
    end
  end
end
