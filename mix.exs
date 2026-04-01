defmodule Duet.MixProject do
  use Mix.Project

  def project do
    [
      app: :duet,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      escript: escript(),
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix_pubsub, "~> 2.0"},
      {:yaml_elixir, "~> 2.9"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      build: ["escript.build"]
    ]
  end

  defp escript do
    [
      main_module: Duet.CLI,
      name: "duet",
      path: "bin/duet"
    ]
  end
end
