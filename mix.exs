defmodule Ltix.MixProject do
  use Mix.Project

  def project do
    [
      app: :ltix,
      version: "0.2.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
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

  def cli do
    [preferred_envs: [precommit: :test]]
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

  defp aliases do
    [
      precommit: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "test"
      ]
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
      {:jason, "~> 1.4", optional: true},
      {:splode, "~> 0.3"},
      {:usage_rules, "~> 1.2", only: [:dev, :test], runtime: false},
      {:plug, "~> 1.19", optional: true}
    ]
  end

  defp docs do
    [
      main: "Ltix",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/what-is-ltix.md",
        "guides/concepts.md",
        "guides/comparing-lti-libraries.md",
        "guides/threat-model.md",
        "guides/getting-started.md",
        "guides/testing-with-ims-ri.md",
        "guides/storage-adapters.md",
        "guides/upgrading-to-0.2.md",
        "guides/upgrading-to-0.3.md",
        "guides/working-with-roles.md",
        "guides/error-handling.md",
        "guides/advantage-services.md",
        "guides/deep-linking.md",
        "guides/memberships-service.md",
        "guides/grade-service.md",
        "guides/writing-plugins.md",
        "guides/writing-claim-and-launch-plugins.md",
        "guides/jwk-management.md",
        "guides/hardening.md",
        "guides/telemetry.md",
        "guides/cookbooks/auto-create-deployments.md",
        "guides/cookbooks/testing-lti-launches.md",
        "guides/cookbooks/managing-jwks-with-ecto.md",
        "guides/cookbooks/score-construction.md",
        "guides/cookbooks/persisting-service-endpoints.md",
        "guides/cookbooks/background-grade-sync.md",
        "guides/cookbooks/canvas-grade-extensions.md",
        "guides/cookbooks/building-content-items.md",
        "guides/cookbooks/token-caching-and-reuse.md",
        "guides/cookbooks/custom-advantage-service.md",
        "guides/cookbooks/platform-storage.md"
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
          "guides/comparing-lti-libraries.md",
          "guides/threat-model.md"
        ],
        "Getting started": [
          "guides/getting-started.md",
          "guides/testing-with-ims-ri.md",
          "guides/storage-adapters.md",
          "guides/upgrading-to-0.2.md",
          "guides/upgrading-to-0.3.md"
        ],
        "Launch flow": [
          "guides/working-with-roles.md",
          "guides/error-handling.md"
        ],
        Services: [
          "guides/advantage-services.md",
          "guides/deep-linking.md",
          "guides/memberships-service.md",
          "guides/grade-service.md"
        ],
        Plugins: [
          "guides/writing-plugins.md",
          "guides/writing-claim-and-launch-plugins.md"
        ],
        Operations: [
          "guides/jwk-management.md",
          "guides/hardening.md",
          "guides/telemetry.md"
        ],
        Cookbooks: [
          "guides/cookbooks/auto-create-deployments.md",
          "guides/cookbooks/testing-lti-launches.md",
          "guides/cookbooks/managing-jwks-with-ecto.md",
          "guides/cookbooks/score-construction.md",
          "guides/cookbooks/persisting-service-endpoints.md",
          "guides/cookbooks/background-grade-sync.md",
          "guides/cookbooks/canvas-grade-extensions.md",
          "guides/cookbooks/building-content-items.md",
          "guides/cookbooks/token-caching-and-reuse.md",
          "guides/cookbooks/custom-advantage-service.md",
          "guides/cookbooks/platform-storage.md"
        ]
      ],
      nest_modules_by_prefix: [
        Ltix.JWT,
        Ltix.JWT.KeySet,
        Ltix.Claims,
        Ltix.Launch,
        Ltix.Login,
        Ltix.PluginSet,
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
      redirects: %{
        "custom-claim-parsers" => "writing-claim-and-launch-plugins",
        "custom-role-parsers" => "working-with-roles"
      },
      groups_for_modules: [
        Core: [
          Ltix.Deployable,
          Ltix.Registerable,
          Ltix.Registration,
          Ltix.Deployment,
          Ltix.StorageAdapter,
          Ltix.JWK
        ],
        Plugins: [
          Ltix.Plugin,
          Ltix.PluginSet,
          Ltix.PluginSet.Conflict,
          Ltix.DefaultPlugins,
          Ltix.Core,
          Ltix.Provider,
          Ltix.Step,
          Ltix.Ordered,
          Ltix.Property,
          Ltix.Type,
          Ltix.Behaviour
        ],
        Login: [
          Ltix.Login,
          Ltix.Login.RegistrationFound
        ],
        JWT: [
          Ltix.JWT.Token,
          Ltix.JWT.KeySet
        ],
        Launch: [
          Ltix.Launch,
          Ltix.Launch.Verified,
          Ltix.Launch.ClaimsReceived,
          Ltix.Launch.ClaimsParsed,
          Ltix.Launch.Validated
        ],
        Claims: [
          Ltix.Claim,
          Ltix.Claims,
          Ltix.Role,
          ~r/^Ltix\.Claims\./
        ],
        "Deep Linking": [
          Ltix.DeepLinking,
          Ltix.DeepLinking.ContentItem,
          Ltix.DeepLinking.Response,
          Ltix.DeepLinking.Settings,
          Ltix.DeepLinking.ContentItem.Link,
          Ltix.DeepLinking.ContentItem.LTIResourceLink,
          Ltix.DeepLinking.ContentItem.File,
          Ltix.DeepLinking.ContentItem.HTMLFragment,
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
          Ltix.MembershipsService.Endpoint,
          Ltix.MembershipsService.Member,
          Ltix.MembershipsService.MembershipContainer
        ],
        "Grade Service": [
          Ltix.GradeService,
          Ltix.GradeService.Endpoint,
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
    [
      file: "AGENTS.md",
      usage_rules: ["usage_rules:all"],
      skills: [
        location: ".claude/skills",
        build: []
      ]
    ]
  end
end
