defmodule Msg.MixProject do
  use Mix.Project

  @version "0.1.1"
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
      app: :msg,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: @deps,
      description: "Microsoft Graph for Elixir",
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/riddler/msg"}
      ],
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit],
        warnings: [:unknown]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
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
