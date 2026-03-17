defmodule Ltix.JWKTest do
  use ExUnit.Case, async: true

  alias Ltix.JWK

  doctest Ltix.JWK

  describe "generate/1" do
    test "returns a %Ltix.JWK{} struct" do
      assert %JWK{} = JWK.generate()
    end

    test "private_key_pem is a valid PEM" do
      jwk = JWK.generate()
      assert String.starts_with?(jwk.private_key_pem, "-----BEGIN")
      assert String.contains?(jwk.private_key_pem, "PRIVATE KEY-----")
    end

    test "kid is a non-empty string" do
      jwk = JWK.generate()
      assert is_binary(jwk.kid)
      assert byte_size(jwk.kid) > 0
    end

    test "kid is deterministic (thumbprint-based)" do
      jwk = JWK.generate()

      # Reconstruct the kid from the PEM to verify it matches
      recomputed_kid =
        jwk.private_key_pem
        |> JOSE.JWK.from_pem()
        |> JOSE.JWK.thumbprint()

      assert jwk.kid == recomputed_kid
    end

    test "rejects key size below 2048" do
      assert_raise Zoi.ParseError, ~r/must be at least 2048/, fn ->
        JWK.generate(key_size: 1024)
      end
    end

    test "each call generates a unique key" do
      jwk1 = JWK.generate()
      jwk2 = JWK.generate()

      refute jwk1.private_key_pem == jwk2.private_key_pem
      refute jwk1.kid == jwk2.kid
    end
  end

  describe "new/1" do
    setup do
      jwk = JWK.generate()
      %{pem: jwk.private_key_pem, kid: jwk.kid}
    end

    test "valid PEM and kid returns {:ok, %Ltix.JWK{}}", ctx do
      assert {:ok, %JWK{} = jwk} = JWK.new(private_key_pem: ctx.pem, kid: ctx.kid)
      assert jwk.private_key_pem == ctx.pem
      assert jwk.kid == ctx.kid
    end

    test "missing private_key_pem returns error" do
      assert {:error, error} = JWK.new(kid: "some-kid")
      assert Exception.message(error) =~ "private_key_pem"
    end

    test "missing kid returns error" do
      jwk = JWK.generate()
      assert {:error, error} = JWK.new(private_key_pem: jwk.private_key_pem)
      assert Exception.message(error) =~ "kid"
    end

    test "empty string kid returns error" do
      jwk = JWK.generate()
      assert {:error, error} = JWK.new(private_key_pem: jwk.private_key_pem, kid: "")
      assert Exception.message(error) =~ "kid"
    end

    test "non-PEM string returns error" do
      assert {:error, error} = JWK.new(private_key_pem: "not-a-pem", kid: "some-kid")
      assert Exception.message(error) =~ "private_key_pem"
    end

    test "PEM containing an EC key returns error" do
      # Generate an EC key PEM
      ec_key = :public_key.generate_key({:namedCurve, :secp256r1})
      ec_pem = :public_key.pem_encode([:public_key.pem_entry_encode(:ECPrivateKey, ec_key)])

      assert {:error, error} = JWK.new(private_key_pem: ec_pem, kid: "ec-kid")
      assert Exception.message(error) =~ "RSA private key"
    end

    test "PEM containing a public key returns error" do
      jwk = JWK.generate()
      public_pem = JWK.to_public_key(jwk)

      assert {:error, error} = JWK.new(private_key_pem: public_pem, kid: "pub-kid")
      assert Exception.message(error) =~ "RSA private key"
    end
  end

  describe "to_jwks/1" do
    test "single JWK returns %{keys => [key]} with one entry" do
      jwk = JWK.generate()
      jwks = JWK.to_jwks(jwk)

      assert %{"keys" => [key]} = jwks
      assert key["kty"] == "RSA"
    end

    test "list of JWKs returns matching count" do
      jwk1 = JWK.generate()
      jwk2 = JWK.generate()

      jwks = JWK.to_jwks([jwk1, jwk2])

      assert %{"keys" => keys} = jwks
      assert length(keys) == 2
    end

    test "output keys contain kty, n, e, kid, alg, use" do
      jwk = JWK.generate()
      %{"keys" => [key]} = JWK.to_jwks(jwk)

      assert Map.has_key?(key, "kty")
      assert Map.has_key?(key, "n")
      assert Map.has_key?(key, "e")
      assert Map.has_key?(key, "kid")
      assert Map.has_key?(key, "alg")
      assert Map.has_key?(key, "use")
    end

    test "output keys do NOT contain private material" do
      jwk = JWK.generate()
      %{"keys" => [key]} = JWK.to_jwks(jwk)

      refute Map.has_key?(key, "d")
      refute Map.has_key?(key, "p")
      refute Map.has_key?(key, "q")
      refute Map.has_key?(key, "dp")
      refute Map.has_key?(key, "dq")
      refute Map.has_key?(key, "qi")
    end

    test "kid in output matches the struct's kid field" do
      jwk = JWK.generate()
      %{"keys" => [key]} = JWK.to_jwks(jwk)

      assert key["kid"] == jwk.kid
    end

    test "alg is RS256, use is sig" do
      jwk = JWK.generate()
      %{"keys" => [key]} = JWK.to_jwks(jwk)

      assert key["alg"] == "RS256"
      assert key["use"] == "sig"
    end
  end

  describe "to_public_key/1" do
    test "returns a string starting with BEGIN" do
      jwk = JWK.generate()
      public_pem = JWK.to_public_key(jwk)

      assert String.starts_with?(public_pem, "-----BEGIN")
    end

    test "does not contain private key material" do
      jwk = JWK.generate()
      public_pem = JWK.to_public_key(jwk)

      refute String.contains?(public_pem, "PRIVATE")
    end
  end
end
