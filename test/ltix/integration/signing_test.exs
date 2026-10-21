defmodule Ltix.Integration.SigningTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking
  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.Errors.Invalid.InvalidOption
  alias Ltix.Errors.Unknown.StorageError
  alias Ltix.JWK
  alias Ltix.MembershipsService
  alias Ltix.MembershipsService.Endpoint, as: MembershipsServiceEndpoint
  alias Ltix.OAuth
  alias Ltix.OAuth.Client
  alias Ltix.OAuth.ClientCredentials

  @deployment_claim "https://purl.imsglobal.org/spec/lti/claim/deployment_id"

  # Signs with a key the test chooses and sends each signing request to the test process.
  defmodule KeyStorageAdapter do
    @moduledoc false
    @behaviour Ltix.StorageAdapter

    @impl Ltix.StorageAdapter
    defdelegate get_registration(issuer, client_id, opts), to: Ltix.Test.StorageAdapter

    @impl Ltix.StorageAdapter
    defdelegate get_deployment(registration, deployment_id, opts), to: Ltix.Test.StorageAdapter

    @impl Ltix.StorageAdapter
    defdelegate validate_nonce(nonce, registration, expires_at, opts),
      to: Ltix.Test.StorageAdapter

    @impl Ltix.StorageAdapter
    def key_id(registration, _opts) do
      send(self(), {:key_id, registration})
      Process.get(:key_id_result, {:ok, Process.get(:signing_key).kid})
    end

    @impl Ltix.StorageAdapter
    def sign(registration, key_id, message, _opts) do
      send(self(), {:sign, registration, key_id})
      Process.get(:sign_result) || JWK.sign(Process.get(:signing_key), message)
    end
  end

  setup do
    platform = Ltix.Test.setup_platform!()
    signing_key = JWK.generate(key_size: 2048)
    Process.put(:signing_key, signing_key)
    owner = self()

    Req.Test.stub(ClientCredentials, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(owner, {:client_assertion, URI.decode_query(body)["client_assertion"]})

      Req.Test.json(conn, %{
        "access_token" => "token",
        "token_type" => "Bearer",
        "expires_in" => 3600
      })
    end)

    endpoints = %{
      MembershipsService =>
        MembershipsServiceEndpoint.new!("https://platform.example.com/members")
    }

    %{
      platform: platform,
      registration: platform.registration,
      signing_key: signing_key,
      opts: [
        endpoints: endpoints,
        storage_adapter: KeyStorageAdapter,
        req_options: [plug: {Req.Test, :ltix}, retry: false]
      ]
    }
  end

  describe "service authentication" do
    test "signs the client assertion with the storage adapter's key", ctx do
      assert {:ok, %Client{}} = OAuth.authenticate(ctx.registration, ctx.opts)

      registration = ctx.registration
      key_id = ctx.signing_key.kid
      assert_received {:key_id, ^registration}
      assert_received {:sign, ^registration, ^key_id}
      assert_received {:client_assertion, assertion}

      assert %{"alg" => "RS256", "typ" => "JWT", "kid" => ^key_id} = header(assertion)
      assert {:ok, %{"iss" => "tool-client-id"}} = verify(assertion, ctx.signing_key)
    end

    test "sends the registration's audience, or the token endpoint without one", ctx do
      audience = "https://api.platform.example.com/auth/token"

      for {registration, expected} <- [
            {ctx.registration, ctx.registration.token_endpoint},
            {%{ctx.registration | audience: audience}, audience}
          ] do
        assert {:ok, %Client{}} = OAuth.authenticate(registration, ctx.opts)
        assert_received {:client_assertion, assertion}
        assert {:ok, %{"aud" => ^expected}} = verify(assertion, ctx.signing_key)
      end
    end

    # [Core §6.2.1](https://www.imsglobal.org/spec/lti/v1p3/#deployment-id)
    test "sends the deployment ID of a launch, and again on refresh", ctx do
      launch =
        Ltix.Test.build_launch(ctx.platform,
          memberships_endpoint: "https://platform.example.com/members"
        )

      opts =
        Keyword.put(Keyword.delete(ctx.opts, :endpoints), :services, [MembershipsService])

      assert {:ok, %Client{} = client} = OAuth.authenticate(launch, opts)
      assert_received {:client_assertion, assertion}
      assert {:ok, %{@deployment_claim => "deployment-001"}} = verify(assertion, ctx.signing_key)

      assert {:ok, %Client{}} = Client.force_refresh(client)
      assert_received {:client_assertion, assertion}
      assert {:ok, %{@deployment_claim => "deployment-001"}} = verify(assertion, ctx.signing_key)
    end

    test "sends the deployment given with a registration, as a record or an ID", ctx do
      record = %CustomDeployment{id: 7, platform_deployment_id: "deployment-007"}

      for deployment <- [record, "deployment-007"] do
        opts = Keyword.put(ctx.opts, :deployment, deployment)

        assert {:ok, %Client{deployment: ^deployment} = client} =
                 OAuth.authenticate(ctx.registration, opts)

        assert_received {:client_assertion, assertion}

        assert {:ok, %{@deployment_claim => "deployment-007"}} =
                 verify(assertion, ctx.signing_key)

        {:ok, cached} =
          Client.from_access_token(client.token, [registration: ctx.registration] ++ opts)

        assert {:ok, %Client{deployment: ^deployment}} = Client.force_refresh(cached)
        assert_received {:client_assertion, assertion}

        assert {:ok, %{@deployment_claim => "deployment-007"}} =
                 verify(assertion, ctx.signing_key)
      end
    end

    test "sends the deployment given to a service's authenticate function", ctx do
      {endpoints, opts} = Keyword.pop!(ctx.opts, :endpoints)
      opts = [endpoint: endpoints[MembershipsService], deployment: "deployment-007"] ++ opts

      assert {:ok, %Client{}} = MembershipsService.authenticate(ctx.registration, opts)
      assert_received {:client_assertion, assertion}
      assert {:ok, %{@deployment_claim => "deployment-007"}} = verify(assertion, ctx.signing_key)

      launch =
        Ltix.Test.build_launch(ctx.platform,
          memberships_endpoint: "https://platform.example.com/members"
        )

      assert_raise InvalidOption, "Option :deployment is unknown", fn ->
        MembershipsService.authenticate(launch, deployment: "deployment-007")
      end
    end

    test "sends no deployment ID for a registration given without a deployment", ctx do
      assert {:ok, %Client{deployment: nil}} = OAuth.authenticate(ctx.registration, ctx.opts)
      assert_received {:client_assertion, assertion}
      assert {:ok, claims} = verify(assertion, ctx.signing_key)
      refute Map.has_key?(claims, @deployment_claim)
    end

    test "rejects an invalid deployment", ctx do
      assert {:error, %InvalidField{field: :deployment_id}} =
               OAuth.authenticate(ctx.registration, Keyword.put(ctx.opts, :deployment, "é"))

      assert_raise InvalidOption, ~r/Option :deployment is invalid.*Ltix.Deployable/, fn ->
        OAuth.authenticate(ctx.registration, Keyword.put(ctx.opts, :deployment, %{id: 7}))
      end

      {:ok, %Client{token: token}} = OAuth.authenticate(ctx.registration, ctx.opts)
      assert_received {:client_assertion, _assertion}

      assert {:error, %InvalidField{field: :deployment_id}} =
               Client.from_access_token(token,
                 registration: ctx.registration,
                 endpoints: ctx.opts[:endpoints],
                 deployment: "é"
               )

      launch = Ltix.Test.build_launch(ctx.platform)

      assert_raise InvalidOption, "Option :deployment is unknown", fn ->
        OAuth.authenticate(launch, services: [MembershipsService], deployment: "deployment-007")
      end

      refute_received {:client_assertion, _assertion}
    end

    test "passes the adapter the registration record it was called with", ctx do
      record = CustomRegistration.from_registration(ctx.registration, id: 42)

      assert {:ok, %Client{registration: ^record} = client} =
               OAuth.authenticate(record, ctx.opts)

      assert_received {:key_id, ^record}
      assert_received {:sign, ^record, _key_id}

      assert {:ok, %Client{registration: ^record}} = Client.force_refresh(client)
      assert_received {:key_id, ^record}
      assert_received {:sign, ^record, _key_id}
    end

    test "returns StorageError without sending a request when the adapter can't sign", ctx do
      opts = Keyword.put(ctx.opts, :storage_adapter, LaunchStorageAdapter)

      assert {:error, %StorageError{callback: :sign} = error} =
               OAuth.authenticate(ctx.registration, opts)

      assert Exception.message(error) =~ "must implement key_id/2 and sign/4"
      refute_received {:client_assertion, _assertion}
    end

    test "returns StorageError for a key ID or signature the adapter can't provide", ctx do
      for {callback, key, result} <- [
            {:key_id, :key_id_result, {:error, :key_not_found}},
            {:key_id, :key_id_result, {:ok, nil}},
            {:sign, :sign_result, {:error, :signing_service_unavailable}},
            {:sign, :sign_result, {:ok, :not_a_signature}}
          ] do
        Process.put(key, result)

        assert {:error, %StorageError{callback: ^callback, result: ^result}} =
                 OAuth.authenticate(ctx.registration, ctx.opts)

        Process.delete(key)
      end

      refute_received {:client_assertion, _assertion}
    end
  end

  describe "deep linking responses" do
    test "are signed with the storage adapter's key", ctx do
      launch = Ltix.Test.build_launch(ctx.platform, message_type: :deep_linking)
      key_id = ctx.signing_key.kid
      registration = launch.registration

      assert {:ok, response} =
               DeepLinking.build_response(launch, [], storage_adapter: KeyStorageAdapter)

      assert_received {:key_id, ^registration}

      assert %{"alg" => "RS256", "typ" => "JWT", "kid" => ^key_id} = header(response.jwt)

      assert {:ok, %{"aud" => "https://platform.example.com"}} =
               verify(response.jwt, ctx.signing_key)
    end

    test "return StorageError when the adapter can't sign", ctx do
      launch = Ltix.Test.build_launch(ctx.platform, message_type: :deep_linking)

      assert {:error, %StorageError{callback: :sign}} =
               DeepLinking.build_response(launch, [], storage_adapter: LaunchStorageAdapter)
    end
  end

  defp header(jwt) do
    %JOSE.JWS{alg: {_module, algorithm}, fields: fields} = JOSE.JWT.peek_protected(jwt)
    Map.put(fields, "alg", Atom.to_string(algorithm))
  end

  defp verify(jwt, %JWK{} = jwk) do
    platform = %Ltix.Test.Platform{registration: nil, deployment: nil, jwk: jwk, tool_jwk: jwk}
    Ltix.Test.verify_deep_linking_response(platform, jwt)
  end
end
