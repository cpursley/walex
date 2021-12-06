# This file steals liberally from https://github.com/supabase/realtime,
# which in turn draws on https://github.com/cainophile/cainophile

defmodule WalEx.TransactionFilter do
  alias WalEx.Adapters.Changes.Transaction

  defmodule(Filter, do: defstruct([:schema, :table, :condition]))

  require Logger

  @doc """
  Predicate to check if the filter matches the transaction.

  ## Examples

      iex> txn = %Transaction{changes: [
      ...>   %WalEx.Adapters.Changes.NewRecord{
      ...>     columns: [
      ...>       %WalEx.Adapters.Postgres.Decoder.Messages.Relation.Column{flags: [:key], name: "id", type: "int8", type_modifier: 4294967295},
      ...>       %WalEx.Adapters.Postgres.Decoder.Messages.Relation.Column{flags: [], name: "details", type: "text", type_modifier: 4294967295},
      ...>       %WalEx.Adapters.Postgres.Decoder.Messages.Relation.Column{flags: [], name: "user_id", type: "int8", type_modifier: 4294967295}
      ...>     ],
      ...>     commit_timestamp: nil,
      ...>     record: %{"details" => "The SCSI system is down, program the haptic microchip so we can back up the SAS circuit!", "id" => "14", "user_id" => "1"},
      ...>     schema: "public",
      ...>     table: "todos",
      ...>     type: "INSERT"
      ...>   }
      ...> ]}
      iex> matches?(%{event: "*", relation: "*"}, txn)
      true
      iex> matches?(%{event: "INSERT", relation: "*"}, txn)
      true
      iex> matches?(%{event: "UPDATE", relation: "*"}, txn)
      false
      iex> matches?(%{event: "INSERT", relation: "public"}, txn)
      true
      iex> matches?(%{event: "INSERT", relation: "myschema"}, txn)
      false
      iex> matches?(%{event: "INSERT", relation: "public:todos"}, txn)
      true
      iex> matches?(%{event: "INSERT", relation: "myschema:users"}, txn)
      false

  """
  def matches?(%{event: event, relation: relation}, %Transaction{changes: changes}) do
    case parse_relation_filter(relation) do
      {:ok, filter} ->
        Enum.any?(changes, fn change -> change_matches(event, filter, change) end)

      {:error, msg} ->
        Logger.warn("Could not parse relation filter: #{inspect(msg)}")
        false
    end
  end

  # malformed filter or txn. Should not match.
  def matches?(_filter, _txn), do: false

  defp change_matches(event, _filter, %{type: type}) when event != type and event != "*" do
    false
  end

  defp change_matches(_event, filter, change) do
    name_matches(filter.schema, change.schema) and name_matches(filter.table, change.table)
  end

  @doc """
  Parse a string representing a relation filter to a `Filter` struct.

  ## Examples

      iex> parse_relation_filter("public:users")
      {:ok, %Filter{schema: "public", table: "users", condition: nil}}

      iex> parse_relation_filter("public")
      {:ok, %Filter{schema: "public", table: nil, condition: nil}}


      iex> parse_relation_filter("")
      {:ok, %Filter{schema: nil, table: nil, condition: nil}}

      iex> parse_relation_filter("public:users:bad")
      {:error, "malformed relation filter"}

  """
  def parse_relation_filter(relation) do
    # We do a very loose validation here.
    # When the relation filter format is well defined we can do
    # proper parsing and validation.
    case String.split(relation, ":") do
      [""] -> {:ok, %Filter{schema: nil, table: nil, condition: nil}}
      ["*"] -> {:ok, %Filter{schema: nil, table: nil, condition: nil}}
      [schema] -> {:ok, %Filter{schema: schema, table: nil, condition: nil}}
      [schema, table] -> {:ok, %Filter{schema: schema, table: table, condition: nil}}
      _ -> {:error, "malformed relation filter"}
    end
  end

  defp name_matches(nil, _change_name), do: true

  defp name_matches(filter_name, change_name) do
    filter_name == change_name
  end

  def insert_event?(relation, txn), do: relation("INSERT", relation, txn)
  def update_event?(relation, txn), do: relation("UPDATE", relation, txn)
  def delete_event?(relation, txn), do: relation("DELETE", relation, txn)

  defp relation(event, relation, txn) do
    if String.contains?(relation, ":") do
      matches?(%{event: event, relation: relation}, txn)
    else
      matches?(%{event: event, relation: "public:" <> relation}, txn)
    end
  end

  def table(table_name, %Transaction{changes: changes}) do
    Enum.filter(changes, fn change -> has_table?(change, table_name) end)
  end

  def table(_table, _txn), do: false

  def has_table?(change, table_name), do: String.to_atom(change.table) == table_name

  def has_tables?(tables, %Transaction{changes: _changes} = txn) when is_list(tables) do
    tables
    |> Enum.map(fn table -> has_tables?(table, txn) end)
    |> Enum.all?()
  end

  def has_tables?(table_name, %Transaction{changes: changes}) when is_atom(table_name) do
    Enum.any?(changes, fn change ->
      has_table?(change, table_name) && subscribes?(change)
    end)
  end

  def has_tables?(table_name, txn) when is_binary(table_name) do
    has_tables?(String.to_atom(table_name), txn)
  end

  def has_tables?(_tables, _txn), do: false

  defp subscribes?(change) do
    case Application.get_env(:walex, :subscriptions) do
      nil ->
        true

      subscriptions ->
        String.to_atom(change.table) in subscriptions
    end
  end

  def changes(old_record, record) do
    case MapDiff.diff(old_record, record) do
      %{value: changes} ->
        filter_changes(changes)

      _ ->
        %{}
    end
  end

  defp filter_changes(changes) do
    changes
    |> Enum.filter(fn {_key, change} -> change.changed in [:primitive_change, :map_change] end)
    |> Enum.into(%{})
  end
end
