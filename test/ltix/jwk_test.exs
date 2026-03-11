defmodule Ltix.JWKTest do
  use ExUnit.Case, async: true

  alias Ltix.JWK

  doctest Ltix.JWK

  describe "generate_key_pair/1" do
    test "default generates 2048-bit RSA key pair" do
      {private, public} = JWK.generate_key_pair()

      {_kty, priv_fields} = JOSE.JWK.to_map(private)
      {_kty, pub_fields} = JOSE.JWK.to_map(public)

      assert priv_fields["kty"] == "RSA"
      assert pub_fields["kty"] == "RSA"
    end

    test "custom key size" do
      {private, _public} = JWK.generate_key_pair(key_size: 4096)

      {_kty, fields} = JOSE.JWK.to_map(private)
      assert fields["kty"] == "RSA"

      # 4096-bit key has a larger modulus than 2048-bit
      n_bytes =
        fields["n"]
        |> Base.url_decode64!(padding: false)
        |> byte_size()

      assert n_bytes > 256
    end

    test "rejects key size below 2048" do
      assert_raise Zoi.ParseError, ~r/must be at least 2048/, fn ->
        JWK.generate_key_pair(key_size: 1024)
      end
    end

    test "private key contains RSA private material" do
      {private, _public} = JWK.generate_key_pair()

      {_kty, fields} = JOSE.JWK.to_map(private)
      assert Map.has_key?(fields, "d")
      assert Map.has_key?(fields, "p")
      assert Map.has_key?(fields, "q")
    end

    test "public key contains only public material" do
      {_private, public} = JWK.generate_key_pair()

      {_kty, fields} = JOSE.JWK.to_map(public)
      assert Map.has_key?(fields, "n")
      assert Map.has_key?(fields, "e")
      refute Map.has_key?(fields, "d")
      refute Map.has_key?(fields, "p")
      refute Map.has_key?(fields, "q")
    end

    # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
    test "both keys share the same kid" do
      {private, public} = JWK.generate_key_pair()

      {_kty, priv_fields} = JOSE.JWK.to_map(private)
      {_kty, pub_fields} = JOSE.JWK.to_map(public)

      assert priv_fields["kid"] == pub_fields["kid"]
      assert is_binary(priv_fields["kid"])
      assert byte_size(priv_fields["kid"]) > 0
    end

    # [Sec §6.1](https://www.imsglobal.org/spec/security/v1p0/#platform-originating-messages)
    test "keys include alg RS256 and use sig" do
      {private, public} = JWK.generate_key_pair()

      {_kty, priv_fields} = JOSE.JWK.to_map(private)
      {_kty, pub_fields} = JOSE.JWK.to_map(public)

      assert priv_fields["alg"] == "RS256"
      assert priv_fields["use"] == "sig"
      assert pub_fields["alg"] == "RS256"
      assert pub_fields["use"] == "sig"
    end

    test "each call generates a unique kid" do
      {priv1, _} = JWK.generate_key_pair()
      {priv2, _} = JWK.generate_key_pair()

      {_kty, fields1} = JOSE.JWK.to_map(priv1)
      {_kty, fields2} = JOSE.JWK.to_map(priv2)

      refute fields1["kid"] == fields2["kid"]
    end
  end

  describe "to_jwks/1" do
    test "returns valid JWKS map with keys array" do
      {_private, public} = JWK.generate_key_pair()

      jwks = JWK.to_jwks([public])

      assert %{"keys" => [key]} = jwks
      assert key["kty"] == "RSA"
      assert Map.has_key?(key, "kid")
    end

    test "includes multiple keys" do
      {_, pub1} = JWK.generate_key_pair()
      {_, pub2} = JWK.generate_key_pair()

      jwks = JWK.to_jwks([pub1, pub2])

      assert %{"keys" => keys} = jwks
      assert length(keys) == 2
    end

    test "strips private material from output" do
      {private, _public} = JWK.generate_key_pair()

      # Pass the private key — to_jwks should still only output public material
      jwks = JWK.to_jwks([private])

      [key] = jwks["keys"]
      assert Map.has_key?(key, "n")
      assert Map.has_key?(key, "e")
      refute Map.has_key?(key, "d")
      refute Map.has_key?(key, "p")
      refute Map.has_key?(key, "q")
    end
  end
end
