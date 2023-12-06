# This file steals liberally from https://github.com/supabase/realtime,
# which in turn draws on https://github.com/cainophile/cainophile

defmodule WalEx.TransactionFilter do
  alias WalEx.Changes.{
    DeletedRecord,
    NewRecord,
    UpdatedRecord,
    Transaction
  }

  require Logger

  defmodule(Filter, do: defstruct([:schema, :table, :condition]))

  @doc """
  Predicate to check if the filter matches the transaction.

  ## Examples

      iex> txn = %Transaction{changes: [
      ...>   %WalEx.Changes.NewRecord{
      ...>     columns: [
      ...>       %WalEx.Postgres.Decoder.Messages.Relation.Column{flags: [:key], name: "id", type: "int8", type_modifier: 4294967295},
      ...>       %WalEx.Postgres.Decoder.Messages.Relation.Column{flags: [], name: "details", type: "text", type_modifier: 4294967295},
      ...>       %WalEx.Postgres.Decoder.Messages.Relation.Column{flags: [], name: "user_id", type: "int8", type_modifier: 4294967295}
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

      {:error, _msg} ->
        false
    end
  end

  # malformed filter or txn. Should not match.
  def matches?(_filter, _txn), do: false

  defp change_matches(event, _filter, %{type: type}) when event != type and event != "*" do
    false
  end

  defp change_matches(_event, filter, change) do
    name_matches?(filter.schema, change.schema) and name_matches?(filter.table, change.table)
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

  defp name_matches?(nil, _change_name), do: true
  defp name_matches?(filter_name, change_name), do: filter_name == change_name

  def insert_event?(relation, txn), do: relation("INSERT", relation, txn)
  def update_event?(relation, txn), do: relation("UPDATE", relation, txn)
  def delete_event?(relation, txn), do: relation("DELETE", relation, txn)

  defp relation(event, relation, txn) when is_atom(relation) do
    matches?(%{event: event, relation: "public:" <> to_string(relation)}, txn)
  end

  defp relation(event, relation, txn) when is_binary(relation) do
    if String.contains?(relation, ":") do
      matches?(%{event: event, relation: relation}, txn)
    else
      matches?(%{event: event, relation: "public:" <> relation}, txn)
    end
  end

  @doc """
  Returns a list of changes for the given table name and type (optional)
  """
  def filter_changes(%Transaction{changes: changes}, table, type, app_name) do
    changes
    |> subscribes_and_has_table(table, app_name)
    |> Enum.filter(&is_type?(&1, type))
  end

  def filter_changes(%Transaction{changes: changes}, table, app_name) do
    subscribes_and_has_table(changes, table, app_name)
  end

  defp subscribes_and_has_table(changes, table, app_name) do
    Enum.filter(changes, &subscribes_to_table?(&1, table, app_name))
  end

  def subscribes_to_table?(change, table, app_name) do
    has_table?(change, table) && subscribes?(change, app_name)
  end

  def subscribes?(%{table: table}, app_name) do
    subscriptions =
      app_name
      |> WalEx.Configs.get_configs([:subscriptions])
      |> Keyword.get(:subscriptions)

    String.to_atom(table) in subscriptions
  end

  def has_table?(%{table: table}, table_name) when is_atom(table), do: table == table_name

  def has_table?(%{table: table}, table_name) when is_binary(table),
    do: String.to_atom(table) == table_name

  def has_table?(_txn, _table_name), do: false

  def is_type?(%NewRecord{type: "INSERT"}, :insert), do: true
  def is_type?(%UpdatedRecord{type: "UPDATE"}, :update), do: true
  def is_type?(%DeletedRecord{type: "DELETE"}, :delete), do: true
  def is_type?(_txn, _type), do: false

  def changes(old_record, new_record) do
    case MapDiff.diff(old_record, new_record) do
      %{value: changes} ->
        filter_diffs(changes)

      _ ->
        %{}
    end
  end

  defp filter_diffs(changes) do
    changes
    |> Enum.filter(fn {_key, change} ->
      if is_map(change) && Map.has_key?(change, :changed) do
        change.changed in [:primitive_change, :map_change]
      end
    end)
    |> Enum.into(%{})
  end
end
