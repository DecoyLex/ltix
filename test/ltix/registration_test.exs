defmodule Ltix.RegistrationTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.InvalidField
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

    # [RFC 7519 §2](https://www.rfc-editor.org/rfc/rfc7519#section-2)
    test "accepts an audience that is a URI or a string without a colon" do
      for audience <- [
            "https://api.platform.example.com/auth/token",
            "urn:example:authorization-server",
            "platform.example.com"
          ] do
        assert {:ok, %Registration{audience: ^audience}} =
                 Registration.new(Map.put(@valid_attrs, :audience, audience))
      end
    end

    test "accepts an audience without a token endpoint, and no audience" do
      attrs = Map.delete(@valid_attrs, :token_endpoint)

      assert {:ok, %Registration{audience: "platform.example.com", token_endpoint: nil}} =
               Registration.new(Map.put(attrs, :audience, "platform.example.com"))

      assert {:ok, %Registration{audience: nil}} = Registration.new(@valid_attrs)
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
            {:issuer, "http://platform.example.com", "must be an absolute HTTPS URL"},
            {:issuer, "https://platform.example.com?foo=bar",
             "must not include a query component"},
            {:issuer, "https://platform.example.com#section",
             "must not include a fragment component"},
            {:issuer, 123, "must be an absolute HTTPS URL"},
            {:client_id, "", "must be a non-empty string"},
            {:client_id, 123, "must be a non-empty string"},
            {:auth_endpoint, "http://platform.example.com/auth", "must be an absolute HTTPS URL"},
            {:jwks_uri, "http://platform.example.com/.well-known/jwks.json",
             "must be an absolute HTTPS URL"},
            {:jwks_uri, :jwks, "must be an absolute HTTPS URL"},
            {:token_endpoint, "http://platform.example.com/token",
             "must be an absolute HTTPS URL"},
            {:auth_endpoint, "https://user:secret@platform.example.com/auth",
             "must be an absolute HTTPS URL"},
            {:jwks_uri, "https://platform.example.com:0/jwks", "must be an absolute HTTPS URL"},
            {:token_endpoint, "https://platform.example.com/a token",
             "must be an absolute HTTPS URL"},
            {:audience, "", "must be a non-empty string"},
            {:audience, ["https://platform.example.com/token"], "must be a non-empty string"},
            {:audience, "platform.example.com:token server",
             "must be a URI when it includes a colon"},
            {:audience, ":platform", "must be a URI when it includes a colon"}
          ] do
        assert {:error,
                %InvalidField{struct: Registration, field: ^field, value: ^value, reason: ^reason}} =
                 Registration.new(Map.put(@valid_attrs, field, value))
      end
    end

    test "reports missing required fields" do
      for field <- [:issuer, :client_id, :auth_endpoint, :jwks_uri] do
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
               ~s(Ltix.Registration field :client_id is invalid, must be a non-empty string \(got ""\))

      assert {:error, error} = Registration.new(Map.delete(@valid_attrs, :issuer))
      assert Exception.message(error) == "Ltix.Registration field :issuer is required"
    end
  end
end
