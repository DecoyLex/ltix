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
      {:plug, "~> 1.19", optional: true},
      {:cachex, "~> 4.0", optional: true}
    ]
  end

  defp docs do
    [
      main: "Ltix",
      extras: [
        "README.md",
        "guides/what-is-ltix.md",
        "guides/concepts.md",
        "guides/getting-started.md",
        "guides/storage-adapters.md",
        "guides/working-with-roles.md",
        "guides/error-handling.md"
      ],
      before_closing_body_tag: fn
        :html ->
          """
          <script defer src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
          <script>
            let initialized = false;
            window.addEventListener("exdoc:loaded", () => {
              if (!initialized) {
                mermaid.initialize({
                  startOnLoad: false,
                  theme: document.body.className.includes("dark") ? "dark" : "default"
                });
                initialized = true;
              }
              let id = 0;
              for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
                const preEl = codeEl.parentElement;
                const graphDefinition = codeEl.textContent;
                const graphEl = document.createElement("div");
                const graphId = "mermaid-graph-" + id++;
                mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
                  graphEl.innerHTML = svg;
                  bindFunctions?.(graphEl);
                  preEl.insertAdjacentElement("afterend", graphEl);
                  preEl.remove();
                });
              }
            });
          </script>
          """

        _ ->
          ""
      end,
      groups_for_extras: [
        About: ["guides/what-is-ltix.md", "guides/concepts.md"],
        Guides: [
          "guides/getting-started.md",
          "guides/storage-adapters.md",
          "guides/working-with-roles.md",
          "guides/error-handling.md"
        ]
      ],
      nest_modules_by_prefix: [
        Ltix.JWT,
        Ltix.JWT.KeySet,
        Ltix.LaunchClaims,
        Ltix.LaunchClaims.Role,
        Ltix.Errors,
        Ltix.Errors.Invalid,
        Ltix.Errors.Security,
        Ltix.Errors.Unknown,
        Ltix.Test
      ],
      groups_for_modules: [
        Core: [
          Ltix.Registration,
          Ltix.Deployment,
          Ltix.LaunchContext,
          Ltix.StorageAdapter
        ],
        JWT: [
          Ltix.JWT.Token,
          Ltix.JWT.KeySet,
          Ltix.JWT.KeySet.Cache,
          Ltix.JWT.KeySet.EtsCache,
          Ltix.JWT.KeySet.CachexCache
        ],
        "Launch Claims": [
          Ltix.LaunchClaims,
          Ltix.LaunchClaims.Role,
          Ltix.LaunchClaims.Role.LIS,
          Ltix.LaunchClaims.Role.Parser,
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
        ],
        Testing: [
          Ltix.Test,
          Ltix.Test.Platform,
          Ltix.Test.StorageAdapter
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
