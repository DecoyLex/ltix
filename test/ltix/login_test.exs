defmodule Ltix.LoginTest do
  use ExUnit.Case, async: true

  doctest Ltix.Login

  alias Ltix.Test.StorageAdapter

  @redirect_uri "https://tool.example.com/callback"

  setup do
    {:ok, registration} =
      Ltix.Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/authorize",
        jwks_uri: "https://platform.example.com/.well-known/jwks.json"
      })

    StorageAdapter.set_pid(start_supervised!({StorageAdapter, registrations: [registration]}))

    params = %{
      "iss" => "https://platform.example.com",
      "login_hint" => "user-hint-123",
      "target_link_uri" => "https://tool.example.com/launch"
    }

    %{params: params}
  end

  defp login(params),
    do: Ltix.handle_login(params, @redirect_uri, storage_adapter: StorageAdapter)

  describe "handle_login/3" do
    # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
    # [Sec §5.1.1.2](https://www.imsglobal.org/spec/security/v1p0/#step-2-authentication-request)
    test "a valid login returns the redirect URI and state", %{params: params} do
      assert {:ok, result} = login(params)

      uri = URI.parse(result.redirect_uri)
      assert uri.host == "platform.example.com"
      assert uri.path == "/authorize"

      query = URI.decode_query(uri.query)
      assert query["scope"] == "openid"
      assert query["response_type"] == "id_token"
      assert query["client_id"] == "tool-client-id"
      assert query["redirect_uri"] == @redirect_uri
      assert query["login_hint"] == "user-hint-123"
      assert query["state"] == result.state
      assert query["response_mode"] == "form_post"
      assert query["nonce"] =~ ~r/\A[A-Za-z0-9_-]{43}\z/
      assert query["prompt"] == "none"
    end

    test "each login has its own state and nonce", %{params: params} do
      assert {:ok, first} = login(params)
      assert {:ok, second} = login(params)

      refute first.state == second.state
      refute LaunchFlow.nonce(first) == LaunchFlow.nonce(second)
    end
  end
end
