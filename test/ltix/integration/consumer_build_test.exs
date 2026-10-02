defmodule Ltix.Integration.ConsumerBuildTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 120_000

  test "consumers compile and use core helpers without optional dependencies" do
    library = File.cwd!()
    project = Path.join(System.tmp_dir!(), "ltix-consumer-#{System.unique_integer([:positive])}")
    File.mkdir_p!(project)
    on_exit(fn -> File.rm_rf!(project) end)

    File.write!(Path.join(project, "mix.exs"), """
    defmodule Consumer.MixProject do
      use Mix.Project
      def project do
        [app: :consumer, version: "0.1.0",
         deps: [{:ltix, path: #{inspect(library)}}, {:jose, "~> 1.11"}]]
      end
      def application, do: [extra_applications: [:logger]]
    end
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
        {private_key, _public_key, kid} = Ltix.Test.generate_rsa_key_pair()
        {_type, pem} = JOSE.JWK.to_pem(private_key)
        {:ok, tool_key} = Ltix.JWK.new(private_key_pem: pem, kid: kid)
        {:ok, registration} = Ltix.Registration.new(%{
          issuer: "https://platform.example.com", client_id: "consumer",
          auth_endpoint: "https://platform.example.com/login",
          token_endpoint: "https://platform.example.com/token",
          jwks_uri: "https://platform.example.com/keys", tool_jwk: tool_key
        })
        platform = %Ltix.Test.Platform{registration: registration}
        token = Ltix.Test.mint_id_token(%{"sub" => "consumer-user"}, private_key, kid: kid)
        assert {:ok, %{"sub" => "consumer-user"}} =
                 Ltix.Test.verify_deep_linking_response(platform, token)
        {other_key, _public_key, _kid} = Ltix.Test.generate_rsa_key_pair()
        other_token = Ltix.Test.mint_id_token(%{"sub" => "consumer-user"}, other_key)
        assert {:error, :signature_invalid} =
                 Ltix.Test.verify_deep_linking_response(platform, other_token)
        assert {:ok, claims} = Ltix.LaunchClaims.from_json(Ltix.Test.valid_lti_claims())
        assert claims.resource_link.id == "resource-link-001"
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
