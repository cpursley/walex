defmodule WalEx.SupervisorTest do
  use ExUnit.Case, async: false

  alias WalEx.Supervisor, as: WalExSupervisor

  describe "start_link/2" do
    test "should start a process" do
      assert {:ok, pid} = WalExSupervisor.start_link(get_base_configs())

      assert is_pid(pid)
    end

    test "should raise if any required config is missing" do
      assert_raise RuntimeError,
                   "Following configs are missing: [:hostname, :username, :password, :port, :database, :subscriptions, :publication, :modules, :name]",
                   fn -> WalExSupervisor.start_link([]) end
    end

    test "should start multiple supervision trees" do
      configs_1 = get_base_configs()
      configs_2 = Keyword.put(configs_1, :name, :other_name)
      configs_3 = Keyword.put(configs_1, :name, :another_name)

      assert {:ok, pid_1} = WalExSupervisor.start_link(configs_1)
      assert {:ok, pid_2} = WalExSupervisor.start_link(configs_2)
      assert {:ok, pid_3} = WalExSupervisor.start_link(configs_3)

      assert is_pid(pid_1)
      assert is_pid(pid_2)
      assert is_pid(pid_3)
    end

    test "should start WalEx.Registry" do
      assert {:ok, _pid} = WalExSupervisor.start_link(get_base_configs())

      pid = Process.whereis(:walex_registry)
      assert is_pid(pid)
    end
  end

  defp get_base_configs(keys \\ []) do
    configs = [
      name: :test_name,
      hostname: "hostname",
      username: "username",
      password: "password",
      database: "database",
      port: 5432,
      subscriptions: ["subscriptions"],
      publication: "publication",
      modules: ["modules"]
    ]

    case keys do
      [] -> configs
      _keys -> Keyword.take(configs, keys)
    end
  end
end
