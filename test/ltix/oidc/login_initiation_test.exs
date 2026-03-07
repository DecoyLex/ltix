defmodule Ltix.OIDC.LoginInitiationTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.{MissingParameter, RegistrationNotFound}
  alias Ltix.OIDC.LoginInitiation
  alias Ltix.Test.TestStorageAdapter

  setup do
    {:ok, registration} =
      Ltix.Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/authorize",
        jwks_uri: "https://platform.example.com/.well-known/jwks.json"
      })

    {:ok, pid} = TestStorageAdapter.start_link(registrations: [registration])
    TestStorageAdapter.set_pid(pid)

    params = %{
      "iss" => "https://platform.example.com",
      "login_hint" => "user-hint-123",
      "target_link_uri" => "https://tool.example.com/launch"
    }

    opts = [redirect_uri: "https://tool.example.com/callback"]

    %{registration: registration, params: params, opts: opts}
  end

  describe "call/3" do
    # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
    test "valid login initiation returns redirect_uri and state", %{params: params, opts: opts} do
      assert {:ok, result} = LoginInitiation.call(params, TestStorageAdapter, opts)

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
    test "missing iss returns MissingParameter error", %{params: params, opts: opts} do
      params = Map.delete(params, "iss")

      assert {:error, %MissingParameter{parameter: "iss"}} =
               LoginInitiation.call(params, TestStorageAdapter, opts)
    end

    # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
    test "missing login_hint returns MissingParameter error", %{params: params, opts: opts} do
      params = Map.delete(params, "login_hint")

      assert {:error, %MissingParameter{parameter: "login_hint"}} =
               LoginInitiation.call(params, TestStorageAdapter, opts)
    end

    # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
    test "missing target_link_uri returns MissingParameter error", %{params: params, opts: opts} do
      params = Map.delete(params, "target_link_uri")

      assert {:error, %MissingParameter{parameter: "target_link_uri"}} =
               LoginInitiation.call(params, TestStorageAdapter, opts)
    end

    test "unknown issuer returns RegistrationNotFound error", %{params: params, opts: opts} do
      params = Map.put(params, "iss", "https://unknown.example.com")

      assert {:error, %RegistrationNotFound{issuer: "https://unknown.example.com"}} =
               LoginInitiation.call(params, TestStorageAdapter, opts)
    end

    # [Core §4.1.1](https://www.imsglobal.org/spec/lti/v1p3/#lti_message_hint-login-parameter)
    test "lti_message_hint preserved when present", %{params: params, opts: opts} do
      params = Map.put(params, "lti_message_hint", "platform-hint-456")

      assert {:ok, result} = LoginInitiation.call(params, TestStorageAdapter, opts)
      query = URI.parse(result.redirect_uri).query |> URI.decode_query()

      assert query["lti_message_hint"] == "platform-hint-456"
    end

    test "lti_message_hint omitted when not present", %{params: params, opts: opts} do
      assert {:ok, result} = LoginInitiation.call(params, TestStorageAdapter, opts)
      query = URI.parse(result.redirect_uri).query |> URI.decode_query()

      refute Map.has_key?(query, "lti_message_hint")
    end

    # [Core §4.1.3](https://www.imsglobal.org/spec/lti/v1p3/#client_id-login-parameter)
    test "client_id used for registration lookup when present", %{opts: opts} do
      {:ok, other_reg} =
        Ltix.Registration.new(%{
          issuer: "https://platform.example.com",
          client_id: "other-client-id",
          auth_endpoint: "https://platform.example.com/authorize",
          jwks_uri: "https://platform.example.com/.well-known/jwks.json"
        })

      {:ok, pid} = TestStorageAdapter.start_link(registrations: [other_reg])
      TestStorageAdapter.set_pid(pid)

      params = %{
        "iss" => "https://platform.example.com",
        "login_hint" => "user-hint-123",
        "target_link_uri" => "https://tool.example.com/launch",
        "client_id" => "other-client-id"
      }

      assert {:ok, result} = LoginInitiation.call(params, TestStorageAdapter, opts)
      query = URI.parse(result.redirect_uri).query |> URI.decode_query()

      assert query["client_id"] == "other-client-id"
    end

    test "client_id absent — registration looked up by issuer alone", %{
      params: params,
      opts: opts
    } do
      refute Map.has_key?(params, "client_id")

      assert {:ok, result} = LoginInitiation.call(params, TestStorageAdapter, opts)
      query = URI.parse(result.redirect_uri).query |> URI.decode_query()

      assert query["client_id"] == "tool-client-id"
    end

    test "nonce is stored via callback module", %{params: params, opts: opts} do
      assert {:ok, result} = LoginInitiation.call(params, TestStorageAdapter, opts)
      query = URI.parse(result.redirect_uri).query |> URI.decode_query()
      nonce = query["nonce"]

      assert MapSet.member?(TestStorageAdapter.stored_nonces(), nonce)
    end

    test "state and nonce are cryptographically random", %{params: params, opts: opts} do
      assert {:ok, result1} = LoginInitiation.call(params, TestStorageAdapter, opts)
      assert {:ok, result2} = LoginInitiation.call(params, TestStorageAdapter, opts)

      refute result1.state == result2.state

      q1 = URI.parse(result1.redirect_uri).query |> URI.decode_query()
      q2 = URI.parse(result2.redirect_uri).query |> URI.decode_query()

      refute q1["nonce"] == q2["nonce"]
    end
  end
end
