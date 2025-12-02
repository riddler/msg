defmodule Msg.MixProject do
  use Mix.Project

  @app :msg
  @version "0.3.8"
  @source_url "https://github.com/riddler/msg"
  @deps [
    # Docs - separated out to speed up dev compilcation
    {:ex_doc, "~> 0.31", only: :docs, runtime: false},

    # Development, Test, Local
    {:castore, "~> 1.0", only: [:dev, :test]},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:excoveralls, "~> 0.18", only: :test},
    {:mox, "~> 1.1", only: :test},

    # Actual dependencies
    {:jason, "~> 1.4"},
    {:oauth2, "~> 2.0"},
    {:req, "~> 0.4"}
  ]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: @deps,
      description: "Microsoft Graph for Elixir",
      test_coverage: [tool: ExCoveralls],
      package: package(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit],
        warnings: [:unknown]
      ]
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      name: @app,
      files: ~w(lib/msg* mix.exs README.md LICENSE),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Riddler Team"]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.json": :test,
        docs: :docs,
        quality: :test
      ]
    ]
  end
end
