defmodule WalEx.Event.Dsl do
  defmacro process_events_async(events, functions) do
    [module | _] = __CALLER__.context_modules

    quote do
      Enum.each(unquote(events), fn event ->
        unquote(functions)
        |> Enum.each(fn function ->
          task_fn =
            case function do
              # If function is a tuple, treat it as {Module, function}
              {mod, func} when is_atom(mod) and is_atom(func) ->
                fn -> apply(mod, func, [event]) end

              # If function is an atom, treat it as a local function in the current module
              # maybe don't allow atoms
              func when is_atom(func) ->
                fn -> apply(unquote(module), func, [event]) end

              _ ->
                raise ArgumentError, "Invalid function: #{inspect(function)}"
            end

          Task.start(task_fn)
        end)
      end)
    end
  end

  defmacro on_event(:all, do_block) do
    quote do
      def process_all(txn) do
        case filter_events(txn) do
          filtered_events when is_list(filtered_events) and filtered_events != [] ->
            unquote(do_block).(filtered_events)

          _ ->
            {:error, :no_events}
        end
      end
    end
  end

  defmacro on_event(name, filters \\ %{}, functions \\ [], do_block) do
    quote do
      def process_all(txn) do
        case filter_events(txn, unquote(name), unquote(nil), unquote(filters)) do
          filtered_events when is_list(filtered_events) and filtered_events != [] ->
            process_events_async(filtered_events, unquote(functions))
            unquote(do_block).(filtered_events)

          _ ->
            {:error, :no_events}
        end
      end
    end
  end

  defp process_event(name, type, filters, functions, do_block) do
    quote do
      def unquote(:"process_#{type}")(txn) do
        case filter_events(txn, unquote(name), unquote(type), unquote(filters)) do
          filtered_events when is_list(filtered_events) and filtered_events != [] ->
            process_events_async(filtered_events, unquote(functions))
            unquote(do_block).(filtered_events)

          _ ->
            {:error, :no_events}
        end
      end
    end
  end

  defmacro on_insert(name, filters \\ %{}, functions \\ [], do_block) do
    process_event(name, :insert, filters, functions, do_block)
  end

  defmacro on_update(name, filters \\ %{}, functions \\ [], do_block) do
    process_event(name, :update, filters, functions, do_block)
  end

  defmacro on_delete(name, filters \\ %{}, functions \\ [], do_block) do
    process_event(name, :delete, filters, functions, do_block)
  end
end
