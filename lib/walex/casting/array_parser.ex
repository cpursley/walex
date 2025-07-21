defmodule WalEx.Casting.ArrayParser do
  @moduledoc """
  Parser for PostgreSQL array literals

  Implementation inspired by Supabase Realtime and Sequin
  """

  @doc """
  Parses a PostgreSQL array literal string into an Elixir list.

  Returns all elements as strings - the caller is responsible for any
  type conversion. NULL values are returned as `nil`.

  ## Parameters
    - `array_string` - PostgreSQL array literal (e.g., `"{1,2,3}"`)

  ## Returns
    - `{:ok, list}` - Successfully parsed array as nested list
    - `{:error, reason}` - Parsing failed with reason

  ## Examples

      # Simple arrays
      iex> WalEx.ArrayParser.parse("{1,2,3}")
      {:ok, ["1", "2", "3"]}
      
      # Empty arrays
      iex> WalEx.ArrayParser.parse("{}")
      {:ok, []}
      
      # Arrays with quoted strings
      iex> WalEx.ArrayParser.parse("{\"hello, world\",\"foo\"}")
      {:ok, ["hello, world", "foo"]}
      
      # Nested arrays
      iex> WalEx.ArrayParser.parse("{{1,2},{3,4}}")
      {:ok, [["1", "2"], ["3", "4"]]}

      # NULL values
      iex> WalEx.ArrayParser.parse("{1,NULL,3}")
      {:ok, ["1", nil, "3"]}
  """
  def parse(array_string) when is_binary(array_string) do
    case array_string do
      "{}" -> {:ok, []}
      <<"{", rest::binary>> -> parse_array_contents(rest, [], "")
      _ -> {:error, "Invalid array format - must start with {"}
    end
  end

  # Main parsing loop - handles end of input
  defp parse_array_contents(<<>>, _acc, _current) do
    {:error, "Unexpected end of array - missing closing }"}
  end

  # Handle closing brace - empty current element
  defp parse_array_contents(<<"}", _rest::binary>>, acc, "") do
    {:ok, Enum.reverse(acc)}
  end

  defp parse_array_contents(<<"}", _rest::binary>>, acc, current) do
    {:ok, Enum.reverse([current | acc])}
  end

  # Handle NULL values - must be followed by comma or closing brace
  defp parse_array_contents(<<"NULL", rest::binary>>, acc, "") do
    case rest do
      <<",", rest::binary>> -> parse_array_contents(rest, [nil | acc], "")
      <<"}", _::binary>> -> parse_array_contents(rest, [nil | acc], "")
      _ -> {:error, "Invalid character after NULL"}
    end
  end

  # Handle nested arrays - track depth and recursively parse
  defp parse_array_contents(<<"{", rest::binary>>, acc, "") do
    case parse_nested_array(rest, 1, "{") do
      {:ok, nested_content, remaining} ->
        case parse(nested_content) do
          {:ok, nested_array} ->
            case remaining do
              <<",", rest::binary>> -> parse_array_contents(rest, [nested_array | acc], "")
              <<"}", _::binary>> -> parse_array_contents(remaining, [nested_array | acc], "")
              <<>> -> {:error, "Unexpected end of array - missing closing }"}
              _ -> {:error, "Invalid character after nested array"}
            end

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  # Handle quoted strings - delegate to specialized parser
  defp parse_array_contents(<<"\"", rest::binary>>, acc, "") do
    parse_quoted_string(rest, acc, "")
  end

  # Handle comma separator - empty current means consecutive commas
  defp parse_array_contents(<<",", rest::binary>>, acc, "") do
    parse_array_contents(rest, acc, "")
  end

  defp parse_array_contents(<<",", rest::binary>>, acc, current) do
    parse_array_contents(rest, [current | acc], "")
  end

  # Handle regular characters - accumulate into current element
  defp parse_array_contents(<<char, rest::binary>>, acc, current) do
    parse_array_contents(rest, acc, current <> <<char>>)
  end

  # Parse quoted string - handle unterminated string error
  defp parse_quoted_string(<<>>, _acc, _buffer) do
    {:error, "Unexpected end of array - unterminated quoted string"}
  end

  # Handle escape sequences within quoted strings
  defp parse_quoted_string(<<"\\", escaped, rest::binary>>, acc, buffer) do
    case escaped do
      ?\\ -> parse_quoted_string(rest, acc, buffer <> "\\")
      ?\" -> parse_quoted_string(rest, acc, buffer <> "\"")
      _ -> parse_quoted_string(rest, acc, buffer <> "\\" <> <<escaped>>)
    end
  end

  # End of quoted string - must be followed by comma or closing brace
  defp parse_quoted_string(<<"\"", rest::binary>>, acc, buffer) do
    case rest do
      <<",", rest::binary>> -> parse_array_contents(rest, [buffer | acc], "")
      <<"}", _::binary>> -> parse_array_contents(rest, [buffer | acc], "")
      _ -> {:error, "Invalid character after quoted string"}
    end
  end

  defp parse_quoted_string(<<char, rest::binary>>, acc, buffer) do
    parse_quoted_string(rest, acc, buffer <> <<char>>)
  end

  # Parse nested array - track brace depth to find matching closing brace
  defp parse_nested_array(<<>>, _depth, _buffer) do
    {:error, "Unexpected end of array - unclosed nested array"}
  end

  # Increment depth when encountering opening brace
  defp parse_nested_array(<<"{", rest::binary>>, depth, buffer) do
    parse_nested_array(rest, depth + 1, buffer <> "{")
  end

  # Decrement depth when encountering closing brace (not the final one)
  defp parse_nested_array(<<"}", rest::binary>>, depth, buffer) when depth > 1 do
    parse_nested_array(rest, depth - 1, buffer <> "}")
  end

  # Found matching closing brace - return nested array content
  defp parse_nested_array(<<"}", rest::binary>>, 1, buffer) do
    {:ok, buffer <> "}", rest}
  end

  # Regular character in nested array - just accumulate
  defp parse_nested_array(<<char, rest::binary>>, depth, buffer) do
    parse_nested_array(rest, depth, buffer <> <<char>>)
  end
end
