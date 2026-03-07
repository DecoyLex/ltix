defmodule Ltix.OIDC.AuthenticationRequestTest do
  use ExUnit.Case, async: true

  alias Ltix.OIDC.AuthenticationRequest
  alias Ltix.Registration

  setup do
    {:ok, registration} =
      Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/authorize",
        jwks_uri: "https://platform.example.com/.well-known/jwks.json"
      })

    params = %{
      redirect_uri: "https://tool.example.com/callback",
      state: "csrf-state-value",
      nonce: "nonce-value",
      login_hint: "user-hint-123"
    }

    %{registration: registration, params: params}
  end

  describe "build/2" do
    # [Sec §5.1.1.2](https://www.imsglobal.org/spec/security/v1p0/#step-2-authentication-request)
    test "includes all required OIDC parameters", %{registration: reg, params: params} do
      url = AuthenticationRequest.build(reg, params)
      query = URI.parse(url).query |> URI.decode_query()

      assert URI.parse(url).host == "platform.example.com"
      assert URI.parse(url).path == "/authorize"
      assert query["scope"] == "openid"
      assert query["response_type"] == "id_token"
      assert query["client_id"] == "tool-client-id"
      assert query["redirect_uri"] == "https://tool.example.com/callback"
      assert query["login_hint"] == "user-hint-123"
      assert query["state"] == "csrf-state-value"
      assert query["response_mode"] == "form_post"
      assert query["nonce"] == "nonce-value"
      assert query["prompt"] == "none"
    end

    # [Core §4.1.1](https://www.imsglobal.org/spec/lti/v1p3/#lti_message_hint-login-parameter)
    test "includes lti_message_hint when provided", %{registration: reg, params: params} do
      params = Map.put(params, :lti_message_hint, "platform-hint-456")
      url = AuthenticationRequest.build(reg, params)
      query = URI.parse(url).query |> URI.decode_query()

      assert query["lti_message_hint"] == "platform-hint-456"
    end

    test "omits lti_message_hint when not provided", %{registration: reg, params: params} do
      url = AuthenticationRequest.build(reg, params)
      query = URI.parse(url).query |> URI.decode_query()

      refute Map.has_key?(query, "lti_message_hint")
    end

    test "properly URL-encodes redirect_uri", %{registration: reg, params: params} do
      params = %{params | redirect_uri: "https://tool.example.com/callback?foo=bar&baz=qux"}
      url = AuthenticationRequest.build(reg, params)

      # The redirect_uri should be encoded in the query string
      assert url =~ "redirect_uri=https%3A%2F%2Ftool.example.com%2Fcallback"
    end

    # [Sec §5.1.1.2](https://www.imsglobal.org/spec/security/v1p0/#step-2-authentication-request)
    test "always sets prompt=none", %{registration: reg, params: params} do
      url = AuthenticationRequest.build(reg, params)
      query = URI.parse(url).query |> URI.decode_query()

      assert query["prompt"] == "none"
    end
  end
end
