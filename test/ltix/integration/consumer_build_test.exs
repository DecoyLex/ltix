defmodule Ltix.Integration.ConsumerBuildTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 120_000

  @providers if(Code.ensure_loaded?(JSON), do: [{:native, JSON, ""}], else: []) ++
               [{:jason, Jason, ", {:jason, \"~> 1.4\"}"}]

  for {provider, json_library, json_dependency} <- @providers do
    test "consumers use #{provider} JSON and core helpers without optional HTTP dependencies" do
      library = File.cwd!()

      project =
        Path.join(System.tmp_dir!(), "ltix-consumer-#{System.unique_integer([:positive])}")

      File.mkdir_p!(project)
      on_exit(fn -> File.rm_rf!(project) end)

      json_dependency = unquote(json_dependency)

      File.write!(Path.join(project, "mix.exs"), """
      defmodule Consumer.MixProject do
        use Mix.Project
        def project do
          [app: :consumer, version: "0.1.0",
           deps: [{:ltix, path: #{inspect(library)}}, {:jose, "~> 1.11"}#{json_dependency}]]
        end
        def application, do: [extra_applications: [:logger]]
      end
      """)

      File.mkdir_p!(Path.join(project, "config"))
      json_library = unquote(json_library)

      File.write!(Path.join(project, "config/config.exs"), """
      import Config
      config :ltix, :json_library, #{inspect(json_library)}
      """)

      File.cp!(Path.join(library, "mix.lock"), Path.join(project, "mix.lock"))
      File.ln_s!(Path.join(library, "deps"), Path.join(project, "deps"))

      File.write!(Path.join(project, "verify.exs"), """
      ExUnit.start()
      defmodule ConsumerTest do
        use ExUnit.Case
        test "core parsing and signing work without HTTP stubs" do
          refute Code.ensure_loaded?(Plug.Conn)
          refute Code.ensure_loaded?(Cachex)
          tool_key = Ltix.JWK.generate(key_size: 2048)
          {:ok, registration} = Ltix.Registration.new(%{
            issuer: "https://platform.example.com", client_id: "consumer",
            auth_endpoint: "https://platform.example.com/login",
            token_endpoint: "https://platform.example.com/token",
            jwks_uri: "https://platform.example.com/keys", tool_jwk: tool_key
          })
          platform = %Ltix.Test.Platform{
            registration: registration,
            deployment: Ltix.Deployment.new!("deployment-001"),
            jwk: Ltix.JWK.generate(key_size: 2048)
          }
          token = Ltix.Test.sign_id_token(%{"sub" => "consumer-user"}, tool_key)
          assert {:ok, %{"sub" => "consumer-user"}} =
                   Ltix.Test.verify_deep_linking_response(platform, token)
          other_token = Ltix.Test.sign_id_token(%{"sub" => "consumer-user"}, platform.jwk)
          assert {:error, :signature_invalid} =
                   Ltix.Test.verify_deep_linking_response(platform, other_token)
          assert {:ok, claims} = Ltix.LaunchClaims.from_json(Ltix.Test.valid_lti_claims(platform))
          assert claims.resource_link.id == "resource-link-001"
          assert {:error, %Ltix.Errors.Security.AlgorithmNotAllowed{algorithm: "HS256"}} =
                   Ltix.JWT.Token.verify("eyJhbGciOiJIUzI1NiJ9.e30.c2ln", registration)
          assert_raise RuntimeError, ~r/HTTP test helpers require Plug/, fn ->
            Ltix.Test.setup_platform!()
          end
          assert_raise RuntimeError, ~r/HTTP test helpers require Plug/, fn ->
            Ltix.Test.stub_post_score()
          end
        end
      end
      """)

      environment = [
        {"MIX_ENV", "prod"},
        {"MIX_BUILD_PATH", Path.join(project, "_build")},
        {"MIX_DEPS_PATH", Path.join(project, "deps")}
      ]

      {output, status} =
        System.cmd("mix", ["do", "compile", "--warnings-as-errors", "+", "run", "verify.exs"],
          cd: project,
          env: environment,
          stderr_to_stdout: true
        )

      assert status == 0, output
    end
  end
end
