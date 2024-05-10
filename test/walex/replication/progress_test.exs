defmodule WalEx.Replication.ProgressTest do
  use ExUnit.Case, async: false
  alias WalEx.Replication.Publisher
  alias WalEx.Replication.Progress
  alias WalEx.Config.Registry

  require Logger

  @app_name :walex_test

  setup_all do
    {:ok, pid} = start_supervised(Registry.child_spec(), restart: :temporary)
    %{registry_pid: pid}
  end

  describe "start" do
    test "start_link is required" do
      Process.flag(:trap_exit, true)

      pid =
        spawn_link(fn ->
          Progress.begin(@app_name, {0, 1})
        end)

      assert_receive {:EXIT, ^pid, {:noproc, _}}
    end
  end

  describe "usage" do
    setup do
      {:ok, pid} = start_supervised({Progress, app_name: @app_name}, restart: :temporary)
      %{progress_pid: pid}
    end

    test "begin/end cancel each other" do
      assert Progress.oldest_running_wal_end(@app_name) == nil

      Progress.begin(@app_name, {0, 1})
      Progress.done(@app_name, {0, 1})

      assert Progress.oldest_running_wal_end(@app_name) == nil

      :ok
    end

    test "oldest_running_wal_end" do
      Progress.begin(@app_name, {0, 2})
      Progress.begin(@app_name, {0, 3})
      Progress.done(@app_name, {0, 2})

      assert Progress.oldest_running_wal_end(@app_name) == 3

      Progress.begin(@app_name, {0, 4})
      Progress.done(@app_name, {0, 4})
      assert Progress.oldest_running_wal_end(@app_name) == 3

      Progress.done(@app_name, {0, 3})
      assert Progress.oldest_running_wal_end(@app_name) == nil

      :ok
    end

    test "oldest is is the smallest, doesn't care about insert order" do
      Progress.begin(@app_name, {0, 20})
      Progress.begin(@app_name, {0, 10})
      Progress.begin(@app_name, {0, 5})
      assert Progress.oldest_running_wal_end(@app_name) == 5
      Progress.done(@app_name, {0, 5})
      assert Progress.oldest_running_wal_end(@app_name) == 10
      Progress.done(@app_name, {0, 20})
      assert Progress.oldest_running_wal_end(@app_name) == 10
      Progress.done(@app_name, {0, 10})
      assert Progress.oldest_running_wal_end(@app_name) == nil

      :ok
    end

    test "publisher restart resets progress" do
      Progress.begin(@app_name, {0, 20})
      Progress.begin(@app_name, {0, 10})
      Progress.begin(@app_name, {0, 5})

      assert {:ok, _pid} = start_supervised({Publisher, app_name: @app_name}, restart: :temporary)
      assert Progress.oldest_running_wal_end(@app_name) == nil
    end
  end
end
