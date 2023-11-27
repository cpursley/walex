defmodule WalEx.ConfigsTest do
  use ExUnit.Case, async: false

  alias WalEx.Configs

  setup do
    {:ok, _pid} = WalEx.Registry.start_registry()
    :ok
  end

  describe "start_link/2" do
    test "should start a process" do
      assert {:ok, pid} = Configs.start_link(configs: get_base_configs())

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

      Configs.start_link(configs: configs)

      assert [
               hostname: "hostname",
               username: "username",
               password: "password",
               port: 5432,
               database: "database",
               ssl: false,
               ssl_opts: [verify: :verify_none]
             ] ==
               Configs.get_configs(:test_name, [
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

  describe "get_configs/2" do
    setup do
      {:ok, _pid} = Configs.start_link(configs: get_base_configs())
      :ok
    end

    test "should return all configs when second parameter is not sent" do
      assert [
               hostname: "hostname",
               username: "username",
               password: "password",
               port: 5432,
               database: "database",
               subscriptions: ["subscriptions"],
               publication: "publication",
               modules: ["modules"],
               name: :test_name,
               ssl: false,
               ssl_opts: [verify: :verify_none]
             ] == Configs.get_configs(:test_name)
    end

    test "should return only selected configs when second parameter is require a filter" do
      assert [
               hostname: "hostname",
               modules: ["modules"],
               ssl: false,
               ssl_opts: [verify: :verify_none]
             ] ==
               Configs.get_configs(:test_name, [:modules, :hostname, :ssl, :ssl_opts])
    end

    test "should filter configs by process name" do
      configs =
        get_base_configs()
        |> Keyword.replace(:name, :other_name)
        |> Keyword.replace(:database, "other_database")

      {:ok, _pid} = Configs.start_link(configs: configs)

      assert [
               database: "database",
               name: :test_name,
               ssl: false,
               ssl_opts: [verify: :verify_none]
             ] ==
               Configs.get_configs(:test_name, [:database, :name, :ssl, :ssl_opts])

      assert [
               database: "other_database",
               name: :other_name,
               ssl: false,
               ssl_opts: [verify: :verify_none]
             ] ==
               Configs.get_configs(:other_name, [:database, :name, :ssl, :ssl_opts])
    end
  end

  describe "add_config/3" do
    setup do
      {:ok, _pid} = Configs.start_link(configs: get_base_configs())
      :ok
    end

    test "should add new values when new_values is a list" do
      Configs.add_config(:test_name, :subscriptions, [
        "new_subscriptions_1",
        "new_subscriptions_2"
      ])

      assert ["subscriptions", "new_subscriptions_1", "new_subscriptions_2"] ==
               Configs.get_configs(:test_name)[:subscriptions]
    end

    test "should add new values when new_value is not a list" do
      Configs.add_config(:test_name, :subscriptions, "new_subscriptions")

      assert ["subscriptions", "new_subscriptions"] ==
               Configs.get_configs(:test_name)[:subscriptions]
    end
  end

  describe "remove_config/3" do
    setup do
      {:ok, _pid} = Configs.start_link(configs: get_base_configs())
      :ok
    end

    test "should remove existing value from list if it exists" do
      Configs.add_config(:test_name, :subscriptions, [
        "new_subscriptions_1",
        "new_subscriptions_2"
      ])

      assert ["subscriptions", "new_subscriptions_1", "new_subscriptions_2"] ==
               Configs.get_configs(:test_name)[:subscriptions]

      Configs.remove_config(:test_name, :subscriptions, "subscriptions")

      assert ["new_subscriptions_1", "new_subscriptions_2"] ==
               Configs.get_configs(:test_name)[:subscriptions]
    end
  end

  describe "replace_config/3" do
    setup do
      {:ok, _pid} = Configs.start_link(configs: get_base_configs())
      :ok
    end

    test "should replace existing value when value is not a list" do
      assert "password" == Configs.get_configs(:test_name)[:password]

      Configs.replace_config(:test_name, :password, "new_password")

      assert "new_password" == Configs.get_configs(:test_name)[:password]
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
      modules: ["modules"],
      ssl: false,
      ssl_opts: [verify: :verify_none]
    ]

    case keys do
      [] -> configs
      _keys -> Keyword.take(configs, keys)
    end
  end
end
