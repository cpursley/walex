defmodule WalEx.Config do
  use Agent

  alias WalEx.Config.Registry, as: WalExRegistry

  @allowed_config_value ~w(database hostname name password port publication username)a
  @allowed_config_values ~w(modules subscriptions)a

  def start_link(opts) do
    configs =
      opts
      |> Keyword.get(:configs)
      |> build_app_configs()

    app_name = Keyword.get(configs, :name)

    name = WalExRegistry.set_name(:set_agent, __MODULE__, app_name)

    Agent.start_link(fn -> configs end, name: name)
  end

  def get_configs(app_name, key) when is_atom(key) do
    WalExRegistry.get_state(:get_agent, __MODULE__, app_name)
    |> Keyword.get(key)
  end

  def get_configs(app_name, keys) when is_list(keys) and keys != [] do
    WalExRegistry.get_state(:get_agent, __MODULE__, app_name)
    |> Keyword.take(keys)
  end

  def get_configs(app_name, _keys) do
    WalExRegistry.get_state(:get_agent, __MODULE__, app_name)
  end

  def add_config(app_name, key, new_values)
      when is_list(new_values) and key in @allowed_config_values do
    Agent.update(set_agent(app_name), fn config ->
      updated_values =
        config
        |> Keyword.get(key, [])
        |> Enum.concat(new_values)
        |> Enum.uniq()

      Keyword.put(config, key, updated_values)
    end)
  end

  def add_config(app_name, key, new_value) when key in @allowed_config_values do
    add_config(app_name, key, [new_value])
  end

  def remove_config(app_name, key, new_value) when key in @allowed_config_values do
    Agent.update(set_agent(app_name), fn config ->
      updated_values =
        config
        |> Keyword.get(key, [])
        |> Enum.reject(&(&1 == new_value))
        |> Enum.uniq()

      Keyword.put(config, key, updated_values)
    end)
  end

  def replace_config(app_name, key, new_value) when key in @allowed_config_value do
    Agent.update(set_agent(app_name), fn config ->
      Keyword.put(config, key, new_value)
    end)
  end

  defp build_app_configs(configs) do
    db_configs_from_url =
      configs
      |> Keyword.get(:url, "")
      |> parse_url()

    name = Keyword.get(configs, :name)
    subscriptions = Keyword.get(configs, :subscriptions, [])
    modules = Keyword.get(configs, :modules, [])

    [
      name: name,
      publication: Keyword.get(configs, :publication),
      subscriptions: subscriptions,
      modules: build_module_names(name, modules, subscriptions),
      destinations: Keyword.get(configs, :destinations),
      webhook_signing_secret: Keyword.get(configs, :webhook_signing_secret),
      event_relay: Keyword.get(configs, :event_relay),
      hostname: Keyword.get(configs, :hostname, db_configs_from_url[:hostname]),
      username: Keyword.get(configs, :username, db_configs_from_url[:username]),
      password: Keyword.get(configs, :password, db_configs_from_url[:password]),
      port: Keyword.get(configs, :port, db_configs_from_url[:port]),
      database: Keyword.get(configs, :database, db_configs_from_url[:database]),
      ssl: Keyword.get(configs, :ssl, false),
      ssl_opts: Keyword.get(configs, :ssl_opts, verify: :verify_none)
    ]
  end

  def build_module_names(name, modules, subscriptions)
      when is_list(modules) and is_list(subscriptions) do
    subscriptions
    |> map_subscriptions_to_modules(name)
    |> Enum.concat(modules)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def build_module_names(_name, _modules, _subscriptions), do: nil

  def map_subscriptions_to_modules(subscriptions, name) do
    Enum.map(subscriptions, fn subscription ->
      (to_string(name) <> "." <> "Events" <> "." <> to_module_name(subscription))
      |> String.to_atom()
    end)
  end

  def to_module_name(subscription) when is_atom(subscription) or is_binary(subscription) do
    subscription
    |> to_string()
    |> String.split("_")
    |> Enum.map_join(&String.capitalize/1)
  end

  defp parse_url(""), do: []

  defp parse_url(url) when is_binary(url) do
    info = URI.parse(url)

    if is_nil(info.host), do: raise("host is not present")

    if is_nil(info.path) or not (info.path =~ ~r"^/([^/])+$"),
      do: raise("path should be a database name")

    destructure [username, password], info.userinfo && String.split(info.userinfo, ":")
    "/" <> database = info.path

    url_opts = set_url_opts(username, password, database, info)

    for {k, v} <- url_opts,
        not is_nil(v),
        do: {k, if(is_binary(v), do: URI.decode(v), else: v)}
  end

  defp set_url_opts(username, password, database, info) do
    url_opts = [
      username: username,
      password: password,
      database: database,
      port: info.port
    ]

    put_hostname_if_present(url_opts, info.host)
  end

  defp put_hostname_if_present(keyword, ""), do: keyword

  defp put_hostname_if_present(keyword, hostname) when is_binary(hostname) do
    Keyword.put(keyword, :hostname, hostname)
  end

  defp set_agent(app_name), do: WalEx.Config.Registry.set_name(:set_agent, __MODULE__, app_name)
end
