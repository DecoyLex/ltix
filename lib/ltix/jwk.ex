defmodule Ltix.JWK do
  @generate_key_pair_schema Zoi.keyword(
                              key_size:
                                Zoi.integer(description: "RSA key size in bits (minimum 2048).")
                                |> Zoi.min(2048)
                                |> Zoi.default(2048)
                            )

  @moduledoc """
  RSA key pair generation and JWKS document building for LTI tool authentication.

  Every LTI Advantage service call requires a signed JWT assertion. This module
  generates the key pairs used for signing and builds the JWKS documents that
  platforms use to verify signatures.

  ## Generating keys

      {private, public} = Ltix.JWK.generate_key_pair()

  Store the private key in your `%Ltix.Registration{}` as `tool_jwk`. Serve
  the public key from your JWKS endpoint.

  ## Building a JWKS endpoint response

      jwks = Ltix.JWK.to_jwks([current_public, previous_public])
      # => %{"keys" => [%{"kty" => "RSA", "kid" => "...", ...}, ...]}

  Include multiple keys during rotation so platforms can verify with either.

  ## Options

  #{Zoi.describe(@generate_key_pair_schema)}
  """

  @doc """
  Generate an RSA key pair for LTI tool authentication.

  Returns `{private_jwk, public_jwk}`. The private key is suitable for
  `registration.tool_jwk`. The public key goes on your JWKS endpoint.

  Both keys share the same `kid` and include `alg: RS256` and `use: sig`.

  ## Examples

      {private, public} = Ltix.JWK.generate_key_pair()
      {private, public} = Ltix.JWK.generate_key_pair(key_size: 4096)
  """
  # [Sec §6.1](https://www.imsglobal.org/spec/security/v1p0/#platform-originating-messages)
  # RSA keys with RS256 algorithm
  # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
  # Each key identified by kid
  @spec generate_key_pair(keyword()) :: {JOSE.JWK.t(), JOSE.JWK.t()}
  def generate_key_pair(opts \\ []) do
    opts = Zoi.parse!(@generate_key_pair_schema, opts)
    key_size = Keyword.fetch!(opts, :key_size)

    kid = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

    private_jwk =
      {:rsa, key_size}
      |> JOSE.JWK.generate_key()
      |> JOSE.JWK.merge(%{"kid" => kid, "alg" => "RS256", "use" => "sig"})

    public_jwk = JOSE.JWK.to_public(private_jwk)

    {private_jwk, public_jwk}
  end

  @doc """
  Build a JWKS (JSON Web Key Set) map from a list of public JWKs.

  Strips private key material from any key that still contains it, so it's
  safe to pass private keys by accident.

  ## Examples

      {_private, public} = Ltix.JWK.generate_key_pair()
      jwks = Ltix.JWK.to_jwks([public])
      [key] = jwks["keys"]
      key["kty"]
      #=> "RSA"
  """
  # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
  @spec to_jwks([JOSE.JWK.t()]) :: map()
  def to_jwks(public_keys) when is_list(public_keys) do
    keys =
      Enum.map(public_keys, fn jwk ->
        {_kty, fields} =
          jwk
          |> JOSE.JWK.to_public()
          |> JOSE.JWK.to_map()

        fields
      end)

    %{"keys" => keys}
  end
end
