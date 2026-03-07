defmodule Ltix.MixProject do
  use Mix.Project

  def project do
    [
      app: :ltix,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      usage_rules: usage_rules()
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
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:req, "~> 0.5"},
      {:jose, "~> 1.11"},
      {:splode, "~> 0.3"},
      {:usage_rules, "~> 1.2", only: [:dev, :test], runtime: false},
      {:plug, "~> 1.19", optional: true}
    ]
  end

  defp usage_rules do
    # Example for those using claude.
    [
      file: "CLAUDE.md",
      usage_rules: ["usage_rules:all"],
      skills: [
        location: ".claude/skills",
        build: []
      ]
    ]
  end
end
