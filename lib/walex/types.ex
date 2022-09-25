defmodule WalEx.Types do
  def cast_record("t", "bool"), do: true
  def cast_record("f", "bool"), do: false

  def cast_record(record, <<"int", _::binary>>) when is_binary(record) do
    case Integer.parse(record) do
      {int, _} ->
        int

      :error ->
        record
    end
  end

  def cast_record(record, <<"float", _::binary>>) when is_binary(record) do
    case Float.parse(record) do
      {float, _} ->
        float

      :error ->
        record
    end
  end

  def cast_record(record, "numeric") when is_binary(record), do: Decimal.new(record)
  def cast_record(record, "decimal"), do: cast_record(record, "numeric")

  def cast_record(record, "timestamp") when is_binary(record) do
    with {:ok, %NaiveDateTime{} = naive_date_time} <- Timex.parse(record, "{RFC3339}"),
         %DateTime{} = date_time <- Timex.to_datetime(naive_date_time) do
      date_time
    else
      _ -> record
    end
  end

  def cast_record(record, "timestamptz") when is_binary(record) do
    case Timex.parse(record, "{RFC3339}") do
      {:ok, %DateTime{} = date_time} ->
        date_time

      _ ->
        record
    end
  end

  def cast_record(record, "jsonb") when is_binary(record) do
    case Jason.decode(record) do
      {:ok, json} ->
        json

      _ ->
        record
    end
  end

  # TODO: Add additional type castings and ability to load external types
  def cast_record(record, _column_type) do
    record
  end
end
