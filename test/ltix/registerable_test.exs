defmodule Ltix.RegisterableTest do
  use ExUnit.Case, async: true

  alias Ltix.Registerable
  alias Ltix.Registration

  @tool_jwk Ltix.JWK.generate()

  describe "Ltix.Registration identity implementation" do
    test "returns the registration unchanged" do
      {:ok, reg} =
        Registration.new(%{
          issuer: "https://platform.example.com",
          client_id: "client-123",
          auth_endpoint: "https://platform.example.com/auth",
          jwks_uri: "https://platform.example.com/.well-known/jwks.json",
          tool_jwk: @tool_jwk
        })

      assert Registerable.to_registration(reg) == {:ok, reg}
    end
  end

  describe "custom struct implementation" do
    test "extracts a Registration from a custom struct" do
      custom = %CustomRegistration{
        id: 42,
        tenant_id: 7,
        platform_issuer: "https://canvas.example.edu",
        oauth_client_id: "10000000000042",
        oidc_auth_url: "https://canvas.example.edu/api/lti/authorize_redirect",
        platform_jwks_url: "https://canvas.example.edu/api/lti/security/jwks",
        signing_key: @tool_jwk
      }

      assert {:ok, %Registration{} = reg} = Registerable.to_registration(custom)
      assert reg.issuer == "https://canvas.example.edu"
      assert reg.client_id == "10000000000042"
    end

    test "surfaces validation errors from Registration.new/1" do
      custom = %CustomRegistration{
        id: 1,
        tenant_id: 1,
        platform_issuer: "not-https",
        oauth_client_id: "client",
        oidc_auth_url: "https://example.com/auth",
        platform_jwks_url: "https://example.com/jwks",
        signing_key: @tool_jwk
      }

      assert {:error, error} = Registerable.to_registration(custom)
      assert Exception.message(error) =~ "issuer"
    end
  end

  test "raises Protocol.UndefinedError for unimplemented types" do
    assert_raise Protocol.UndefinedError, fn ->
      Registerable.to_registration(%{})
    end
  end
end
