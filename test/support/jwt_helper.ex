defmodule Ltix.Test.JWTHelper do
  @moduledoc """
  Generate RSA keys [Sec §6.1] and sign JWTs [Sec §5.1.2] for testing.

  Every test that needs a JWT uses this helper rather than static fixtures,
  ensuring tests are self-contained and key material is never accidentally committed.
  """

  @doc """
  Generate an RSA key pair for testing.

  Returns `{private_jwk, public_jwk, kid}` where:
  - `private_jwk` is a `JOSE.JWK` with the private key (for signing)
  - `public_jwk` is a `JOSE.JWK` with only the public key (for verification/JWKS)
  - `kid` is a unique key ID string [Sec §6.2]
  """
  @spec generate_rsa_key_pair() :: {JOSE.JWK.t(), JOSE.JWK.t(), String.t()}
  def generate_rsa_key_pair do
    kid = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    private_jwk = JOSE.JWK.generate_key({:rsa, 2048})

    # Add kid to the key fields
    private_jwk = JOSE.JWK.merge(private_jwk, %{"kid" => kid})
    public_jwk = JOSE.JWK.to_public(private_jwk)

    {private_jwk, public_jwk, kid}
  end

  @doc """
  Build a JWKS (JSON Web Key Set) map from a list of public JWKs.

  Returns a map in the format `%{"keys" => [...]}` per [Sec §6.3].
  """
  @spec build_jwks([JOSE.JWK.t()]) :: map()
  def build_jwks(public_keys) do
    keys =
      Enum.map(public_keys, fn jwk ->
        {_kty, fields} = JOSE.JWK.to_map(jwk)
        fields
      end)

    %{"keys" => keys}
  end

  @doc """
  Sign claims as a JWT with RS256 per [Sec §5.1.2; Sec §5.4].

  ## Options

  - `:kid` — Key ID to include in the JWT header [Sec §6.3]
  - `:alg` — Algorithm (default: `"RS256"`). Override for testing bad alg scenarios.
  """
  @spec mint_id_token(map(), JOSE.JWK.t(), keyword()) :: String.t()
  def mint_id_token(claims, private_jwk, opts \\ []) do
    kid = Keyword.get(opts, :kid)
    alg = Keyword.get(opts, :alg, "RS256")

    jws_fields =
      %{"alg" => alg}
      |> then(fn fields ->
        if kid, do: Map.put(fields, "kid", kid), else: fields
      end)

    jws = JOSE.JWS.from_map(jws_fields)
    jwt = JOSE.JWT.from_map(claims)

    {_meta, token} =
      JOSE.JWT.sign(private_jwk, jws, jwt)
      |> JOSE.JWS.compact()

    token
  end

  @doc """
  Return a complete, valid LtiResourceLinkRequest claim set per
  [Core §5.3] required claims + [Core §5.4] optional claims.

  Caller can override individual claims for negative tests.
  """
  @spec valid_lti_claims(map()) :: map()
  def valid_lti_claims(overrides \\ %{}) do
    now = System.system_time(:second)

    base = %{
      # OIDC standard claims [Sec §5.1.2]
      "iss" => "https://platform.example.com",
      "sub" => "user-12345",
      "aud" => "tool-client-id",
      "exp" => now + 3600,
      "iat" => now,
      "nonce" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false),
      # LTI required claims [Core §5.3]
      "https://purl.imsglobal.org/spec/lti/claim/message_type" => "LtiResourceLinkRequest",
      "https://purl.imsglobal.org/spec/lti/claim/version" => "1.3.0",
      "https://purl.imsglobal.org/spec/lti/claim/deployment_id" => "deployment-001",
      "https://purl.imsglobal.org/spec/lti/claim/target_link_uri" =>
        "https://tool.example.com/launch",
      "https://purl.imsglobal.org/spec/lti/claim/roles" => [
        "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"
      ],
      "https://purl.imsglobal.org/spec/lti/claim/resource_link" => %{
        "id" => "resource-link-001",
        "title" => "Example Assignment"
      }
    }

    Map.merge(base, overrides)
  end
end
