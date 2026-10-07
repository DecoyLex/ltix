defmodule Ltix.JWK do
  @moduledoc """
  RSA keys for LTI tool authentication.

  Every LTI Advantage service call requires a signed JWT assertion, and
  platforms verify it with the public keys your tool publishes. A JWK has a
  key ID and a public key, and a private key when it was made from one.

  ## Generating a key

      jwk = Ltix.JWK.generate()

  Store `kid`, `public_key_pem`, and `private_key_pem`, and encrypt the
  private key.

  ## Signing

  Load the private key and sign in your storage adapter's
  `c:Ltix.StorageAdapter.sign/3` callback.

      {:ok, jwk} = Ltix.JWK.new(private_key_pem: pem, kid: kid)
      Ltix.JWK.sign(jwk, message)

  ## Serving your key set endpoint

  Load the public keys and return them with `to_jwks/1`. The endpoint needs
  no private key.

      def jwks(conn, _params) do
        json(conn, Ltix.JWK.to_jwks(MyApp.Lti.list_public_jwks()))
      end

  Here `list_public_jwks/0` builds each JWK from what you stored.

      Ltix.JWK.new!(public_key_pem: pem, kid: kid)

  During a rotation, include the new key and the old one so platforms can
  verify with either.

  For a key in a key management service, build the JWK from the public key
  the service returns, as a PEM, a DER binary, or a JWK map.

  """

  alias Ltix.AppConfig
  alias Ltix.Errors
  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.Options

  @generate_schema Zoi.keyword(
                     [
                       key_size:
                         Zoi.integer(
                           description: """
                           RSA key size in bits (minimum 2048). The default can be overridden
                           by setting `config :ltix, :default_key_size`.
                           """
                         )
                         |> Zoi.min(2048)
                     ],
                     unrecognized_keys: :error
                   )

  @key_formats [
    public_key_pem: {:pem, :public},
    public_key_der: {:der, :public},
    public_jwk: {:jwk, :public},
    private_key_pem: {:pem, :private},
    private_key_der: {:der, :private},
    private_jwk: {:jwk, :private}
  ]
  @key_fields Keyword.keys(@key_formats)

  @derive {Inspect, except: [:private_key_pem]}
  @enforce_keys [:kid, :public_key_pem]
  defstruct [:kid, :public_key_pem, :private_key_pem]

  @type t :: %__MODULE__{
          kid: String.t(),
          public_key_pem: String.t(),
          private_key_pem: String.t() | nil
        }

  @doc """
  Generate an RSA key pair for LTI tool authentication.

  Returns a `%Ltix.JWK{}` struct. Persist `kid` and the key PEMs to build
  the JWK again with `new/1`.

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
    opts = Options.parse!(opts, @generate_schema)

    key_size = Keyword.get_lazy(opts, :key_size, &AppConfig.default_key_size/0)
    jose_jwk = JOSE.JWK.generate_key({:rsa, key_size})

    %__MODULE__{
      kid: JOSE.JWK.thumbprint(jose_jwk),
      public_key_pem: pem(JOSE.JWK.to_public(jose_jwk)),
      private_key_pem: pem(jose_jwk)
    }
  end

  @doc """
  Construct a JWK from existing key material.

  Takes a keyword list or an atom-keyed map with `:kid` and one key. Unknown
  fields are rejected. A JWK made from a public key has no private key, so
  it can't sign.

  ## Fields

    * `:kid` - the key ID. Optional with `:public_jwk` or `:private_jwk` when
      the map has a `"kid"`, which a `:kid` given with it has to match.
    * `:public_key_pem` - an RSA public key as a PEM string
    * `:public_key_der` - an RSA public key as a DER binary
    * `:public_jwk` - an RSA public key as a string-keyed JWK map
    * `:private_key_pem` - an RSA private key as an unencrypted PEM string
    * `:private_key_der` - an RSA private key as a DER binary
    * `:private_jwk` - an RSA private key as a string-keyed JWK map

  ## Examples

      {:ok, jwk} = Ltix.JWK.new(private_key_pem: pem, kid: "my-key-id")
      {:ok, jwk} = Ltix.JWK.new(public_key_pem: public_pem, kid: "my-key-id")

  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    jwk_kid = jwk_kid(attrs)
    kid = if is_nil(attrs[:kid]), do: jwk_kid, else: attrs[:kid]

    {key_error, public_key_pem, private_key_pem} =
      case parse_key(attrs) do
        {:ok, {public_key_pem, private_key_pem}} -> {nil, public_key_pem, private_key_pem}
        {:error, error} -> {error, nil, nil}
      end

    errors =
      InvalidField.unknown_fields(__MODULE__, attrs, [:kid | @key_fields]) ++
        [key_error, validate_kid(kid, jwk_kid)]

    with :ok <- Errors.collect(errors) do
      {:ok,
       %__MODULE__{kid: kid, public_key_pem: public_key_pem, private_key_pem: private_key_pem}}
    end
  end

  @doc """
  Same as `new/1`, but returns the JWK or raises the error.

  ## Examples

      jwk = Ltix.JWK.new!(private_key_pem: pem, kid: "my-key-id")
  """
  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, jwk} -> jwk
      {:error, error} -> raise error
    end
  end

  @doc """
  Build a JWKS (JSON Web Key Set) map from one or more JWKs.

  The map has only public keys, so it is safe for public endpoints.
  Accepts a single `%Ltix.JWK{}` or a list.

  ## Examples

      def jwks(conn, _params) do
        json(conn, Ltix.JWK.to_jwks(MyApp.Lti.list_public_jwks()))
      end
  """
  # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
  @spec to_jwks(t() | [t()]) :: map()
  def to_jwks(%__MODULE__{} = jwk), do: to_jwks([jwk])

  def to_jwks(jwks) when is_list(jwks) do
    keys =
      Enum.map(jwks, fn %__MODULE__{} = jwk ->
        {_kty, fields} = JOSE.JWK.to_map(to_jose(jwk))
        fields
      end)

    %{"keys" => keys}
  end

  @doc """
  Export the public key as a PEM string.

  Useful for manual key exchange during platform registration setup.

  ## Examples

      jwk = Ltix.JWK.generate()
      public_pem = Ltix.JWK.to_public_key(jwk)
  """
  @spec to_public_key(t()) :: String.t()
  def to_public_key(%__MODULE__{public_key_pem: pem}), do: pem

  @doc """
  Sign a message with RS256, as `c:Ltix.StorageAdapter.sign/3` requires.

  Returns an error for a JWK without a private key.

  ## Examples

      iex> jwk = Ltix.JWK.generate(key_size: 2048)
      iex> {:ok, signature} = Ltix.JWK.sign(jwk, "message")
      iex> byte_size(signature)
      256
  """
  # [Sec §6.1](https://www.imsglobal.org/spec/security/v1p0/#platform-originating-messages)
  @spec sign(t(), binary()) :: {:ok, binary()} | {:error, Exception.t()}
  def sign(%__MODULE__{private_key_pem: nil}, message) when is_binary(message) do
    {:error, required(:private_key_pem)}
  end

  def sign(%__MODULE__{private_key_pem: pem}, message) when is_binary(message) do
    [entry | _] = :public_key.pem_decode(pem)
    {:ok, :public_key.sign(message, :sha256, :public_key.pem_entry_decode(entry))}
  end

  @doc false
  @spec to_jose(t()) :: JOSE.JWK.t()
  def to_jose(%__MODULE__{public_key_pem: pem, kid: kid}) do
    pem
    |> JOSE.JWK.from_pem()
    |> JOSE.JWK.merge(%{"kid" => kid, "alg" => "RS256", "use" => "sig"})
  end

  defp pem(jose_jwk) do
    {_kty, pem} = JOSE.JWK.to_pem(jose_jwk)
    pem
  end

  # --- Validation ---

  # Returns `{:ok, {public_key_pem, private_key_pem}}` for the one key given.
  # Key material is left out of the errors.
  # [Sec §6.1](https://www.imsglobal.org/spec/security/v1p0/#platform-originating-messages)
  defp parse_key(attrs) do
    case for field <- @key_fields, attrs[field] != nil, do: field do
      [] ->
        reason = "one of #{Enum.join(@key_fields, ", ")} is required"
        {:error, invalid(:public_key_pem, nil, reason, "Sec §6.1 (RSA key)")}

      [field] ->
        {format, kind} = @key_formats[field]

        with {:ok, jose_jwk} <- decode_key(format, attrs[field]),
             {:ok, private_key_pem} <- private_key_pem(format, kind, attrs[field], jose_jwk) do
          {:ok, {pem(JOSE.JWK.to_public(jose_jwk)), private_key_pem}}
        else
          {:error, reason} -> {:error, invalid_key(field, reason)}
          :error -> {:error, invalid_key(field, "expected an RSA #{kind} key")}
        end

      [_first, field | _rest] ->
        {:error, invalid_key(field, "only one key can be given")}
    end
  rescue
    # JOSE raises on malformed key data.
    _error ->
      field = Enum.find(@key_fields, &(attrs[&1] != nil))
      {_format, kind} = @key_formats[field]
      {:error, invalid_key(field, "expected an RSA #{kind} key")}
  end

  defp decode_key(:pem, pem) when is_binary(pem) do
    case :public_key.pem_decode(pem) do
      [] -> {:error, "must be a PEM"}
      [{_type, _der, :not_encrypted} | _] -> jose_key(JOSE.JWK.from_pem(pem))
      _encrypted -> {:error, "must not be encrypted"}
    end
  end

  defp decode_key(:der, der) when is_binary(der), do: jose_key(JOSE.JWK.from_der(der))
  defp decode_key(:jwk, map) when is_map(map), do: jose_key(JOSE.JWK.from_map(map))
  defp decode_key(:jwk, _value), do: {:error, "must be a map"}
  defp decode_key(_format, _value), do: {:error, "must be a binary"}

  defp jose_key(%JOSE.JWK{} = jose_jwk), do: {:ok, jose_jwk}
  defp jose_key(_other), do: :error

  # Checks that the key is an RSA key of the kind the field is for. A PEM the
  # caller gave is kept as given.
  defp private_key_pem(format, kind, value, jose_jwk) do
    {_kty, record} = JOSE.JWK.to_key(jose_jwk)

    case {kind, elem(record, 0), format} do
      {:public, :RSAPublicKey, _format} -> {:ok, nil}
      {:private, :RSAPrivateKey, :pem} -> {:ok, value}
      {:private, :RSAPrivateKey, _format} -> {:ok, pem(jose_jwk)}
      _other -> :error
    end
  end

  defp jwk_kid(attrs) do
    case attrs[:public_jwk] || attrs[:private_jwk] do
      %{"kid" => kid} when is_binary(kid) and kid != "" -> kid
      _other -> nil
    end
  end

  # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
  defp validate_kid(nil, _jwk_kid), do: required(:kid)

  defp validate_kid(kid, jwk_kid) when is_binary(kid) and kid != "" and jwk_kid in [nil, kid],
    do: nil

  defp validate_kid(kid, jwk_kid) when is_binary(kid) and kid != "" and is_binary(jwk_kid) do
    invalid(:kid, kid, "must match the JWK's kid", "Sec §6.3 (key identifier)")
  end

  defp validate_kid(kid, _jwk_kid) do
    invalid(:kid, kid, "must be a non-empty string", "Sec §6.3 (key identifier)")
  end

  defp invalid_key(field, reason),
    do: invalid(field, "[redacted]", reason, "Sec §6.1 (RSA key)")

  defp required(field), do: InvalidField.required(__MODULE__, field)

  defp invalid(field, value, reason, spec_ref),
    do: InvalidField.invalid(__MODULE__, field, value, reason, spec_ref)
end
