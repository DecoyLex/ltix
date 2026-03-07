defmodule Ltix.Test.JWTHelperTest do
  use ExUnit.Case, async: true

  alias Ltix.Test.JWTHelper

  describe "generate_rsa_key_pair/0" do
    test "returns {private_jwk, public_jwk, kid}" do
      {private_jwk, public_jwk, kid} = JWTHelper.generate_rsa_key_pair()

      assert %JOSE.JWK{} = private_jwk
      assert %JOSE.JWK{} = public_jwk
      assert is_binary(kid) and byte_size(kid) > 0
    end

    test "generates unique kid each time" do
      {_, _, kid1} = JWTHelper.generate_rsa_key_pair()
      {_, _, kid2} = JWTHelper.generate_rsa_key_pair()
      assert kid1 != kid2
    end
  end

  describe "build_jwks/1" do
    test "builds a JWKS map with keys array" do
      {_priv, pub, kid} = JWTHelper.generate_rsa_key_pair()
      jwks = JWTHelper.build_jwks([pub])
      assert %{"keys" => [key]} = jwks
      assert key["kty"] == "RSA"
      assert key["kid"] == kid
    end

    test "includes multiple keys" do
      {_priv1, pub1, _kid1} = JWTHelper.generate_rsa_key_pair()
      {_priv2, pub2, _kid2} = JWTHelper.generate_rsa_key_pair()
      jwks = JWTHelper.build_jwks([pub1, pub2])
      assert %{"keys" => keys} = jwks
      assert length(keys) == 2
    end
  end

  describe "mint_id_token/3" do
    test "produces a JWT whose payload round-trips through verification" do
      {private_jwk, public_jwk, kid} = JWTHelper.generate_rsa_key_pair()
      claims = %{"sub" => "user-1", "iss" => "https://platform.example.com"}

      token = JWTHelper.mint_id_token(claims, private_jwk, kid: kid)

      # Peek at the payload without verification to confirm our helper
      # embedded the claims we asked for
      %JOSE.JWT{fields: payload} = JOSE.JWT.peek_payload(token)
      assert payload["sub"] == "user-1"
      assert payload["iss"] == "https://platform.example.com"

      # Confirm the token is verifiable (integration check for the helper)
      {true, _jwt, _jws} = JOSE.JWT.verify_strict(public_jwk, ["RS256"], token)
    end

    test "includes kid in JWT header" do
      {private_jwk, _public_jwk, kid} = JWTHelper.generate_rsa_key_pair()
      token = JWTHelper.mint_id_token(%{"sub" => "user-1"}, private_jwk, kid: kid)

      # Peek at the header
      %JOSE.JWS{fields: fields} = JOSE.JWT.peek_protected(token)
      assert fields["kid"] == kid
    end

    test "allows custom alg for testing bad scenarios" do
      {private_jwk, _public_jwk, kid} = JWTHelper.generate_rsa_key_pair()
      token = JWTHelper.mint_id_token(%{"sub" => "user-1"}, private_jwk, kid: kid, alg: "RS256")
      assert is_binary(token)
    end
  end

  describe "valid_lti_claims/1" do
    test "returns a complete LtiResourceLinkRequest claim set" do
      claims = JWTHelper.valid_lti_claims()

      # Required OIDC claims [Sec §5.1.2]
      assert is_binary(claims["iss"])
      assert is_binary(claims["sub"])
      assert is_binary(claims["aud"]) or is_list(claims["aud"])
      assert is_integer(claims["exp"])
      assert is_integer(claims["iat"])
      assert is_binary(claims["nonce"])

      # Required LTI claims [Core §5.3]
      assert claims["https://purl.imsglobal.org/spec/lti/claim/message_type"] ==
               "LtiResourceLinkRequest"

      assert claims["https://purl.imsglobal.org/spec/lti/claim/version"] == "1.3.0"
      assert is_binary(claims["https://purl.imsglobal.org/spec/lti/claim/deployment_id"])
      assert is_binary(claims["https://purl.imsglobal.org/spec/lti/claim/target_link_uri"])
      assert is_list(claims["https://purl.imsglobal.org/spec/lti/claim/roles"])

      assert is_map(claims["https://purl.imsglobal.org/spec/lti/claim/resource_link"])

      assert is_binary(claims["https://purl.imsglobal.org/spec/lti/claim/resource_link"]["id"])
    end

    test "allows overriding individual claims" do
      claims = JWTHelper.valid_lti_claims(%{"sub" => "custom-user"})
      assert claims["sub"] == "custom-user"
    end
  end
end
