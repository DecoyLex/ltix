defmodule Ltix.Launch.CallbackTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.DeploymentNotFound
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.Errors.Invalid.RegistrationNotFound
  alias Ltix.Errors.Security
  alias Ltix.Test.StorageAdapter

  @lti "https://purl.imsglobal.org/spec/lti/claim/"

  setup do
    platform = Ltix.Test.setup_platform!()
    StorageAdapter.set_pid(start_supervised!({StorageAdapter, platforms: [platform]}))
    login = LaunchFlow.login!(platform)

    %{
      platform: platform,
      state: login.state,
      claims: Ltix.Test.valid_lti_claims(platform, %{"nonce" => LaunchFlow.nonce(login)})
    }
  end

  # Signs `claims` with the platform's key and handles the callback.
  defp callback(claims, ctx), do: LaunchFlow.callback_with_claims(ctx.platform, claims, ctx.state)

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
              }} = LaunchFlow.callback(params, ctx.state)
    end
  end

  describe "registration lookup" do
    test "unknown issuer returns RegistrationNotFound", ctx do
      assert {:error, %RegistrationNotFound{issuer: "https://unknown.example.com"}} =
               callback(Map.put(ctx.claims, "iss", "https://unknown.example.com"), ctx)
    end
  end

  # [Core §5.3](https://www.imsglobal.org/spec/lti/v1p3/#required-message-claims)
  describe "LTI claim validation [Cert §6.1.1]" do
    test "missing target_link_uri", ctx do
      assert {:error, %MissingClaim{claim: "target_link_uri"}} =
               callback(Map.delete(ctx.claims, @lti <> "target_link_uri"), ctx)
    end

    test "missing resource_link", ctx do
      assert {:error, %MissingClaim{claim: "resource_link"}} =
               callback(Map.delete(ctx.claims, @lti <> "resource_link"), ctx)
    end

    # Message type injection. Attacker sends a fabricated message type
    # hoping to bypass validation or trigger unexpected code paths.
    test "rejects fabricated message_type", ctx do
      assert {:error, %InvalidClaim{claim: "message_type"}} =
               callback(Map.put(ctx.claims, @lti <> "message_type", "LtiAdminRequest"), ctx)
    end
  end

  # [Core §3.1.3](https://www.imsglobal.org/spec/lti/v1p3/#tool-deployment)
  describe "deployment validation [Core §3.1.3]" do
    test "unknown deployment_id returns DeploymentNotFound", ctx do
      assert {:error, %DeploymentNotFound{deployment_id: "unknown-deployment"}} =
               callback(Map.put(ctx.claims, @lti <> "deployment_id", "unknown-deployment"), ctx)
    end
  end
end
