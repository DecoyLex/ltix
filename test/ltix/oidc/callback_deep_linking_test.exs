defmodule Ltix.OIDC.CallbackDeepLinkingTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.LaunchClaims
  alias Ltix.LaunchClaims.DeepLinkingSettings
  alias Ltix.LaunchContext
  alias Ltix.OIDC.Callback
  alias Ltix.Test.JWTHelper
  alias Ltix.Test.StorageAdapter

  @lti "https://purl.imsglobal.org/spec/lti/claim/"
  @dl_settings_key "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings"

  setup do
    {private, public, kid} = JWTHelper.generate_rsa_key_pair()
    jwks = JWTHelper.build_jwks([public])

    {:ok, registration} =
      Ltix.Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri: "https://platform.example.com/.well-known/jwks.json",
        tool_jwk: Ltix.JWK.generate()
      })

    {:ok, deployment} = Ltix.Deployment.new("deployment-001")

    nonce = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    {:ok, pid} =
      StorageAdapter.start_link(
        registrations: [registration],
        deployments: [deployment]
      )

    StorageAdapter.set_pid(pid)
    StorageAdapter.store_nonce(nonce, registration)

    Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("cache-control", "max-age=300")
      |> Req.Test.json(jwks)
    end)

    claims = deep_linking_claims(%{"nonce" => nonce})
    id_token = JWTHelper.mint_id_token(claims, private, kid: kid)
    params = %{"id_token" => id_token, "state" => state}

    %{
      private: private,
      kid: kid,
      nonce: nonce,
      state: state,
      params: params,
      claims: claims
    }
  end

  # [DL §4.4](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-request-message)
  describe "happy path" do
    test "deep linking launch returns LaunchContext", ctx do
      assert {:ok, %LaunchContext{} = launch} =
               Callback.call(ctx.params, ctx.state, StorageAdapter, req_options: req_options())

      assert launch.claims.message_type == "LtiDeepLinkingRequest"
      assert launch.claims.version == "1.3.0"
      assert launch.claims.deployment_id == "deployment-001"
      assert launch.claims.target_link_uri == "https://tool.example.com/launch"
    end

    # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
    test "deep_linking_settings is parsed into struct", ctx do
      assert {:ok, %LaunchContext{} = launch} =
               Callback.call(ctx.params, ctx.state, StorageAdapter, req_options: req_options())

      assert %DeepLinkingSettings{} = launch.claims.deep_linking_settings

      assert launch.claims.deep_linking_settings.deep_link_return_url ==
               "https://platform.example.com/deep_links"

      assert launch.claims.deep_linking_settings.accept_types == ["ltiResourceLink", "link"]

      assert launch.claims.deep_linking_settings.accept_presentation_document_targets == [
               "iframe",
               "window"
             ]

      assert launch.claims.deep_linking_settings.accept_multiple == true
    end

    test "succeeds without resource_link claim", ctx do
      refute Map.has_key?(ctx.claims, @lti <> "resource_link")

      assert {:ok, %LaunchContext{} = launch} =
               Callback.call(ctx.params, ctx.state, StorageAdapter, req_options: req_options())

      assert launch.claims.resource_link == nil
    end

    # [DL §4.4.9](https://www.imsglobal.org/spec/lti-dl/v2p0/#role)
    test "succeeds without roles claim", ctx do
      claims = Map.delete(ctx.claims, @lti <> "roles")
      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{}} =
               Callback.call(params, ctx.state, StorageAdapter, req_options: req_options())
    end

    # [DL §4.4.5](https://www.imsglobal.org/spec/lti-dl/v2p0/#user)
    test "succeeds without sub claim", ctx do
      claims = Map.delete(ctx.claims, "sub")
      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} =
               Callback.call(params, ctx.state, StorageAdapter, req_options: req_options())

      assert launch.claims.subject == nil
    end

    test "succeeds with roles and sub present", ctx do
      claims =
        ctx.claims
        |> Map.put("sub", "user-12345")
        |> Map.put(@lti <> "roles", [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"
        ])

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} =
               Callback.call(params, ctx.state, StorageAdapter, req_options: req_options())

      assert launch.claims.subject == "user-12345"
      assert LaunchClaims.Role.instructor?(launch.claims.roles)
    end
  end

  # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
  describe "deep_linking_settings validation" do
    test "missing deep_linking_settings returns MissingClaim error", ctx do
      claims = Map.delete(ctx.claims, @dl_settings_key)
      params = mint_and_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "deep_linking_settings"}} =
               Callback.call(params, ctx.state, StorageAdapter, req_options: req_options())
    end

    test "missing deep_link_return_url in settings returns error", ctx do
      settings = Map.delete(ctx.claims[@dl_settings_key], "deep_link_return_url")
      claims = Map.put(ctx.claims, @dl_settings_key, settings)
      params = mint_and_params(claims, ctx)

      assert {:error, error} =
               Callback.call(params, ctx.state, StorageAdapter, req_options: req_options())

      assert Exception.message(error) =~ "deep_linking_settings.deep_link_return_url"
    end

    test "missing accept_types in settings returns error", ctx do
      settings = Map.delete(ctx.claims[@dl_settings_key], "accept_types")
      claims = Map.put(ctx.claims, @dl_settings_key, settings)
      params = mint_and_params(claims, ctx)

      assert {:error, error} =
               Callback.call(params, ctx.state, StorageAdapter, req_options: req_options())

      assert Exception.message(error) =~ "deep_linking_settings.accept_types"
    end

    test "missing accept_presentation_document_targets in settings returns error", ctx do
      settings =
        Map.delete(ctx.claims[@dl_settings_key], "accept_presentation_document_targets")

      claims = Map.put(ctx.claims, @dl_settings_key, settings)
      params = mint_and_params(claims, ctx)

      assert {:error, error} =
               Callback.call(params, ctx.state, StorageAdapter, req_options: req_options())

      assert Exception.message(error) =~
               "deep_linking_settings.accept_presentation_document_targets"
    end
  end

  describe "message type validation" do
    test "resource link launch without resource_link still fails", ctx do
      claims =
        ctx.claims
        |> Map.put(@lti <> "message_type", "LtiResourceLinkRequest")
        |> Map.put(@lti <> "roles", [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"
        ])

      params = mint_and_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "resource_link"}} =
               Callback.call(params, ctx.state, StorageAdapter, req_options: req_options())
    end

    test "unrecognized message type returns InvalidClaim error", ctx do
      claims = Map.put(ctx.claims, @lti <> "message_type", "LtiUnknownRequest")
      params = mint_and_params(claims, ctx)

      assert {:error, %InvalidClaim{claim: "message_type", value: "LtiUnknownRequest"}} =
               Callback.call(params, ctx.state, StorageAdapter, req_options: req_options())
    end
  end

  describe "build_launch_context/2 with deep linking" do
    test "produces a DL context with settings" do
      platform = Ltix.Test.setup_platform!()

      context =
        Ltix.Test.build_launch_context(platform,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["ltiResourceLink"]}
        )

      assert context.claims.message_type == "LtiDeepLinkingRequest"
      assert context.claims.resource_link == nil
      assert %DeepLinkingSettings{} = context.claims.deep_linking_settings
      assert context.claims.deep_linking_settings.accept_types == ["ltiResourceLink"]

      assert context.claims.deep_linking_settings.deep_link_return_url ==
               "https://platform.example.com/deep_links"
    end

    test "uses default settings when none provided" do
      platform = Ltix.Test.setup_platform!()
      context = Ltix.Test.build_launch_context(platform, message_type: :deep_linking)

      assert context.claims.deep_linking_settings.accept_types ==
               ["ltiResourceLink", "link", "file", "html", "image"]

      assert context.claims.deep_linking_settings.accept_multiple == true
    end

    test "subject defaults to nil for DL context" do
      platform = Ltix.Test.setup_platform!()
      context = Ltix.Test.build_launch_context(platform, message_type: :deep_linking)

      assert context.claims.subject == nil
    end

    test "subject can be explicitly set for DL context" do
      platform = Ltix.Test.setup_platform!()

      context =
        Ltix.Test.build_launch_context(platform,
          message_type: :deep_linking,
          subject: "user-42"
        )

      assert context.claims.subject == "user-42"
    end
  end

  # -- Helpers --

  defp deep_linking_claims(overrides) do
    now = System.system_time(:second)

    base = %{
      "iss" => "https://platform.example.com",
      "sub" => "user-12345",
      "aud" => "tool-client-id",
      "exp" => now + 3600,
      "iat" => now,
      "nonce" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false),
      (@lti <> "message_type") => "LtiDeepLinkingRequest",
      (@lti <> "version") => "1.3.0",
      (@lti <> "deployment_id") => "deployment-001",
      (@lti <> "target_link_uri") => "https://tool.example.com/launch",
      (@lti <> "roles") => [
        "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"
      ],
      @dl_settings_key => %{
        "deep_link_return_url" => "https://platform.example.com/deep_links",
        "accept_types" => ["ltiResourceLink", "link"],
        "accept_presentation_document_targets" => ["iframe", "window"],
        "accept_multiple" => true
      }
    }

    Map.merge(base, overrides)
  end

  defp mint_and_params(claims, ctx) do
    id_token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)
    %{"id_token" => id_token, "state" => ctx.state}
  end

  defp req_options, do: [plug: {Req.Test, Ltix.JWT.KeySet}]
end
