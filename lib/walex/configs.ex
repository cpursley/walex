defmodule WalEx.Configs do
  use Agent

  def start_link(opts) do
    configs =
      opts
      |> Keyword.get(:configs)
      |> build_app_configs()

    app_name = Keyword.get(configs, :name)

    name = WalEx.Registry.set_name(:set_agent, __MODULE__, app_name)

    Agent.start_link(fn -> configs end, name: name)
  end

  def get_configs(app_name, keys \\ []) when is_list(keys) do
    configs = WalEx.Registry.get_state(:get_agent, __MODULE__, app_name)

    if Enum.empty?(keys), do: configs, else: Keyword.take(configs, keys)
  end

  defp build_app_configs(configs) do
    db_configs_from_url =
      configs
      |> Keyword.get(:url, "")
      |> parse_url()

    [
      hostname: Keyword.get(configs, :hostname, db_configs_from_url[:hostname]),
      username: Keyword.get(configs, :username, db_configs_from_url[:username]),
      password: Keyword.get(configs, :password, db_configs_from_url[:password]),
      port: Keyword.get(configs, :port, db_configs_from_url[:port]),
      database: Keyword.get(configs, :database, db_configs_from_url[:database]),
      subscriptions: Keyword.get(configs, :subscriptions),
      publication: Keyword.get(configs, :publication),
      modules: Keyword.get(configs, :modules),
      name: Keyword.get(configs, :name)
    ]
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
end
