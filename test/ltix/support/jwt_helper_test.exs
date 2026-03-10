defmodule Ltix.Test.JWTHelperTest do
  use ExUnit.Case, async: true

  alias Ltix.Test.JWTHelper

  describe "generate_rsa_key_pair/0" do
    test "generates unique kid each time" do
      {_, _, kid1} = JWTHelper.generate_rsa_key_pair()
      {_, _, kid2} = JWTHelper.generate_rsa_key_pair()
      assert kid1 != kid2
    end
  end

  describe "build_jwks/1" do
    test "builds a JWKS map with kid and RSA modulus" do
      {_priv, pub, kid} = JWTHelper.generate_rsa_key_pair()
      jwks = JWTHelper.build_jwks([pub])

      assert %{"keys" => [key]} = jwks
      assert key["kid"] == kid
      assert Map.has_key?(key, "n"), "RSA modulus (n) required by [Sec §6.2]"
      assert Map.has_key?(key, "e"), "RSA exponent (e) required by [Sec §6.2]"
    end

    test "includes all provided keys" do
      {_priv1, pub1, kid1} = JWTHelper.generate_rsa_key_pair()
      {_priv2, pub2, kid2} = JWTHelper.generate_rsa_key_pair()
      jwks = JWTHelper.build_jwks([pub1, pub2])

      assert %{"keys" => keys} = jwks
      kids = Enum.map(keys, & &1["kid"])
      assert kid1 in kids
      assert kid2 in kids
    end
  end

  describe "mint_id_token/3" do
    test "embeds claims into a three-part JWT" do
      {private_jwk, _public_jwk, kid} = JWTHelper.generate_rsa_key_pair()
      claims = %{"sub" => "user-1", "iss" => "https://platform.example.com"}

      token = JWTHelper.mint_id_token(claims, private_jwk, kid: kid)

      # Decode the payload directly to check claims round-tripped
      [_header, payload_b64, _signature] = String.split(token, ".")

      payload =
        payload_b64
        |> Base.url_decode64!(padding: false)
        |> Ltix.AppConfig.json_library!().decode!()

      assert payload["sub"] == "user-1"
      assert payload["iss"] == "https://platform.example.com"
    end

    test "includes kid in JWT header when provided" do
      {private_jwk, _public_jwk, kid} = JWTHelper.generate_rsa_key_pair()
      token = JWTHelper.mint_id_token(%{"sub" => "user-1"}, private_jwk, kid: kid)

      # Decode raw header to check kid
      [header_b64 | _] = String.split(token, ".")

      header =
        header_b64
        |> Base.url_decode64!(padding: false)
        |> Ltix.AppConfig.json_library!().decode!()

      assert header["kid"] == kid
    end

    test "omits kid from header when not provided" do
      {private_jwk, _public_jwk, _kid} = JWTHelper.generate_rsa_key_pair()
      token = JWTHelper.mint_id_token(%{"sub" => "user-1"}, private_jwk)

      [header_b64 | _] = String.split(token, ".")

      header =
        header_b64
        |> Base.url_decode64!(padding: false)
        |> Ltix.AppConfig.json_library!().decode!()

      refute Map.has_key?(header, "kid")
    end
  end

  describe "valid_lti_claims/1" do
    test "returns a complete LtiResourceLinkRequest claim set" do
      claims = JWTHelper.valid_lti_claims()

      # Required OIDC claims [Sec §5.1.2] — assert specific expected values
      assert claims["iss"] == "https://platform.example.com"
      assert claims["sub"] == "user-12345"
      assert claims["aud"] == "tool-client-id"
      assert claims["exp"] > System.system_time(:second)
      assert claims["iat"] <= System.system_time(:second)
      assert byte_size(claims["nonce"]) > 0

      # Required LTI claims [Core §5.3]
      lti = "https://purl.imsglobal.org/spec/lti/claim/"
      assert claims[lti <> "message_type"] == "LtiResourceLinkRequest"
      assert claims[lti <> "version"] == "1.3.0"
      assert claims[lti <> "deployment_id"] == "deployment-001"
      assert claims[lti <> "target_link_uri"] == "https://tool.example.com/launch"
      assert [_ | _] = claims[lti <> "roles"]
      assert %{"id" => "resource-link-001"} = claims[lti <> "resource_link"]
    end

    test "allows overriding individual claims" do
      claims = JWTHelper.valid_lti_claims(%{"sub" => "custom-user"})
      assert claims["sub"] == "custom-user"
      # Non-overridden claims retain defaults
      assert claims["iss"] == "https://platform.example.com"
    end
  end
end
