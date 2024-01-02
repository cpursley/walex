defmodule WalEx.SupervisorTest do
  use ExUnit.Case, async: false

  alias WalEx.Supervisor, as: WalExSupervisor
  alias WalEx.Replication
  alias Replication.Supervisor, as: ReplicationSupervisor
  alias Replication.Server, as: ReplicationServer
  alias Replication.Publisher, as: ReplicationPublisher

  describe "start_link/2" do
    test "should start Supervisor and child processes" do
      assert {:ok, walex_supervisor_pid} = WalExSupervisor.start_link(get_base_configs())
      assert is_pid(walex_supervisor_pid)

      assert %{active: 6, workers: 5, supervisors: 1, specs: 6} =
               Supervisor.count_children(walex_supervisor_pid)

      replication_supervisor_pid =
        find_worker_pid(walex_supervisor_pid, ReplicationSupervisor)

      assert is_pid(replication_supervisor_pid)

      replication_publisher_pid =
        find_worker_pid(replication_supervisor_pid, ReplicationPublisher)

      assert is_pid(replication_publisher_pid)

      replication_server_pid =
        find_worker_pid(replication_supervisor_pid, ReplicationServer)

      assert is_pid(replication_server_pid)
    end

    test "should raise if any required config is missing" do
      assert_raise RuntimeError,
                   "Following required configs are missing: [:hostname, :username, :password, :port, :database, :subscriptions, :publication, :name]",
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

  def find_worker_pid(supervisor_pid, child_module) do
    case Supervisor.which_children(supervisor_pid) do
      children when is_list(children) ->
        find_pid(children, child_module)

      _ ->
        {:error, :supervisor_not_running}
    end
  end

  defp find_pid(children, module_name) do
    {_, pid, _, _} = Enum.find(children, fn {module, _, _, _} -> module == module_name end)
    pid
  end

  defp get_base_configs(keys \\ []) do
    configs = [
      name: :test_name,
      hostname: "hostname",
      username: "username",
      password: "password",
      database: "todos_test",
      port: 5432,
      subscriptions: ["subscriptions"],
      publication: "publication"
    ]

    case keys do
      [] ->
        configs

      _keys ->
        Keyword.take(configs, keys)
    end
  end
end
