defmodule Ltix.MixProject do
  use Mix.Project

  def project do
    [
      app: :ltix,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      usage_rules: usage_rules(),

      # Docs
      name: "Ltix",
      description: "Ltix is an Elixir library for building LTI 1.3 applications.",
      source_url: "https://github.com/DecoyLex/ltix",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false, warn_if_outdated: true},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:req, "~> 0.5"},
      {:jose, "~> 1.11"},
      {:splode, "~> 0.3"},
      {:usage_rules, "~> 1.2", only: [:dev, :test], runtime: false},
      {:plug, "~> 1.19", optional: true}
    ]
  end

  defp docs do
    [
      main: "Ltix",
      extras: ["README.md"],
      groups_for_modules: [
        "OIDC Flow": [
          Ltix.OIDC.LoginInitiation,
          Ltix.OIDC.AuthenticationRequest,
          Ltix.OIDC.Callback
        ],
        JWT: [
          Ltix.JWT.Token,
          Ltix.JWT.KeySet
        ],
        "Launch Claims": [
          Ltix.LaunchClaims,
          Ltix.LaunchClaims.Role,
          Ltix.LaunchClaims.Context,
          Ltix.LaunchClaims.ResourceLink,
          Ltix.LaunchClaims.LaunchPresentation,
          Ltix.LaunchClaims.ToolPlatform,
          Ltix.LaunchClaims.Lis,
          Ltix.LaunchClaims.AgsEndpoint,
          Ltix.LaunchClaims.NrpsEndpoint,
          Ltix.LaunchClaims.DeepLinkingSettings
        ],
        Errors: [
          Ltix.Errors,
          Ltix.Errors.Invalid,
          Ltix.Errors.Security,
          Ltix.Errors.Unknown
        ]
      ]
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
