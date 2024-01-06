defmodule WalEx.Event do
  @moduledoc """
  Event DSL and casting
  """

  @derive Jason.Encoder
  defstruct([:name, :type, :source, :new_record, :old_record, :changes, :timestamp])

  @type t :: %WalEx.Event{
          name: atom(),
          type: :insert | :update | :delete,
          source: WalEx.Event.Source.t(),
          new_record: map() | nil,
          old_record: map() | nil,
          changes: map() | nil,
          timestamp: DateTime.t()
        }

  require Logger
  import WalEx.TransactionFilter

  alias WalEx.{Changes, Event, Helpers}

  @doc """
  Macros for processing events
  """
  defmacro __using__(opts) do
    app_name = Keyword.get(opts, :name)

    quote do
      import WalEx.Event.Dsl

      def filter_events(txn) do
        Event.filter_and_cast(unquote(app_name), txn)
      end

      def filter_events(txn, name, type, filters) do
        Event.filter_and_cast(unquote(app_name), txn, name, type, filters)
      end
    end
  end

  def cast(
        %Changes.NewRecord{
          type: "INSERT",
          schema: schema,
          table: table,
          columns: columns,
          record: record,
          commit_timestamp: timestamp
        },
        app_name
      ) do
    %Event{
      name: String.to_atom(table),
      type: :insert,
      source: cast_source(app_name, schema, table, columns),
      new_record: record,
      timestamp: timestamp
    }
  end

  def cast(
        %Changes.UpdatedRecord{
          type: "UPDATE",
          schema: schema,
          table: table,
          columns: columns,
          record: record,
          old_record: old_record,
          commit_timestamp: timestamp
        },
        app_name
      ) do
    %Event{
      name: String.to_atom(table),
      type: :update,
      source: cast_source(app_name, schema, table, columns),
      new_record: record,
      changes: map_changes(old_record, record),
      timestamp: timestamp
    }
  end

  def cast(
        %Changes.DeletedRecord{
          type: "DELETE",
          schema: schema,
          table: table,
          columns: columns,
          old_record: old_record,
          commit_timestamp: timestamp
        },
        app_name
      ) do
    %Event{
      name: String.to_atom(table),
      type: :delete,
      source: cast_source(app_name, schema, table, columns),
      old_record: old_record,
      timestamp: timestamp
    }
  end

  def cast(_event, _event_name), do: nil

  defp cast_source(app_name, schema, table, columns) do
    %WalEx.Event.Source{
      name: Helpers.get_source_name(),
      version: Helpers.get_source_version(),
      db: Helpers.get_database(app_name),
      schema: schema,
      table: table,
      columns: map_columns(columns)
    }
  end

  def cast_events(changes, app_name) do
    changes
    |> Enum.map(&cast(&1, app_name))
  end

  @doc """
  Filter out events by table and type (optional) from transaction and cast to Event struct
  """
  def filter_and_cast(app_name, txn) do
    txn
    |> filter_subscribed(app_name)
    |> cast_events(app_name)
  end

  # TODO: change order of filter (to before cast!)
  def filter_and_cast(app_name, txn, table, type, %{
        unwatched_records: unwatched_records,
        unwatched_fields: unwatched_fields
      }) do
    txn
    |> filter_changes(table, type, app_name)
    |> cast_events(app_name)
    |> filter_unwatched_records(unwatched_records)
    |> filter_unwatched_fields(unwatched_fields)
  end

  def filter_and_cast(app_name, txn, table, type, %{unwatched_records: unwatched_records}) do
    txn
    |> filter_changes(table, type, app_name)
    |> cast_events(app_name)
    |> filter_unwatched_records(unwatched_records)
  end

  def filter_and_cast(app_name, txn, table, type, %{unwatched_fields: unwatched_fields}) do
    txn
    |> filter_changes(table, type, app_name)
    |> cast_events(app_name)
    |> filter_unwatched_fields(unwatched_fields)
  end

  def filter_and_cast(app_name, txn, table, type, _filters) do
    txn
    |> filter_changes(table, type, app_name)
    |> cast_events(app_name)
  end
end
