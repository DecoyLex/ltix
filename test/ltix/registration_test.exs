defmodule Ltix.RegistrationTest do
  use ExUnit.Case, async: true

  alias Ltix.Registration

  doctest Ltix.Registration

  @valid_attrs %{
    issuer: "https://platform.example.com",
    client_id: "tool-client-123",
    auth_endpoint: "https://platform.example.com/auth",
    jwks_uri: "https://platform.example.com/.well-known/jwks.json",
    token_endpoint: "https://platform.example.com/token"
  }

  describe "new/1" do
    test "valid registration" do
      assert {:ok, %Registration{} = reg} = Registration.new(@valid_attrs)
      assert reg.issuer == "https://platform.example.com"
      assert reg.client_id == "tool-client-123"
      assert reg.auth_endpoint == "https://platform.example.com/auth"
      assert reg.jwks_uri == "https://platform.example.com/.well-known/jwks.json"
      assert reg.token_endpoint == "https://platform.example.com/token"
    end

    test "valid registration without optional token_endpoint" do
      attrs = Map.delete(@valid_attrs, :token_endpoint)
      assert {:ok, %Registration{token_endpoint: nil}} = Registration.new(attrs)
    end

    # [Sec §5.1.2] issuer MUST be HTTPS URL
    test "rejects non-HTTPS issuer" do
      attrs = %{@valid_attrs | issuer: "http://platform.example.com"}
      assert {:error, error} = Registration.new(attrs)
      assert Exception.message(error) =~ "issuer"
    end

    # [Sec §5.1.2] issuer MUST have no query component
    test "rejects issuer with query string" do
      attrs = %{@valid_attrs | issuer: "https://platform.example.com?foo=bar"}
      assert {:error, error} = Registration.new(attrs)
      assert Exception.message(error) =~ "issuer"
    end

    # [Sec §5.1.2] issuer MUST have no fragment component
    test "rejects issuer with fragment" do
      attrs = %{@valid_attrs | issuer: "https://platform.example.com#section"}
      assert {:error, error} = Registration.new(attrs)
      assert Exception.message(error) =~ "issuer"
    end

    test "rejects empty client_id" do
      attrs = %{@valid_attrs | client_id: ""}
      assert {:error, error} = Registration.new(attrs)
      assert Exception.message(error) =~ "client_id"
    end

    test "rejects nil client_id" do
      attrs = %{@valid_attrs | client_id: nil}
      assert {:error, error} = Registration.new(attrs)
      assert Exception.message(error) =~ "client_id"
    end

    # [Sec §3] All endpoints MUST be HTTPS
    test "rejects non-HTTPS auth_endpoint" do
      attrs = %{@valid_attrs | auth_endpoint: "http://platform.example.com/auth"}
      assert {:error, error} = Registration.new(attrs)
      assert Exception.message(error) =~ "auth_endpoint"
    end

    # [Sec §3] All endpoints MUST be HTTPS
    test "rejects non-HTTPS jwks_uri" do
      attrs = %{@valid_attrs | jwks_uri: "http://platform.example.com/.well-known/jwks.json"}
      assert {:error, error} = Registration.new(attrs)
      assert Exception.message(error) =~ "jwks_uri"
    end

    # [Sec §3] All endpoints MUST be HTTPS
    test "rejects non-HTTPS token_endpoint when present" do
      attrs = %{@valid_attrs | token_endpoint: "http://platform.example.com/token"}
      assert {:error, error} = Registration.new(attrs)
      assert Exception.message(error) =~ "token_endpoint"
    end

    test "accepts issuer with port and path" do
      attrs = %{@valid_attrs | issuer: "https://platform.example.com:8443/lti"}

      assert {:ok, %Registration{issuer: "https://platform.example.com:8443/lti"}} =
               Registration.new(attrs)
    end
  end
end
