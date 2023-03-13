defmodule WalEx.RegistryTest do
  use ExUnit.Case, async: false

  alias WalEx.Registry, as: WalExRegistry

  describe "start_registry/0" do
    test "should start a process" do
      assert {:ok, pid} = WalExRegistry.start_registry()

      assert is_pid(pid)
    end
  end

  describe "set_name/3" do
    setup do
      assert {:ok, _pid} = WalExRegistry.start_registry()
      :ok
    end

    test "should set agent name" do
      assert {:via, Registry, {:walex_registry, {WalEx.RegistryTest, :app_name_test}}} ==
               WalExRegistry.set_name(:set_agent, __MODULE__, :app_name_test)
    end

    test "should set get server name" do
      assert {:via, Registry, {:walex_registry, {WalEx.RegistryTest, :app_name_test}}} ==
               WalExRegistry.set_name(:set_gen_server, __MODULE__, :app_name_test)
    end

    test "should set supervisor name" do
      assert {:via, WalEx.RegistryTest, :app_name_test} ==
               WalExRegistry.set_name(:set_supervisor, __MODULE__, :app_name_test)
    end
  end

  describe "get_state/3" do
    setup do
      assert {:ok, _pid} = WalExRegistry.start_registry()
      :ok
    end

    test "should set agent state" do
      name = WalExRegistry.set_name(:set_agent, __MODULE__, :app_name_test)

      configs = [
        my_atom: :test_config,
        my_number: 99,
        my_string: "test config",
        my_map: %{john: :doe},
        my_list: [1, 9, 9, 4]
      ]

      Agent.start_link(fn -> configs end, name: name)

      assert configs == WalExRegistry.get_state(:get_agent, __MODULE__, :app_name_test)
    end
  end
end
