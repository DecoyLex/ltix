defmodule Ltix.RegistrationTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.Registration

  doctest Ltix.Registration

  @tool_jwk Ltix.JWK.generate()

  @valid_attrs %{
    issuer: "https://platform.example.com",
    client_id: "tool-client-123",
    auth_endpoint: "https://platform.example.com/auth",
    jwks_uri: "https://platform.example.com/.well-known/jwks.json",
    token_endpoint: "https://platform.example.com/token",
    tool_jwk: @tool_jwk
  }

  describe "new/1" do
    test "valid registration" do
      assert {:ok, %Registration{} = reg} = Registration.new(@valid_attrs)
      assert reg.issuer == "https://platform.example.com"
      assert reg.client_id == "tool-client-123"
      assert reg.auth_endpoint == "https://platform.example.com/auth"
      assert reg.jwks_uri == "https://platform.example.com/.well-known/jwks.json"
      assert reg.token_endpoint == "https://platform.example.com/token"
      assert reg.tool_jwk == @tool_jwk
    end

    test "rejects unknown fields" do
      for attrs <- [
            Map.put(@valid_attrs, :issuer_url, "x"),
            [{:issuer_url, "x"} | Map.to_list(@valid_attrs)]
          ] do
        assert {:error, %InvalidField{field: :issuer_url, value: "x", reason: :unknown}} =
                 Registration.new(attrs)
      end
    end

    test "valid registration without optional token_endpoint or with it nil" do
      for attrs <- [
            Map.delete(@valid_attrs, :token_endpoint),
            %{@valid_attrs | token_endpoint: nil}
          ] do
        assert {:ok, %Registration{token_endpoint: nil}} = Registration.new(attrs)
      end
    end

    test "rejects an unknown field given nil" do
      assert {:error, %InvalidField{field: :issuer_url, reason: :unknown}} =
               Registration.new(Map.put(@valid_attrs, :issuer_url, nil))
    end

    test "accepts issuer with port and path" do
      attrs = %{@valid_attrs | issuer: "https://platform.example.com:8443/lti"}

      assert {:ok, %Registration{issuer: "https://platform.example.com:8443/lti"}} =
               Registration.new(attrs)
    end

    # [Sec §5.1.2](https://www.imsglobal.org/spec/security/v1p0/#id-token)
    # [Sec §3](https://www.imsglobal.org/spec/security/v1p0/#transport-security)
    # [Sec §7.2](https://www.imsglobal.org/spec/security/v1p0/#h_key-management)
    test "reports an invalid field with its value" do
      for {field, value, reason} <- [
            {:issuer, "http://platform.example.com", "must be an HTTPS URL"},
            {:issuer, "https://platform.example.com?foo=bar",
             "must not include a query component"},
            {:issuer, "https://platform.example.com#section",
             "must not include a fragment component"},
            {:issuer, 123, "must be an HTTPS URL"},
            {:client_id, "", "must be a non-empty string"},
            {:client_id, 123, "must be a non-empty string"},
            {:auth_endpoint, "http://platform.example.com/auth", "must be an HTTPS URL"},
            {:jwks_uri, "http://platform.example.com/.well-known/jwks.json",
             "must be an HTTPS URL"},
            {:jwks_uri, :jwks, "must be an HTTPS URL"},
            {:token_endpoint, "http://platform.example.com/token", "must be an HTTPS URL"},
            {:tool_jwk, "not-a-jwk", "must be an %Ltix.JWK{} struct"}
          ] do
        assert {:error,
                %InvalidField{struct: Registration, field: ^field, value: ^value, reason: ^reason}} =
                 Registration.new(%{@valid_attrs | field => value})
      end
    end

    test "reports missing required fields" do
      for field <- [:issuer, :client_id, :auth_endpoint, :jwks_uri, :tool_jwk] do
        for attrs <- [Map.delete(@valid_attrs, field), %{@valid_attrs | field => nil}] do
          assert {:error, %InvalidField{field: ^field, reason: :required}} =
                   Registration.new(attrs)
        end
      end
    end

    test "reports every invalid field together" do
      attrs = %{@valid_attrs | issuer: "http://platform.example.com", client_id: ""}

      assert {:error,
              %Ltix.Errors.Invalid{
                errors: [%InvalidField{field: :issuer}, %InvalidField{field: :client_id}]
              }} = Registration.new(attrs)
    end

    test "new!/1 returns the registration or raises the error" do
      assert %Registration{issuer: "https://platform.example.com"} =
               Registration.new!(@valid_attrs)

      assert_raise InvalidField, "Ltix.Registration field :issuer is required", fn ->
        Registration.new!(Map.delete(@valid_attrs, :issuer))
      end
    end

    test "describes the field, the problem, and the value" do
      assert {:error, error} = Registration.new(%{@valid_attrs | client_id: ""})

      assert Exception.message(error) ==
               ~s(Ltix.Registration field :client_id is invalid, must be a non-empty string \(got ""\) [Sec §5.1.1.2])

      assert {:error, error} = Registration.new(Map.delete(@valid_attrs, :issuer))
      assert Exception.message(error) == "Ltix.Registration field :issuer is required"
    end
  end
end
