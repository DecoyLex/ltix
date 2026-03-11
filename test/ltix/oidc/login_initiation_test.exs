defmodule Ltix.OIDC.LoginInitiationTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.MissingParameter
  alias Ltix.Errors.Invalid.RegistrationNotFound
  alias Ltix.OIDC.LoginInitiation
  alias Ltix.Test.StorageAdapter

  @tool_jwk elem(Ltix.JWK.generate_key_pair(), 0)

  setup do
    {:ok, registration} =
      Ltix.Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/authorize",
        jwks_uri: "https://platform.example.com/.well-known/jwks.json",
        tool_jwk: @tool_jwk
      })

    {:ok, pid} = StorageAdapter.start_link(registrations: [registration])
    StorageAdapter.set_pid(pid)

    params = %{
      "iss" => "https://platform.example.com",
      "login_hint" => "user-hint-123",
      "target_link_uri" => "https://tool.example.com/launch"
    }

    redirect_uri = "https://tool.example.com/callback"

    %{registration: registration, params: params, redirect_uri: redirect_uri}
  end

  describe "call/3" do
    # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
    test "valid login initiation returns redirect_uri and state", %{
      params: params,
      redirect_uri: redirect_uri
    } do
      assert {:ok, result} = LoginInitiation.call(params, StorageAdapter, redirect_uri)

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

    # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
    test "missing iss returns MissingParameter error", %{
      params: params,
      redirect_uri: redirect_uri
    } do
      params = Map.delete(params, "iss")

      assert {:error, %MissingParameter{parameter: "iss"}} =
               LoginInitiation.call(params, StorageAdapter, redirect_uri)
    end

    # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
    test "missing login_hint returns MissingParameter error", %{
      params: params,
      redirect_uri: redirect_uri
    } do
      params = Map.delete(params, "login_hint")

      assert {:error, %MissingParameter{parameter: "login_hint"}} =
               LoginInitiation.call(params, StorageAdapter, redirect_uri)
    end

    # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
    test "missing target_link_uri returns MissingParameter error", %{
      params: params,
      redirect_uri: redirect_uri
    } do
      params = Map.delete(params, "target_link_uri")

      assert {:error, %MissingParameter{parameter: "target_link_uri"}} =
               LoginInitiation.call(params, StorageAdapter, redirect_uri)
    end

    test "unknown issuer returns RegistrationNotFound error", %{
      params: params,
      redirect_uri: redirect_uri
    } do
      params = Map.put(params, "iss", "https://unknown.example.com")

      assert {:error, %RegistrationNotFound{issuer: "https://unknown.example.com"}} =
               LoginInitiation.call(params, StorageAdapter, redirect_uri)
    end

    # [Core §4.1.1](https://www.imsglobal.org/spec/lti/v1p3/#lti_message_hint-login-parameter)
    test "lti_message_hint preserved when present", %{params: params, redirect_uri: redirect_uri} do
      params = Map.put(params, "lti_message_hint", "platform-hint-456")

      assert {:ok, result} = LoginInitiation.call(params, StorageAdapter, redirect_uri)
      query = URI.decode_query(URI.parse(result.redirect_uri).query)

      assert query["lti_message_hint"] == "platform-hint-456"
    end

    test "lti_message_hint omitted when not present", %{
      params: params,
      redirect_uri: redirect_uri
    } do
      assert {:ok, result} = LoginInitiation.call(params, StorageAdapter, redirect_uri)
      query = URI.decode_query(URI.parse(result.redirect_uri).query)

      refute Map.has_key?(query, "lti_message_hint")
    end

    # [Core §4.1.3](https://www.imsglobal.org/spec/lti/v1p3/#client_id-login-parameter)
    test "client_id used for registration lookup when present", %{redirect_uri: redirect_uri} do
      {:ok, other_reg} =
        Ltix.Registration.new(%{
          issuer: "https://platform.example.com",
          client_id: "other-client-id",
          auth_endpoint: "https://platform.example.com/authorize",
          jwks_uri: "https://platform.example.com/.well-known/jwks.json",
          tool_jwk: @tool_jwk
        })

      {:ok, pid} = StorageAdapter.start_link(registrations: [other_reg])
      StorageAdapter.set_pid(pid)

      params = %{
        "iss" => "https://platform.example.com",
        "login_hint" => "user-hint-123",
        "target_link_uri" => "https://tool.example.com/launch",
        "client_id" => "other-client-id"
      }

      assert {:ok, result} = LoginInitiation.call(params, StorageAdapter, redirect_uri)
      query = URI.decode_query(URI.parse(result.redirect_uri).query)

      assert query["client_id"] == "other-client-id"
    end

    test "client_id absent — registration looked up by issuer alone", %{
      params: params,
      redirect_uri: redirect_uri
    } do
      refute Map.has_key?(params, "client_id")

      assert {:ok, result} = LoginInitiation.call(params, StorageAdapter, redirect_uri)
      query = URI.decode_query(URI.parse(result.redirect_uri).query)

      assert query["client_id"] == "tool-client-id"
    end

    test "nonce is stored via callback module", %{params: params, redirect_uri: redirect_uri} do
      assert {:ok, result} = LoginInitiation.call(params, StorageAdapter, redirect_uri)
      query = URI.decode_query(URI.parse(result.redirect_uri).query)
      nonce = query["nonce"]

      assert MapSet.member?(StorageAdapter.stored_nonces(), nonce)
    end

    test "state and nonce are cryptographically random", %{
      params: params,
      redirect_uri: redirect_uri
    } do
      assert {:ok, result1} = LoginInitiation.call(params, StorageAdapter, redirect_uri)
      assert {:ok, result2} = LoginInitiation.call(params, StorageAdapter, redirect_uri)

      refute result1.state == result2.state

      q1 = URI.decode_query(URI.parse(result1.redirect_uri).query)
      q2 = URI.decode_query(URI.parse(result2.redirect_uri).query)

      refute q1["nonce"] == q2["nonce"]
    end
  end
end
