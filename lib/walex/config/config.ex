defmodule WalEx.Config do
  @moduledoc """
  Configuration
  """
  use Agent

  alias WalEx.Config.Registry, as: WalExRegistry

  @allowed_config_value ~w(database hostname name password port publication username webhook_signing_secret slot_name durable_slot)a
  @allowed_config_values ~w(destinations event_relay modules subscriptions)a

  def start_link(opts) do
    configs =
      opts
      |> Keyword.get(:configs)
      |> build_app_configs()

    app_name = Keyword.get(configs, :name)

    name = WalExRegistry.set_name(:set_agent, __MODULE__, app_name)

    Agent.start_link(fn -> configs end, name: name)
  end

  def has_config?(configs, key) when is_list(configs) do
    Keyword.has_key?(configs, key) and not is_nil(Keyword.get(configs, key))
  end

  def has_config?(_configs, _key), do: false

  def get_configs(app_name) do
    WalExRegistry.get_state(:get_agent, __MODULE__, app_name)
  end

  def get_configs(app_name, key) when is_atom(key) do
    WalExRegistry.get_state(:get_agent, __MODULE__, app_name)
    |> Keyword.get(key)
  end

  def get_configs(app_name, keys) when is_list(keys) and keys != [] do
    order_map = keys |> Enum.with_index() |> Map.new()

    WalExRegistry.get_state(:get_agent, __MODULE__, app_name)
    |> Keyword.take(keys)
    |> Enum.sort_by(fn {k, _} -> Map.get(order_map, k) end)
  end

  def get_database(app_name), do: get_configs(app_name, :database)

  def get_destination(app_name, destination) do
    case get_configs(app_name, :destinations) do
      destinations when is_list(destinations) and destinations != [] ->
        destinations
        |> Keyword.get(destination, nil)

      _ ->
        nil
    end
  end

  def get_event_modules(app_name), do: get_destination(app_name, :modules)

  def get_webhooks(app_name), do: get_destination(app_name, :webhooks)

  def get_event_relay_topic(app_name), do: get_destination(app_name, :event_relay_topic)

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
    destinations = Keyword.get(configs, :destinations, [])
    modules = Keyword.get(destinations, :modules, [])
    module_names = build_module_names(name, modules, subscriptions)

    [
      name: name,
      hostname: Keyword.get(configs, :hostname, db_configs_from_url[:hostname]),
      username: Keyword.get(configs, :username, db_configs_from_url[:username]),
      password: Keyword.get(configs, :password, db_configs_from_url[:password]),
      port: Keyword.get(configs, :port, db_configs_from_url[:port]),
      database: Keyword.get(configs, :database, db_configs_from_url[:database]),
      ssl: Keyword.get(configs, :ssl, false),
      ssl_opts: Keyword.get(configs, :ssl_opts, verify: :verify_none),
      socket_options: Keyword.get(configs, :socket_options, []),
      subscriptions: subscriptions,
      publication: Keyword.get(configs, :publication),
      destinations: Keyword.put(destinations, :modules, module_names),
      webhook_signing_secret: Keyword.get(configs, :webhook_signing_secret),
      event_relay: Keyword.get(configs, :event_relay),
      slot_name: Keyword.get(configs, :slot_name) |> parse_slot_name(name),
      durable_slot: Keyword.get(configs, :durable_slot, false) == true
    ]
  end

  def build_module_names(name, modules, subscriptions)
      when is_list(modules) and is_list(subscriptions) do
    subscriptions
    |> map_subscriptions_to_modules(name)
    |> Enum.concat(modules)
    |> Enum.uniq()
    |> map_existing_modules()
    |> Enum.sort()
  end

  def build_module_names(_name, _modules, _subscriptions), do: nil

  def map_subscriptions_to_modules(subscriptions, name) do
    Enum.map(subscriptions, fn subscription ->
      (to_module_name(name) <> "." <> "Events" <> "." <> to_module_name(subscription))
      |> String.to_atom()
    end)
  end

  def to_module_name(module_name) when is_atom(module_name) or is_binary(module_name) do
    module_name
    |> to_string()
    |> String.split(["_"])
    |> Enum.map_join(&capitalize/1)
  end

  defp capitalize(name) do
    if String.at(name, 0) == String.upcase(String.at(name, 0)) do
      name
    else
      String.capitalize(name)
    end
  end

  defp module_exists?(module_name) do
    case Code.ensure_compiled(module_name) do
      {:module, _module} ->
        true

      {:error, _error} ->
        false
    end
  end

  defp map_existing_modules(modules), do: Enum.filter(modules, &module_exists?/1)

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

  defp parse_slot_name(nil, app_name), do: to_string(app_name) <> "_walex"
  defp parse_slot_name(slot_name, _), do: slot_name

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
