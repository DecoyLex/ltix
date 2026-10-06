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
      defmodule ConsumerStorage do
        @moduledoc false
        @behaviour Ltix.StorageAdapter
        use Agent

        def start_link(_opts) do
          Agent.start_link(fn -> %{registrations: %{}, deployments: %{}, used_nonces: MapSet.new()} end,
            name: __MODULE__)
        end

        def create_registration(registration) do
          key = {registration.issuer, registration.client_id}
          Agent.update(__MODULE__, &%{&1 | registrations: Map.put(&1.registrations, key, registration)})
          registration
        end

        def create_deployment(deployment, registration) do
          key = {registration.issuer, registration.client_id, deployment.deployment_id}
          Agent.update(__MODULE__, &%{&1 | deployments: Map.put(&1.deployments, key, deployment)})
          deployment
        end

        @impl Ltix.StorageAdapter
        def get_registration(issuer, nil) do
          Agent.get(__MODULE__, fn state ->
            case Enum.find(Map.values(state.registrations), &(&1.issuer == issuer)) do
              nil -> {:error, :not_found}
              registration -> {:ok, registration}
            end
          end)
        end

        def get_registration(issuer, client_id) do
          result = Agent.get(__MODULE__, &Map.fetch(&1.registrations, {issuer, client_id}))
          case result do
            :error -> {:error, :not_found}
            result -> result
          end
        end

        @impl Ltix.StorageAdapter
        def get_deployment(registration, deployment_id) do
          key = {registration.issuer, registration.client_id, deployment_id}
          Agent.get_and_update(__MODULE__, fn state ->
            case Map.fetch(state.deployments, key) do
              {:ok, _} = found -> {found, state}
              :error -> create_missing_deployment(state, key, deployment_id)
            end
          end)
        end

        defp create_missing_deployment(%{auto_create: true} = state, key, deployment_id) do
          deployment = Ltix.Deployment.new!(deployment_id)
          {{:ok, deployment}, %{state | deployments: Map.put(state.deployments, key, deployment)}}
        end

        defp create_missing_deployment(state, _key, _deployment_id) do
          {{:error, :not_found}, state}
        end

        @impl Ltix.StorageAdapter
        def validate_nonce(nonce, _registration, _expires_at) do
          Agent.get_and_update(__MODULE__, fn state ->
            if MapSet.member?(state.used_nonces, nonce) do
              {{:error, :nonce_already_used}, state}
            else
              {:ok, %{state | used_nonces: MapSet.put(state.used_nonces, nonce)}}
            end
          end)
        end
      end

      defmodule ConsumerUnscopedStorage do
        @moduledoc false
        @behaviour Ltix.StorageAdapter
        @impl Ltix.StorageAdapter
        defdelegate get_registration(issuer, client_id), to: ConsumerStorage
        @impl Ltix.StorageAdapter
        defdelegate validate_nonce(nonce, registration, expires_at), to: ConsumerStorage

        @impl Ltix.StorageAdapter
        def get_deployment(registration, deployment_id) do
          Agent.get(ConsumerStorage, fn state ->
            found = Enum.find(state.deployments, fn {{_issuer, client_id, identifier}, _} ->
              client_id == registration.client_id and identifier == deployment_id
            end)
            case found do
              nil -> {:error, :not_found}
              {_key, deployment} -> {:ok, deployment}
            end
          end)
        end
      end

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
          assert {:error, %Ltix.Errors.Security.SignatureInvalid{}} =
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
          start_supervised!(ConsumerStorage)
          assert :ok = Ltix.Test.assert_storage_adapter!(ConsumerStorage,
            registration: &ConsumerStorage.create_registration/1,
            deployment: &ConsumerStorage.create_deployment/2)
          assert_raise ExUnit.AssertionError, ~r/get_deployment\\/2.*scoped.*issuer/s, fn ->
            Ltix.Test.assert_storage_adapter!(ConsumerUnscopedStorage,
              registration: &ConsumerStorage.create_registration/1,
              deployment: &ConsumerStorage.create_deployment/2)
          end
          Agent.update(ConsumerStorage, &Map.put(&1, :auto_create, true))
          assert :ok = Ltix.Test.assert_storage_adapter!(ConsumerStorage,
            registration: &ConsumerStorage.create_registration/1,
            deployment: &ConsumerStorage.create_deployment/2,
            auto_create_deployments: true)
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
