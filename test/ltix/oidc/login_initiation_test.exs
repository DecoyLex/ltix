defmodule Ltix.OIDC.LoginInitiationTest do
  use ExUnit.Case, async: true

  alias Ltix.OIDC.LoginInitiation
  alias Ltix.Test.StorageAdapter

  setup do
    {:ok, registration} =
      Ltix.Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/authorize",
        jwks_uri: "https://platform.example.com/.well-known/jwks.json"
      })

    {:ok, pid} = StorageAdapter.start_link(registrations: [registration])
    StorageAdapter.set_pid(pid)

    params = %{
      "iss" => "https://platform.example.com",
      "login_hint" => "user-hint-123",
      "target_link_uri" => "https://tool.example.com/launch"
    }

    redirect_uri = "https://tool.example.com/callback"

    %{params: params, redirect_uri: redirect_uri}
  end

  describe "call/3" do
    # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
    test "valid login initiation returns redirect_uri and state", %{
      params: params,
      redirect_uri: redirect_uri
    } do
      assert {:ok, result} = LoginInitiation.call(params, StorageAdapter, redirect_uri, [])

      uri = URI.parse(result.redirect_uri)
      assert uri.host == "platform.example.com"
      assert uri.path == "/authorize"

      query = URI.decode_query(uri.query)
      assert query["scope"] == "openid"
      assert query["response_type"] == "id_token"
      assert query["client_id"] == "tool-client-id"
      assert query["redirect_uri"] == "https://tool.example.com/callback"
      assert query["login_hint"] == "user-hint-123"
      assert query["state"] == result.state
      assert query["response_mode"] == "form_post"
      assert byte_size(query["nonce"]) > 0
      assert query["prompt"] == "none"
    end

    test "state and nonce are cryptographically random", %{
      params: params,
      redirect_uri: redirect_uri
    } do
      assert {:ok, result1} = LoginInitiation.call(params, StorageAdapter, redirect_uri, [])
      assert {:ok, result2} = LoginInitiation.call(params, StorageAdapter, redirect_uri, [])

      refute result1.state == result2.state

      q1 = URI.decode_query(URI.parse(result1.redirect_uri).query)
      q2 = URI.decode_query(URI.parse(result2.redirect_uri).query)

      refute q1["nonce"] == q2["nonce"]
    end
  end
end
