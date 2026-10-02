defmodule Ltix.OIDC.CallbackCustomStructsTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchContext
  alias Ltix.OIDC.Callback
  alias Ltix.Test.JWTHelper

  setup do
    {private, public, kid} = JWTHelper.generate_rsa_key_pair()
    jwks = JWTHelper.build_jwks([public])

    custom_reg = %CustomRegistration{
      id: 42,
      tenant_id: 7,
      platform_issuer: "https://platform.example.com",
      oauth_client_id: "tool-client-id",
      oidc_auth_url: "https://platform.example.com/auth",
      platform_jwks_url: "https://platform.example.com/.well-known/jwks.json",
      signing_key: Ltix.JWK.generate()
    }

    custom_dep = %CustomDeployment{
      id: 99,
      registration_id: 42,
      platform_deployment_id: "deployment-001",
      label: "Production"
    }

    {:ok, pid} =
      CustomStorageAdapter.start_link(
        registrations: [custom_reg],
        deployments: [custom_dep]
      )

    CustomStorageAdapter.set_pid(pid)

    {:ok, login} =
      Ltix.handle_login(
        %{
          "iss" => custom_reg.platform_issuer,
          "client_id" => custom_reg.oauth_client_id,
          "login_hint" => "user-hint",
          "target_link_uri" => "https://tool.example.com/launch"
        },
        "https://tool.example.com/launch",
        storage_adapter: CustomStorageAdapter
      )

    nonce = Ltix.Test.extract_nonce(login.redirect_uri)
    state = login.state

    Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("cache-control", "max-age=300")
      |> Req.Test.json(jwks)
    end)

    claims = JWTHelper.valid_lti_claims(%{"nonce" => nonce})
    id_token = JWTHelper.mint_id_token(claims, private, kid: kid)

    params = %{"id_token" => id_token, "state" => state}

    %{
      custom_reg: custom_reg,
      custom_dep: custom_dep,
      state: state,
      params: params
    }
  end

  describe "custom struct integration" do
    test "LaunchContext preserves the user's custom structs", ctx do
      assert {:ok, %LaunchContext{} = launch} =
               Callback.call(
                 ctx.params,
                 ctx.state,
                 CustomStorageAdapter,
                 req_options: [plug: {Req.Test, Ltix.JWT.KeySet}]
               )

      # LaunchContext holds the original custom structs, not Ltix internals
      assert %CustomRegistration{} = launch.registration
      assert launch.registration.id == 42
      assert launch.registration.tenant_id == 7
      assert launch.registration.platform_issuer == "https://platform.example.com"

      assert %CustomDeployment{} = launch.deployment
      assert launch.deployment.id == 99
      assert launch.deployment.label == "Production"
      assert launch.deployment.platform_deployment_id == "deployment-001"

      # Claims still parsed correctly
      assert launch.claims.message_type == "LtiResourceLinkRequest"
      assert launch.claims.deployment_id == "deployment-001"
    end
  end
end
