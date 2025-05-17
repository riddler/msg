defmodule Msg.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :msg,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Microsoft Graph API client for Elixir",
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/riddler/msg"}
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.4"},
      {:oauth2, "~> 2.0"},
      {:jason, "~> 1.4"},
      {:mox, "~> 1.1", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
