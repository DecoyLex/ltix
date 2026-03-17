defmodule Ltix.JWK do
  @moduledoc """
  RSA key management for LTI tool authentication.

  Every LTI Advantage service call requires a signed JWT assertion. This module
  wraps an RSA private key and its key ID in a struct that is easy to persist
  (PEM string + kid) and converts to JWKS documents for platform consumption.

  ## Generating a key

      jwk = Ltix.JWK.generate()

  Store the struct fields (`private_key_pem` and `kid`) in your database or
  config, and pass the struct as `tool_jwk` in your `%Ltix.Registration{}`.

  ## Loading from storage

      {:ok, jwk} = Ltix.JWK.new(private_key_pem: pem, kid: kid)

  ## Building a JWKS endpoint response

      jwks = Ltix.JWK.to_jwks([current_jwk, previous_jwk])
      # => %{"keys" => [%{"kty" => "RSA", "kid" => "...", ...}, ...]}

  Include multiple keys during rotation so platforms can verify with either.

  """

  alias Ltix.AppConfig

  alias Ltix.Errors.Invalid.InvalidClaim

  @generate_schema Zoi.keyword(
                     key_size:
                       Zoi.integer(
                         description: """
                         RSA key size in bits (minimum 2048). The default can be overridden
                         by setting `config :ltix, :default_key_size`.
                         """
                       )
                       |> Zoi.min(2048)
                       |> Zoi.default(AppConfig.default_key_size())
                   )

  @enforce_keys [:private_key_pem, :kid]
  defstruct [:private_key_pem, :kid]

  @type t :: %__MODULE__{
          private_key_pem: String.t(),
          kid: String.t()
        }

  @doc """
  Generate an RSA key pair for LTI tool authentication.

  Returns a `%Ltix.JWK{}` struct. Pass it as `tool_jwk` in your
  registration, and persist `private_key_pem` and `kid` for later
  reconstruction via `new/1`.

  ## Examples

      jwk = Ltix.JWK.generate()
      jwk = Ltix.JWK.generate(key_size: 4096)

  ## Options

  #{Zoi.describe(@generate_schema)}
  """
  # [Sec §6.1](https://www.imsglobal.org/spec/security/v1p0/#platform-originating-messages)
  # RSA keys with RS256 algorithm
  # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
  # Each key identified by kid
  @spec generate(keyword()) :: t()
  def generate(opts \\ []) do
    opts = Zoi.parse!(@generate_schema, opts)

    jose_jwk = JOSE.JWK.generate_key({:rsa, opts[:key_size]})
    kid = JOSE.JWK.thumbprint(jose_jwk)
    {_kty, pem} = JOSE.JWK.to_pem(jose_jwk)

    %__MODULE__{private_key_pem: pem, kid: kid}
  end

  @doc """
  Construct a JWK from existing key material.

  For loading keys from storage (database, config, environment variable).
  Both `private_key_pem` and `kid` are required.

  ## Examples

      {:ok, jwk} = Ltix.JWK.new(private_key_pem: pem, kid: "my-key-id")

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(opts) when is_list(opts) do
    pem = Keyword.get(opts, :private_key_pem)
    kid = Keyword.get(opts, :kid)

    with :ok <- validate_kid(kid),
         :ok <- validate_pem(pem) do
      {:ok, %__MODULE__{private_key_pem: pem, kid: kid}}
    end
  end

  @doc """
  Build a JWKS (JSON Web Key Set) map from one or more JWKs.

  Strips private key material, so the output is safe for public endpoints.
  Accepts a single `%Ltix.JWK{}` or a list.

  ## Examples

      jwk = Ltix.JWK.generate()
      jwks = Ltix.JWK.to_jwks(jwk)
      [key] = jwks["keys"]
      key["kty"]
      #=> "RSA"
  """
  # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
  @spec to_jwks(t() | [t()]) :: map()
  def to_jwks(%__MODULE__{} = jwk), do: to_jwks([jwk])

  def to_jwks(jwks) when is_list(jwks) do
    keys =
      Enum.map(jwks, fn %__MODULE__{} = jwk ->
        jose_jwk = to_jose(jwk)

        {_kty, fields} =
          jose_jwk
          |> JOSE.JWK.to_public()
          |> JOSE.JWK.to_map()

        fields
      end)

    %{"keys" => keys}
  end

  @doc """
  Export the public key as a PEM string.

  Derives the public key from the private PEM. Useful for manual key
  exchange during platform registration setup.

  ## Examples

      jwk = Ltix.JWK.generate()
      public_pem = Ltix.JWK.to_public_key(jwk)
  """
  @spec to_public_key(t()) :: String.t()
  def to_public_key(%__MODULE__{private_key_pem: pem}) do
    {_kty, public_pem} =
      pem
      |> JOSE.JWK.from_pem()
      |> JOSE.JWK.to_public()
      |> JOSE.JWK.to_pem()

    public_pem
  end

  @doc false
  @spec to_jose(t()) :: JOSE.JWK.t()
  def to_jose(%__MODULE__{private_key_pem: pem, kid: kid}) do
    pem
    |> JOSE.JWK.from_pem()
    |> JOSE.JWK.merge(%{"kid" => kid, "alg" => "RS256", "use" => "sig"})
  end

  # --- Validation ---

  defp validate_kid(kid) when is_binary(kid) and byte_size(kid) > 0, do: :ok

  defp validate_kid(_) do
    {:error,
     InvalidClaim.exception(
       claim: "kid",
       value: nil,
       message: "kid must be a non-empty string",
       spec_ref: "Sec §6.3 (key identifier)"
     )}
  end

  defp validate_pem(pem) when is_binary(pem) do
    case :public_key.pem_decode(pem) do
      [] ->
        {:error,
         InvalidClaim.exception(
           claim: "private_key_pem",
           value: "***",
           message: "private_key_pem is not a valid PEM",
           spec_ref: "Sec §6.1 (RSA key)"
         )}

      entries ->
        validate_pem_entries(entries)
    end
  end

  defp validate_pem(_) do
    {:error,
     InvalidClaim.exception(
       claim: "private_key_pem",
       value: nil,
       message: "private_key_pem must be a binary",
       spec_ref: "Sec §6.1 (RSA key)"
     )}
  end

  defp validate_pem_entries(entries) do
    entry = List.first(entries)

    case :public_key.pem_entry_decode(entry) do
      {:RSAPrivateKey, _, _, _, _, _, _, _, _, _, _} ->
        :ok

      _ ->
        {:error,
         InvalidClaim.exception(
           claim: "private_key_pem",
           value: "***",
           message: "expected an RSA private key",
           spec_ref: "Sec §6.1 (RSA key)"
         )}
    end
  end
end
