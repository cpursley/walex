defmodule WalEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :walex,
      version: "3.1.0",
      elixir: "~> 1.15",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      name: "WalEx",
      source_url: "https://github.com/cpursley/walex"
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
      {:postgrex, "~> 0.17.4"},
      {:decimal, "~> 2.1.1"},
      {:ex_doc, "~> 0.30.9", only: :dev, runtime: false},
      {:jason, "~> 1.4"},
      {:map_diff, "~> 1.3"},
      {:retry, "~> 0.18.0"},
      {:timex, "~> 3.7"}
    ]
  end

  defp description() do
    "Listen to change events on your Postgres tables then perform callback-like actions with the data."
  end

  defp package() do
    [
      files: ~w(lib test .formatter.exs mix.exs README* LICENSE*),
      maintainers: ["Chase Pursley"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/cpursley/walex"}
    ]
  end
end
