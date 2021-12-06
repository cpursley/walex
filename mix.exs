# TODO ~ change module name to WalEx (capital "E")
defmodule WalEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :walex,
      version: "0.1.0",
      elixir: "~> 1.12.3",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:decimal, "~> 2.0"},
      {:epgsql, "~> 4.6.0"},
      {:jason, "~> 1.2.2"},
      {:map_diff, "~> 1.3"},
      {:retry, "~> 0.15.0"},
      {:timex, "~> 3.7.6"}
    ]
  end
end
