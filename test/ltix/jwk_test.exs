defmodule Ltix.JWKTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.InvalidField
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
      assert_raise Ltix.Errors.Invalid.InvalidOption,
                   ~r/Option :key_size is invalid.*at least 2048/,
                   fn -> JWK.generate(key_size: 1024) end
    end

    test "rejects unknown options" do
      assert_raise Ltix.Errors.Invalid.InvalidOption, "Option :size is unknown", fn ->
        JWK.generate(size: 4096)
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

    test "rejects unknown fields", ctx do
      for attrs <- [
            [private_key_pem: ctx.pem, kid: ctx.kid, key_id: "x"],
            %{private_key_pem: ctx.pem, kid: ctx.kid, key_id: "x"}
          ] do
        assert {:error, %InvalidField{struct: JWK, field: :key_id, value: "x", reason: :unknown}} =
                 JWK.new(attrs)
      end
    end

    test "missing fields and fields given nil are required", ctx do
      attrs = %{private_key_pem: ctx.pem, kid: ctx.kid}

      for field <- [:private_key_pem, :kid],
          attrs <- [Map.delete(attrs, field), %{attrs | field => nil}] do
        assert {:error, %InvalidField{struct: JWK, field: ^field, reason: :required}} =
                 JWK.new(attrs)
      end
    end

    test "rejects an unknown field given nil", ctx do
      assert {:error, %InvalidField{field: :key_id, reason: :unknown}} =
               JWK.new(private_key_pem: ctx.pem, kid: ctx.kid, key_id: nil)
    end

    test "invalid kid reports its value" do
      jwk = JWK.generate()

      for kid <- ["", 123] do
        assert {:error, %InvalidField{field: :kid, value: ^kid}} =
                 JWK.new(private_key_pem: jwk.private_key_pem, kid: kid)
      end
    end

    test "invalid private_key_pem is reported without revealing key material", ctx do
      ec_key = :public_key.generate_key({:namedCurve, :secp256r1})
      ec_pem = :public_key.pem_encode([:public_key.pem_entry_encode(:ECPrivateKey, ec_key)])
      public_pem = JWK.to_public_key(JWK.generate())

      for {pem, reason} <- [
            {"not-a-pem", "must be a PEM"},
            {ec_pem, "expected an RSA private key"},
            {public_pem, "expected an RSA private key"}
          ] do
        assert {:error, %InvalidField{field: :private_key_pem, value: "[redacted]"} = error} =
                 JWK.new(private_key_pem: pem, kid: ctx.kid)

        assert Exception.message(error) =~ reason
      end

      assert {:error, %InvalidField{field: :private_key_pem, value: 123}} =
               JWK.new(private_key_pem: 123, kid: ctx.kid)
    end

    test "new!/1 returns the JWK or raises the error", ctx do
      assert %JWK{kid: kid} = JWK.new!(private_key_pem: ctx.pem, kid: ctx.kid)
      assert kid == ctx.kid

      assert_raise InvalidField, "Ltix.JWK field :kid is required", fn ->
        JWK.new!(private_key_pem: ctx.pem)
      end
    end

    test "reports every invalid field together" do
      assert {:error,
              %Ltix.Errors.Invalid{
                errors: [%InvalidField{field: :private_key_pem}, %InvalidField{field: :kid}]
              }} = JWK.new(private_key_pem: "not-a-pem", kid: "")
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
