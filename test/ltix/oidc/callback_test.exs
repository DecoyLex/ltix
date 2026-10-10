defmodule Ltix.OIDC.CallbackTest do
  use ExUnit.Case, async: true

  alias Ltix.Deployment
  alias Ltix.Errors.Invalid.DeploymentNotFound
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.Errors.Invalid.RegistrationNotFound
  alias Ltix.Errors.Security
  alias Ltix.OIDC.Callback
  alias Ltix.Registration
  alias Ltix.Test.StorageAdapter

  @lti "https://purl.imsglobal.org/spec/lti/claim/"

  setup do
    platform_jwk = Ltix.JWK.generate()
    jwks = Ltix.JWK.to_jwks(platform_jwk)

    {:ok, registration} =
      Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri:
          "https://platform.example.com/.well-known/jwks-#{System.unique_integer([:positive])}.json"
      })

    {:ok, deployment} = Deployment.new("deployment-001")

    platform = %Ltix.Test.Platform{
      registration: registration,
      deployment: deployment,
      jwk: platform_jwk
    }

    {:ok, pid} =
      StorageAdapter.start_link(platforms: [platform])

    StorageAdapter.set_pid(pid)

    {:ok, login} =
      Ltix.handle_login(
        %{
          "iss" => registration.issuer,
          "client_id" => registration.client_id,
          "login_hint" => "user-hint",
          "target_link_uri" => "https://tool.example.com/launch"
        },
        "https://tool.example.com/launch",
        storage_adapter: StorageAdapter
      )

    nonce = Ltix.Test.extract_nonce(login.redirect_uri)
    state = login.state

    stub_jwks(jwks)

    claims = Ltix.Test.valid_lti_claims(platform, %{"nonce" => nonce})

    %{
      platform: platform,
      platform_jwk: platform_jwk,
      nonce: nonce,
      state: state,
      claims: claims
    }
  end

  # [Sec §5.1.1.5](https://www.imsglobal.org/spec/security/v1p0/#authentication-error-response)
  describe "error responses [Sec §5.1.1.5]" do
    test "platform error response returns AuthenticationFailed", ctx do
      params = %{
        "error" => "login_required",
        "error_description" => "User session expired",
        "state" => ctx.state
      }

      assert {:error,
              %Security.AuthenticationFailed{
                error: "login_required",
                error_description: "User session expired"
              }} =
               Callback.call(params, ctx.state, StorageAdapter, req_options: req_options())
    end
  end

  describe "registration lookup" do
    test "unknown issuer returns RegistrationNotFound", ctx do
      claims =
        Ltix.Test.valid_lti_claims(ctx.platform, %{
          "iss" => "https://unknown.example.com",
          "nonce" => ctx.nonce
        })

      id_token = Ltix.Test.sign_id_token(claims, ctx.platform_jwk)
      params = %{"id_token" => id_token, "state" => ctx.state}

      assert {:error, %RegistrationNotFound{issuer: "https://unknown.example.com"}} =
               Callback.call(params, ctx.state, StorageAdapter, req_options: req_options())
    end
  end

  # [Core §5.3](https://www.imsglobal.org/spec/lti/v1p3/#required-message-claims)
  describe "LTI claim validation [Cert §6.1.1]" do
    test "missing target_link_uri", ctx do
      claims = Map.delete(ctx.claims, @lti <> "target_link_uri")
      id_token = mint_and_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "target_link_uri"}} =
               Callback.call(id_token, ctx.state, StorageAdapter, req_options: req_options())
    end

    test "missing resource_link", ctx do
      claims = Map.delete(ctx.claims, @lti <> "resource_link")
      id_token = mint_and_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "resource_link"}} =
               Callback.call(id_token, ctx.state, StorageAdapter, req_options: req_options())
    end

    # Message type injection. Attacker sends a fabricated message type
    # hoping to bypass validation or trigger unexpected code paths.
    test "rejects fabricated message_type", ctx do
      claims = put_lti_claim(ctx.claims, "message_type", "LtiAdminRequest")
      id_token = mint_and_params(claims, ctx)

      assert {:error, %InvalidClaim{claim: "message_type"}} =
               Callback.call(id_token, ctx.state, StorageAdapter, req_options: req_options())
    end
  end

  # [Core §3.1.3](https://www.imsglobal.org/spec/lti/v1p3/#tool-deployment)
  describe "deployment validation [Core §3.1.3]" do
    test "unknown deployment_id returns DeploymentNotFound", ctx do
      claims = put_lti_claim(ctx.claims, "deployment_id", "unknown-deployment")
      id_token = mint_and_params(claims, ctx)

      assert {:error, %DeploymentNotFound{deployment_id: "unknown-deployment"}} =
               Callback.call(id_token, ctx.state, StorageAdapter, req_options: req_options())
    end
  end

  # -- Helpers --

  defp mint_and_params(claims, ctx) do
    id_token = Ltix.Test.sign_id_token(claims, ctx.platform_jwk)
    %{"id_token" => id_token, "state" => ctx.state}
  end

  defp stub_jwks(jwks) do
    Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("cache-control", "max-age=300")
      |> Req.Test.json(jwks)
    end)
  end

  defp req_options, do: [plug: {Req.Test, Ltix.JWT.KeySet}]

  defp put_lti_claim(claims, key, value) do
    Map.put(claims, @lti <> key, value)
  end
end
