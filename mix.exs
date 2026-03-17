defmodule Ltix.MixProject do
  use Mix.Project

  def project do
    [
      app: :ltix,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      package: package(),
      usage_rules: usage_rules(),

      # Docs
      name: "Ltix",
      description: "Ltix is an Elixir library for building LTI 1.3 applications.",
      source_url: "https://github.com/DecoyLex/ltix",
      homepage_url: "https://github.com/DecoyLex/ltix",
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

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/DecoyLex/ltix"},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE usage-rules.md usage-rules)
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:telemetry, "~> 1.4"},
      {:recase, "~> 0.9"},
      {:zoi, "~> 0.17"},
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
        "guides/comparing-lti-libraries.md",
        "guides/getting-started.md",
        "guides/testing-with-ims-ri.md",
        "guides/storage-adapters.md",
        "guides/working-with-roles.md",
        "guides/custom-role-parsers.md",
        "guides/custom-claim-parsers.md",
        "guides/error-handling.md",
        "guides/advantage-services.md",
        "guides/deep-linking.md",
        "guides/memberships-service.md",
        "guides/grade-service.md",
        "guides/jwk-management.md",
        "guides/telemetry.md",
        "guides/cookbooks/auto-create-deployments.md",
        "guides/cookbooks/testing-lti-launches.md",
        "guides/cookbooks/jwk-management.md",
        "guides/cookbooks/score-construction.md",
        "guides/cookbooks/background-grade-sync.md",
        "guides/cookbooks/canvas-grade-extensions.md",
        "guides/cookbooks/building-content-items.md",
        "guides/cookbooks/token-caching-and-reuse.md"
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
        About: [
          "guides/what-is-ltix.md",
          "guides/concepts.md",
          "guides/comparing-lti-libraries.md"
        ],
        Guides: [
          "guides/getting-started.md",
          "guides/testing-with-ims-ri.md",
          "guides/storage-adapters.md",
          "guides/working-with-roles.md",
          "guides/custom-role-parsers.md",
          "guides/custom-claim-parsers.md",
          "guides/error-handling.md",
          "guides/advantage-services.md",
          "guides/deep-linking.md",
          "guides/memberships-service.md",
          "guides/grade-service.md",
          "guides/jwk-management.md",
          "guides/telemetry.md"
        ],
        Cookbooks: [
          "guides/cookbooks/auto-create-deployments.md",
          "guides/cookbooks/testing-lti-launches.md",
          "guides/cookbooks/jwk-management.md",
          "guides/cookbooks/score-construction.md",
          "guides/cookbooks/background-grade-sync.md",
          "guides/cookbooks/canvas-grade-extensions.md",
          "guides/cookbooks/building-content-items.md",
          "guides/cookbooks/token-caching-and-reuse.md"
        ]
      ],
      nest_modules_by_prefix: [
        Ltix.JWT,
        Ltix.JWT.KeySet,
        Ltix.LaunchClaims,
        Ltix.LaunchClaims.Role,
        Ltix.DeepLinking,
        Ltix.DeepLinking.ContentItem,
        Ltix.MembershipsService,
        Ltix.GradeService,
        Ltix.OAuth,
        Ltix.Errors,
        Ltix.Errors.Invalid,
        Ltix.Errors.Security,
        Ltix.Errors.Unknown,
        Ltix.Test
      ],
      groups_for_modules: [
        Core: [
          Ltix.Deployable,
          Ltix.Registerable,
          Ltix.Registration,
          Ltix.Deployment,
          Ltix.LaunchContext,
          Ltix.StorageAdapter,
          Ltix.JWK
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
          Ltix.LaunchClaims.MembershipsEndpoint,
          Ltix.LaunchClaims.DeepLinkingSettings
        ],
        "Deep Linking": [
          Ltix.DeepLinking,
          Ltix.DeepLinking.ContentItem,
          Ltix.DeepLinking.Response,
          Ltix.DeepLinking.ContentItem.Link,
          Ltix.DeepLinking.ContentItem.LtiResourceLink,
          Ltix.DeepLinking.ContentItem.File,
          Ltix.DeepLinking.ContentItem.HtmlFragment,
          Ltix.DeepLinking.ContentItem.Image
        ],
        "Advantage Services": [
          Ltix.AdvantageService,
          Ltix.OAuth,
          Ltix.OAuth.Client,
          Ltix.OAuth.AccessToken,
          Ltix.Pagination
        ],
        "Memberships Service": [
          Ltix.MembershipsService,
          Ltix.MembershipsService.Member,
          Ltix.MembershipsService.MembershipContainer
        ],
        "Grade Service": [
          Ltix.GradeService,
          Ltix.GradeService.LineItem,
          Ltix.GradeService.Score,
          Ltix.GradeService.Result
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
