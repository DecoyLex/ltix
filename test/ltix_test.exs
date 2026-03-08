defmodule LtixTest do
  use ExUnit.Case

  alias Ltix.{Deployment, LaunchContext, Registration}
  alias Ltix.Errors.Invalid.MissingParameter
  alias Ltix.Test.{JWTHelper, TestStorageAdapter}

  @redirect_uri "https://tool.example.com/callback"

  setup do
    {private, public, kid} = JWTHelper.generate_rsa_key_pair()
    jwks = JWTHelper.build_jwks([public])

    {:ok, registration} =
      Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri: "https://platform.example.com/.well-known/jwks.json"
      })

    {:ok, deployment} = Deployment.new("deployment-001")

    {:ok, pid} =
      TestStorageAdapter.start_link(
        registrations: [registration],
        deployments: [deployment]
      )

    TestStorageAdapter.set_pid(pid)

    nonce = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    TestStorageAdapter.store_nonce(nonce, registration)

    Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("cache-control", "max-age=300")
      |> Req.Test.json(jwks)
    end)

    claims = JWTHelper.valid_lti_claims(%{"nonce" => nonce})
    id_token = JWTHelper.mint_id_token(claims, private, kid: kid)

    on_exit(fn ->
      Application.delete_env(:ltix, :storage_adapter)
      Application.delete_env(:ltix, :allow_anonymous)
    end)

    %{
      registration: registration,
      deployment: deployment,
      private: private,
      kid: kid,
      nonce: nonce,
      state: state,
      id_token: id_token,
      claims: claims
    }
  end

  describe "handle_login/3" do
    # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
    # [Sec §5.1.1.2](https://www.imsglobal.org/spec/security/v1p0/#step-2-authentication-request)
    test "returns redirect_uri and state" do
      assert {:ok, result} =
               Ltix.handle_login(login_params(), @redirect_uri,
                 storage_adapter: TestStorageAdapter
               )

      uri = URI.parse(result.redirect_uri)
      assert uri.host == "platform.example.com"

      query = URI.decode_query(uri.query)
      assert query["scope"] == "openid"
      assert query["response_type"] == "id_token"
      assert query["client_id"] == "tool-client-id"
      assert query["redirect_uri"] == @redirect_uri
      assert query["state"] == result.state
    end

    test "reads storage_adapter from application config" do
      Application.put_env(:ltix, :storage_adapter, TestStorageAdapter)

      assert {:ok, %{redirect_uri: redirect_uri, state: state}} =
               Ltix.handle_login(login_params(), @redirect_uri)

      assert is_binary(redirect_uri)
      assert is_binary(state)
    end

    test "opts override application config" do
      Application.put_env(:ltix, :storage_adapter, TestStorageAdapter)

      assert {:ok, result} =
               Ltix.handle_login(login_params(), "https://override.example.com/callback",
                 storage_adapter: TestStorageAdapter
               )

      query = URI.parse(result.redirect_uri).query |> URI.decode_query()
      assert query["redirect_uri"] == "https://override.example.com/callback"
    end

    test "raises ArgumentError when storage_adapter is not configured" do
      assert_raise ArgumentError, ~r/storage_adapter/, fn ->
        Ltix.handle_login(login_params(), @redirect_uri)
      end
    end

    test "delegates errors from underlying modules" do
      params = Map.delete(login_params(), "iss")

      assert {:error, %MissingParameter{parameter: "iss"}} =
               Ltix.handle_login(params, @redirect_uri, storage_adapter: TestStorageAdapter)
    end
  end

  describe "handle_callback/3" do
    # [Sec §5.1.1.3](https://www.imsglobal.org/spec/security/v1p0/#step-3-authentication-response)
    test "returns LaunchContext", ctx do
      params = %{"id_token" => ctx.id_token, "state" => ctx.state}

      assert {:ok, %LaunchContext{} = launch} =
               Ltix.handle_callback(params, ctx.state,
                 storage_adapter: TestStorageAdapter,
                 req_options: req_options()
               )

      assert launch.registration == ctx.registration
      assert launch.deployment == ctx.deployment
      assert launch.claims.message_type == "LtiResourceLinkRequest"
    end

    test "reads storage_adapter from application config", ctx do
      Application.put_env(:ltix, :storage_adapter, TestStorageAdapter)

      params = %{"id_token" => ctx.id_token, "state" => ctx.state}

      assert {:ok, %LaunchContext{}} =
               Ltix.handle_callback(params, ctx.state, req_options: req_options())
    end

    test "reads allow_anonymous from application config", ctx do
      Application.put_env(:ltix, :storage_adapter, TestStorageAdapter)
      Application.put_env(:ltix, :allow_anonymous, true)

      claims = Map.delete(ctx.claims, "sub")
      id_token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)
      params = %{"id_token" => id_token, "state" => ctx.state}

      assert {:ok, %LaunchContext{} = launch} =
               Ltix.handle_callback(params, ctx.state, req_options: req_options())

      assert launch.claims.subject == nil
    end

    test "opts override application config", ctx do
      Application.put_env(:ltix, :storage_adapter, TestStorageAdapter)
      Application.put_env(:ltix, :allow_anonymous, false)

      claims = Map.delete(ctx.claims, "sub")
      id_token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)
      params = %{"id_token" => id_token, "state" => ctx.state}

      # Override allow_anonymous to true via opts
      assert {:ok, %LaunchContext{}} =
               Ltix.handle_callback(params, ctx.state,
                 allow_anonymous: true,
                 req_options: req_options()
               )
    end

    test "raises ArgumentError when storage_adapter is not configured", ctx do
      params = %{"id_token" => ctx.id_token, "state" => ctx.state}

      assert_raise ArgumentError, ~r/storage_adapter/, fn ->
        Ltix.handle_callback(params, ctx.state, req_options: req_options())
      end
    end

    test "delegates errors from underlying modules" do
      params = %{"state" => "some-state"}

      assert {:error, %MissingParameter{parameter: "id_token"}} =
               Ltix.handle_callback(params, "some-state",
                 storage_adapter: TestStorageAdapter,
                 req_options: req_options()
               )
    end
  end

  defp login_params do
    %{
      "iss" => "https://platform.example.com",
      "login_hint" => "user-hint-123",
      "target_link_uri" => "https://tool.example.com/launch"
    }
  end

  defp req_options, do: [plug: {Req.Test, Ltix.JWT.KeySet}]
end
