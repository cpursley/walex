defmodule WalEx.ConfigTest do
  use ExUnit.Case, async: false

  alias WalEx.Config
  alias Config.Registry, as: WalExRegistry

  setup_all do
    {:ok, pid} = WalExRegistry.start_registry()
    :timer.sleep(1000)
    :ok
  end

  describe "start_link/2" do
    test "should start a process" do
      {:ok, pid} = Config.start_link(configs: get_base_configs())
      assert is_pid(pid)
    end

    test "should accept database url as config and split it into the right configs" do
      configs = [
        name: :test_name,
        url: "postgres://username:password@hostname:5432/database",
        subscriptions: ["subscriptions"],
        publication: "publication",
        modules: ["modules"]
      ]

      {:ok, pid} = Config.start_link(configs: configs)
      assert is_pid(pid)

      assert [
               hostname: "hostname",
               username: "username",
               password: "password",
               port: 5432,
               database: "database",
               ssl: false,
               ssl_opts: [verify: :verify_none]
             ] ==
               Config.get_configs(:test_name, [
                 :hostname,
                 :username,
                 :password,
                 :database,
                 :port,
                 :ssl,
                 :ssl_opts
               ])
    end
  end

  describe "get_configs/" do
    setup do
      {:ok, pid} = Config.start_link(configs: get_base_configs())
      :ok
    end

    test "should return all configs" do
      assert [
               name: :test_name,
               publication: "publication",
               subscriptions: ["subscriptions"],
               modules: [MyApp.CustomModule, :"TestName.Events.Subscriptions"],
               destinations: nil,
               webhook_signing_secret: nil,
               event_relay: nil,
               hostname: "hostname",
               username: "username",
               password: "password",
               port: 5432,
               database: "database",
               ssl: false,
               ssl_opts: [verify: :verify_none]
             ] == Config.get_configs(:test_name)
    end
  end

  describe "get_configs/2" do
    setup do
      {:ok, pid} = Config.start_link(configs: get_base_configs())
      :ok
    end

    test "should return only selected configs when second parameter is an atom" do
      assert ["subscriptions"] == Config.get_configs(:test_name, :subscriptions)
    end

    test "should return only selected configs when second parameter is a list" do
      assert [
               modules: [MyApp.CustomModule, :"TestName.Events.Subscriptions"],
               hostname: "hostname",
               ssl: false,
               ssl_opts: [verify: :verify_none]
             ] ==
               Config.get_configs(:test_name, [:modules, :hostname, :ssl, :ssl_opts])
    end

    test "should filter configs by process name" do
      configs =
        get_base_configs()
        |> Keyword.replace(:name, :other_name)
        |> Keyword.replace(:database, "other_database")

      {:ok, pid} = Config.start_link(configs: configs)
      assert is_pid(pid)

      assert [
               name: :test_name,
               database: "database",
               ssl: false,
               ssl_opts: [verify: :verify_none]
             ] ==
               Config.get_configs(:test_name, [:database, :name, :ssl, :ssl_opts])

      assert [
               name: :other_name,
               database: "other_database",
               ssl: false,
               ssl_opts: [verify: :verify_none]
             ] ==
               Config.get_configs(:other_name, [:database, :name, :ssl, :ssl_opts])
    end
  end

  describe "add_config/3" do
    setup do
      {:ok, pid} = Config.start_link(configs: get_base_configs())
      :ok
    end

    test "should add new values when new_values is a list" do
      Config.add_config(:test_name, :subscriptions, [
        "new_subscriptions_1",
        "new_subscriptions_2"
      ])

      assert ["subscriptions", "new_subscriptions_1", "new_subscriptions_2"] ==
               Config.get_configs(:test_name)[:subscriptions]
    end

    test "should add new values when new_value is not a list" do
      Config.add_config(:test_name, :subscriptions, "new_subscriptions")

      assert ["subscriptions", "new_subscriptions"] ==
               Config.get_configs(:test_name)[:subscriptions]
    end
  end

  describe "remove_config/3" do
    setup do
      {:ok, pid} = Config.start_link(configs: get_base_configs())
      :ok
    end

    test "should remove existing value from list if it exists" do
      Config.add_config(:test_name, :subscriptions, [
        "new_subscriptions_1",
        "new_subscriptions_2"
      ])

      assert ["subscriptions", "new_subscriptions_1", "new_subscriptions_2"] ==
               Config.get_configs(:test_name)[:subscriptions]

      Config.remove_config(:test_name, :subscriptions, "subscriptions")

      assert ["new_subscriptions_1", "new_subscriptions_2"] ==
               Config.get_configs(:test_name)[:subscriptions]
    end
  end

  describe "replace_config/3" do
    setup do
      {:ok, pid} = Config.start_link(configs: get_base_configs())
      :ok
    end

    test "should replace existing value when value is not a list" do
      assert "password" == Config.get_configs(:test_name)[:password]

      Config.replace_config(:test_name, :password, "new_password")

      assert "new_password" == Config.get_configs(:test_name)[:password]
    end
  end

  describe "build_module_names/3" do
    setup do
      {:ok, pid} = Config.start_link(configs: get_base_configs())
      :ok
    end

    test "should create list of modules from subscriptions config when no modules" do
      subscriptions = ["subscriptions"]

      assert [:"TestName.Events.Subscriptions"] ==
               Config.build_module_names(:test_name, [], subscriptions)
    end

    test "should create list of modules from modules config when no subscriptions" do
      modules = [MyApp.CustomModule]

      assert modules == Config.build_module_names(:test_name, modules, [])
    end

    test "should create list of modules when both modules and subscriptions config" do
      subscriptions = ["subscriptions"]
      modules = [MyApp.CustomModule]

      assert [MyApp.CustomModule, :"TestName.Events.Subscriptions"] ==
               Config.build_module_names(:test_name, modules, subscriptions)
    end
  end

  describe "to_module_name/1" do
    setup do
      {:ok, pid} = Config.start_link(configs: get_base_configs())
      :ok
    end

    test "should convert standard atom into Module atom" do
      assert "TestName" == Config.to_module_name(:test_name)
    end

    test "should convert binary string into Module atom" do
      assert "TestName" == Config.to_module_name("test_name")
    end

    test "should convert remove 'Elixir.' from module name" do
      assert "TestName" == Config.to_module_name(:"Elixir.TestName")
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
      modules: [MyApp.CustomModule],
      ssl: false,
      ssl_opts: [verify: :verify_none]
    ]

    case keys do
      [] ->
        configs

      _keys ->
        Keyword.take(configs, keys)
    end
  end
end
