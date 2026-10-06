defmodule Ltix.OIDC.CallbackCustomStructsTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchContext
  alias Ltix.OIDC.Callback

  setup do
    platform_jwk = Ltix.JWK.generate()
    jwks = Ltix.JWK.to_jwks(platform_jwk)

    custom_reg = %CustomRegistration{
      id: 42,
      tenant_id: 7,
      platform_issuer: "https://platform.example.com",
      oauth_client_id: "tool-client-id",
      oidc_auth_url: "https://platform.example.com/auth",
      platform_jwks_url: "https://platform.example.com/.well-known/jwks.json"
    }

    custom_dep = %CustomDeployment{
      id: 99,
      registration_id: 42,
      platform_deployment_id: "deployment-001",
      label: "Production"
    }

    platform = %Ltix.Test.Platform{
      registration: custom_reg,
      deployment: custom_dep,
      jwk: platform_jwk
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

    claims = Ltix.Test.valid_lti_claims(platform, %{"nonce" => nonce})
    id_token = Ltix.Test.sign_id_token(claims, platform_jwk)

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

      # LaunchContext has the original custom structs
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
