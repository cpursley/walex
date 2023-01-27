defmodule WalEx.Supervisor do
  use Supervisor

  @config Application.compile_env(:walex, WalEx)

  def child_spec(config) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [config]}
    }
  end

  def start_link(config) do
    Supervisor.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(_) do
    config_from_url = if has_url?(), do: parse_url(@config[:url])

    children = [
      {
        WalEx.DatabaseReplicationSupervisor,
        hostname: @config[:hostname] || config_from_url[:hostname],
        username: @config[:username] || config_from_url[:username],
        password: @config[:password] || config_from_url[:password],
        port: @config[:port] || config_from_url[:port],
        database: @config[:database] || config_from_url[:database],
        subscriptions: @config[:subscriptions],
        publication: @config[:publication]
      },
      {
        WalEx.Events,
        module: @config[:modules]
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp has_url?, do: is_bitstring(@config[:url]) and @config[:url] != ""

  defp parse_url(""), do: []

  defp parse_url(url) when is_binary(url) do
    info = URI.parse(url)

    if is_nil(info.host), do: raise("host is not present")

    if is_nil(info.path) or not (info.path =~ ~r"^/([^/])+$"),
      do: raise("path should be a database name")

    destructure [username, password], info.userinfo && String.split(info.userinfo, ":")
    "/" <> database = info.path

    url_opts = [
      username: username,
      password: password,
      database: database,
      port: info.port
    ]

    url_opts = put_hostname_if_present(url_opts, info.host)

    for {k, v} <- url_opts,
        not is_nil(v),
        do: {k, if(is_binary(v), do: URI.decode(v), else: v)}
  end

  defp put_hostname_if_present(keyword, ""), do: keyword

  defp put_hostname_if_present(keyword, hostname) when is_binary(hostname) do
    Keyword.put(keyword, :hostname, hostname)
  end
end
