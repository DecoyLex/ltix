defmodule Ltix.Integration.FullLaunchTest do
  use ExUnit.Case, async: true

  alias Ltix.Deployment
  alias Ltix.LaunchContext
  alias Ltix.Registration
  alias Ltix.Test.StorageAdapter

  @redirect_uri "https://tool.example.com/launch"

  setup do
    platform_jwk = Ltix.JWK.generate()
    jwks = Ltix.JWK.to_jwks(platform_jwk)

    {:ok, registration} =
      Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri: "https://platform.example.com/.well-known/#{platform_jwk.kid}/jwks.json"
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

    Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("cache-control", "max-age=300")
      |> Req.Test.json(jwks)
    end)

    %{
      platform: platform,
      platform_jwk: platform_jwk,
      registration: registration,
      deployment: deployment
    }
  end

  # [Sec §5.1.1](https://www.imsglobal.org/spec/security/v1p0/#openid_connect_launch_flow)
  describe "complete launch flow [Sec §5.1.1]" do
    test "login → callback → LaunchContext", ctx do
      {:ok, login_result} = do_login()

      nonce = extract_nonce(login_result.redirect_uri)
      claims = Ltix.Test.valid_lti_claims(ctx.platform, %{"nonce" => nonce})
      id_token = Ltix.Test.sign_id_token(claims, ctx.platform_jwk)

      assert {:ok, %LaunchContext{} = launch} =
               Ltix.handle_callback(
                 %{"id_token" => id_token, "state" => login_result.state},
                 login_result.state,
                 storage_adapter: StorageAdapter,
                 req_options: req_options()
               )

      assert launch.registration == ctx.registration
      assert launch.deployment == ctx.deployment
      assert launch.claims.message_type == "LtiResourceLinkRequest"
      assert launch.claims.version == "1.3.0"
      assert launch.claims.target_link_uri == "https://tool.example.com/launch"
      assert launch.claims.subject == "user-12345"
    end
  end

  # [Core §5.3.6.1](https://www.imsglobal.org/spec/lti/v1p3/#anonymous-launch-case)
  describe "full flow anonymous [Core §5.3.6.1]" do
    test "anonymous launch with allow_anonymous", ctx do
      {:ok, login_result} = do_login()

      nonce = extract_nonce(login_result.redirect_uri)

      claims = Map.delete(Ltix.Test.valid_lti_claims(ctx.platform, %{"nonce" => nonce}), "sub")

      id_token = Ltix.Test.sign_id_token(claims, ctx.platform_jwk)

      assert {:ok, %LaunchContext{} = launch} =
               Ltix.handle_callback(
                 %{"id_token" => id_token, "state" => login_result.state},
                 login_result.state,
                 storage_adapter: StorageAdapter,
                 allow_anonymous: true,
                 req_options: req_options()
               )

      assert launch.claims.subject == nil
    end
  end

  # -- Helpers --

  defp do_login do
    Ltix.handle_login(
      %{
        "iss" => "https://platform.example.com",
        "login_hint" => "user-hint-123",
        "target_link_uri" => "https://tool.example.com/launch"
      },
      @redirect_uri,
      storage_adapter: StorageAdapter
    )
  end

  defp extract_nonce(redirect_uri) do
    redirect_uri
    |> URI.parse()
    |> Map.get(:query)
    |> URI.decode_query()
    |> Map.fetch!("nonce")
  end

  defp req_options, do: [plug: {Req.Test, Ltix.JWT.KeySet}]
end
