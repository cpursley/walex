defmodule WalEx.Replication.Progress do
  use Agent

  alias WalEx.Config.Registry

  @default_value :gb_sets.empty()

  def start_link(opts) do
    app_name = Keyword.fetch!(opts, :app_name)
    name = Registry.set_name(:set_agent, __MODULE__, app_name)
    Agent.start_link(fn -> @default_value end, name: name)
  end

  def reset(app_name) do
    name = Registry.set_name(:set_agent, __MODULE__, app_name)
    Agent.update(name, fn _ -> @default_value end)
  end

  @spec oldest_running_wal_end(any()) :: integer() | nil
  def oldest_running_wal_end(app_name) do
    still_running = current_state(app_name)

    unless :gb_sets.is_empty(still_running) do
      :gb_sets.smallest(still_running)
    else
      nil
    end
  end

  def begin(app_name, {_, wal_end}) do
    name = Registry.set_name(:set_agent, __MODULE__, app_name)
    Agent.update(name, fn set -> :gb_sets.insert(wal_end, set) end)
  end

  def done(app_name, {_, wal_end}) do
    name = Registry.set_name(:set_agent, __MODULE__, app_name)
    Agent.update(name, fn set -> :gb_sets.del_element(wal_end, set) end)
  end

  defp current_state(app_name) do
    Registry.get_state(:get_agent, __MODULE__, app_name)
  end
end
