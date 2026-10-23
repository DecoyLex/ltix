defmodule Ltix.JWKTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.JWK

  doctest Ltix.JWK

  describe "generate/1" do
    # [RFC 7638 §3](https://www.rfc-editor.org/rfc/rfc7638#section-3)
    test "kid is the SHA-256 JWK thumbprint of the generated key" do
      jwk = JWK.generate()
      %{"keys" => [%{"e" => exponent, "n" => modulus}]} = JWK.to_jwks(jwk)
      members = ~s({"e":"#{exponent}","kty":"RSA","n":"#{modulus}"})

      assert jwk.kid == Base.url_encode64(:crypto.hash(:sha256, members), padding: false)
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
      assert {:error, %InvalidField{struct: JWK, field: :key_id, reason: :unknown}} =
               JWK.new(private_key_pem: ctx.pem, kid: ctx.kid, key_id: "x")
    end

    test "rejects an unknown field without revealing its value", ctx do
      assert {:error, %InvalidField{field: :private_key, value: "[redacted]"} = error} =
               JWK.new(private_key_pem: ctx.pem, kid: ctx.kid, private_key: ctx.pem)

      refute inspect(error) =~ "PRIVATE KEY"
      assert Exception.message(error) == "Ltix.JWK field :private_key is unknown"
    end

    test "a missing kid is required", ctx do
      assert {:error, %InvalidField{struct: JWK, field: :kid, reason: :required}} =
               JWK.new(%{private_key_pem: ctx.pem})
    end

    test "requires one key", ctx do
      assert {:error, %InvalidField{struct: JWK, field: :public_key_pem} = error} =
               JWK.new(%{kid: ctx.kid})

      assert Exception.message(error) =~ "one of public_key_pem, public_key_der, public_jwk"
    end

    test "rejects two keys without revealing key material", ctx do
      public_pem = JWK.to_public_key(JWK.new!(private_key_pem: ctx.pem, kid: ctx.kid))

      assert {:error, %InvalidField{struct: JWK, value: "[redacted]"} = error} =
               JWK.new(private_key_pem: ctx.pem, public_key_pem: public_pem, kid: ctx.kid)

      assert Exception.message(error) =~ "only one key can be given"
    end

    test "rejects an unknown field given nil", ctx do
      assert {:error, %InvalidField{field: :key_id, reason: :unknown}} =
               JWK.new(private_key_pem: ctx.pem, kid: ctx.kid, key_id: nil)
    end

    test "invalid kid reports its value" do
      jwk = JWK.generate()

      assert {:error, %InvalidField{field: :kid, value: ""}} =
               JWK.new(private_key_pem: jwk.private_key_pem, kid: "")
    end

    test "invalid private_key_pem is reported without revealing key material", ctx do
      ec_key = :public_key.generate_key({:namedCurve, :secp256r1})
      ec_pem = :public_key.pem_encode([:public_key.pem_entry_encode(:ECPrivateKey, ec_key)])
      public_pem = JWK.to_public_key(JWK.generate())

      [rsa_entry] = :public_key.pem_decode(ctx.pem)
      rsa_key = :public_key.pem_entry_decode(rsa_entry)
      cipher = {{~c"AES-128-CBC", :crypto.strong_rand_bytes(16)}, ~c"passphrase"}

      encrypted_pem =
        :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, rsa_key, cipher)])

      garbage_pem = "-----BEGIN RSA PRIVATE KEY-----\nAAAA\n-----END RSA PRIVATE KEY-----\n"

      for {pem, reason} <- [
            {"not-a-pem", "must be a PEM"},
            {ec_pem, "expected an RSA private key"},
            {public_pem, "expected an RSA private key"},
            {encrypted_pem, "must not be encrypted"},
            {garbage_pem, "expected an RSA private key"}
          ] do
        assert {:error, %InvalidField{field: :private_key_pem, value: "[redacted]"} = error} =
                 JWK.new(private_key_pem: pem, kid: ctx.kid)

        assert Exception.message(error) =~ reason
      end

      for pem <- [123, String.to_charlist(ctx.pem)] do
        assert {:error, %InvalidField{field: :private_key_pem, value: "[redacted]"}} =
                 JWK.new(private_key_pem: pem, kid: ctx.kid)
      end
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

  describe "new/1 with other key formats" do
    setup do
      jwk = JWK.generate(key_size: 2048)
      public_pem = JWK.to_public_key(jwk)
      [public_entry] = :public_key.pem_decode(public_pem)
      [private_entry] = :public_key.pem_decode(jwk.private_key_pem)
      [public_map] = JWK.to_jwks(jwk)["keys"]

      {_type, private_map} = JOSE.JWK.to_map(JOSE.JWK.from_pem(jwk.private_key_pem))

      %{
        jwk: jwk,
        public_pem: public_pem,
        public_der: elem(public_entry, 1),
        public_map: public_map,
        private_der: elem(private_entry, 1),
        private_map: private_map
      }
    end

    test "a public key in any format builds the same key without a private key", ctx do
      for attrs <- [
            [public_key_pem: ctx.public_pem],
            [public_key_der: ctx.public_der],
            [public_jwk: ctx.public_map],
            [public_jwk: Map.delete(ctx.public_map, "kid")]
          ] do
        assert {:ok, %JWK{private_key_pem: nil} = jwk} = JWK.new([kid: ctx.jwk.kid] ++ attrs)
        assert jwk.kid == ctx.jwk.kid
        assert JWK.to_jwks(jwk) == JWK.to_jwks(ctx.jwk)
        assert JWK.to_public_key(jwk) == ctx.public_pem
      end
    end

    test "a private key in any format builds the same key", ctx do
      for attrs <- [
            [private_key_pem: ctx.jwk.private_key_pem],
            [private_key_der: ctx.private_der],
            [private_jwk: ctx.private_map]
          ] do
        assert {:ok, %JWK{} = jwk} = JWK.new([kid: ctx.jwk.kid] ++ attrs)
        assert JWK.to_public_key(jwk) == ctx.public_pem
        assert {:ok, signature} = JWK.sign(jwk, "message")
        assert {:ok, ^signature} = JWK.sign(ctx.jwk, "message")
      end
    end

    test "a JWK map's kid is used when no kid is given", ctx do
      assert {:ok, %JWK{kid: kid}} = JWK.new(public_jwk: ctx.public_map)
      assert kid == ctx.jwk.kid

      assert {:error, %InvalidField{field: :kid, value: "other"} = error} =
               JWK.new(public_jwk: ctx.public_map, kid: "other")

      assert Exception.message(error) =~ "must match the JWK's kid"

      assert {:error, %InvalidField{field: :kid, reason: :required}} =
               JWK.new(public_jwk: Map.delete(ctx.public_map, "kid"))

      assert {:error, %InvalidField{field: :public_jwk}} =
               JWK.new(public_jwk: %{"kty" => "RSA", "kid" => ctx.jwk.kid})
    end

    test "rejects a key that is malformed or not RSA", ctx do
      ec = JOSE.JWK.to_public(JOSE.JWK.generate_key({:ec, "P-256"}))
      {_type, ec_public_pem} = JOSE.JWK.to_pem(ec)
      {_type, ec_public_map} = JOSE.JWK.to_map(ec)

      for {field, value} <- [
            public_key_pem: "not-a-pem",
            public_key_pem: ec_public_pem,
            public_key_pem: ctx.jwk.private_key_pem,
            public_key_der: "garbage",
            public_key_der: 123,
            public_jwk: ec_public_map,
            public_jwk: %{"kty" => "RSA", "n" => 1},
            public_jwk: ctx.private_map,
            public_jwk: "map",
            private_key_der: "garbage",
            private_key_der: ctx.public_der,
            private_jwk: ctx.public_map,
            private_jwk: %{"kty" => "RSA"}
          ] do
        assert {:error, %InvalidField{struct: JWK, field: ^field, value: "[redacted]"}} =
                 JWK.new([{field, value}, {:kid, ctx.jwk.kid}])
      end
    end

    test "a key without a private key can't sign", ctx do
      jwk = JWK.new!(public_key_pem: ctx.public_pem, kid: ctx.jwk.kid)

      assert {:error, %InvalidField{struct: JWK, field: :private_key_pem, reason: :required}} =
               JWK.sign(jwk, "message")
    end

    test "inspect omits the private key", ctx do
      refute inspect(ctx.jwk) =~ "PRIVATE"
      assert inspect(ctx.jwk) =~ ctx.jwk.kid
    end
  end

  describe "to_jwks/1" do
    test "single JWK returns %{keys => [key]} with one entry" do
      jwk = JWK.generate()
      jwks = JWK.to_jwks(jwk)

      assert %{"keys" => [key]} = jwks
      assert key["kty"] == "RSA"
      assert key["kid"] == jwk.kid
      assert key["alg"] == "RS256"
      assert key["use"] == "sig"
    end

    test "list of JWKs returns matching count" do
      jwk1 = JWK.generate()
      jwk2 = JWK.generate()

      jwks = JWK.to_jwks([jwk1, jwk2])

      assert %{"keys" => keys} = jwks
      assert length(keys) == 2
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
  end
end
