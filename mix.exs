defmodule Mudc.MixProject do
  use Mix.Project

  def project do
    [
      app: :mudc,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # Documentation
      name: "Mudc",
      source_url: "https://github.com/user/mudc",
      docs: [
        main: "readme",
        extras: ["README.md", "CLAUDE.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {Mudc.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:term_ui, github: "pcharbon70/term_ui"},
      {:jason, "~> 1.4"},
      {:luerl, "~> 1.2"},
      {:file_system, "~> 1.0"},
      {:mox, "~> 1.0", only: :test},
      {:stream_data, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
