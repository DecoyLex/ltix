defmodule Ltix.RegisterableTest do
  use ExUnit.Case, async: true

  alias Ltix.Registerable
  alias Ltix.Registration

  @tool_jwk elem(Ltix.JWK.generate_key_pair(), 0)

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
        issuer: "https://canvas.example.edu",
        client_id: "10000000000042",
        auth_endpoint: "https://canvas.example.edu/api/lti/authorize_redirect",
        jwks_uri: "https://canvas.example.edu/api/lti/security/jwks",
        tool_jwk: @tool_jwk
      }

      assert {:ok, %Registration{} = reg} = Registerable.to_registration(custom)
      assert reg.issuer == "https://canvas.example.edu"
      assert reg.client_id == "10000000000042"
    end

    test "surfaces validation errors from Registration.new/1" do
      custom = %CustomRegistration{
        id: 1,
        tenant_id: 1,
        issuer: "not-https",
        client_id: "client",
        auth_endpoint: "https://example.com/auth",
        jwks_uri: "https://example.com/jwks",
        tool_jwk: @tool_jwk
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
