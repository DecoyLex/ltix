defmodule Ltix.Registration do
  @moduledoc """
  Everything the tool knows about a registered platform, established
  out-of-band before any launch occurs.

  A registration captures the values exchanged during out-of-band setup
  between the tool and platform. Multiple deployments on a given platform
  may share the same `client_id`.

  ## Fields

    * `:issuer` — HTTPS URL identifying the platform (no query or fragment)
    * `:client_id` — OAuth client ID assigned by the platform
    * `:auth_endpoint` — HTTPS URL for the OIDC authorization endpoint
    * `:jwks_uri` — HTTPS URL where the platform publishes its public keys
    * `:token_endpoint` — HTTPS URL for OAuth token requests (required for
      Advantage services; `nil` if not using them)
    * `:tool_jwk` — the tool's private signing key (`Ltix.JWK.t()`),
      used to sign client assertion JWTs. Generate one with
      `Ltix.JWK.generate/1` and serve the matching public key
      from your JWKS endpoint.

  ## Examples

      {:ok, reg} = Ltix.Registration.new(%{
        issuer: "https://canvas.example.edu",
        client_id: "10000000000042",
        auth_endpoint: "https://canvas.example.edu/api/lti/authorize_redirect",
        jwks_uri: "https://canvas.example.edu/api/lti/security/jwks",
        token_endpoint: "https://canvas.example.edu/login/oauth2/token",
        tool_jwk: tool_private_key
      })
  """

  alias Ltix.Errors
  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.JWK

  @fields [:issuer, :client_id, :auth_endpoint, :jwks_uri, :token_endpoint, :tool_jwk]

  @enforce_keys [:issuer, :client_id, :auth_endpoint, :jwks_uri, :tool_jwk]
  defstruct @fields

  @type t :: %__MODULE__{
          issuer: String.t(),
          client_id: String.t(),
          auth_endpoint: String.t(),
          jwks_uri: String.t(),
          token_endpoint: String.t() | nil,
          tool_jwk: Ltix.JWK.t()
        }

  @doc """
  Create a new registration with validation from a keyword list or an
  atom-keyed map. Unknown fields are rejected.

  ## Validation rules

  - `issuer` — HTTPS URL with no query or fragment
  - `client_id` — non-empty string
  - `auth_endpoint` — HTTPS URL
  - `jwks_uri` — HTTPS URL
  - `token_endpoint` — HTTPS URL (when present)
  - `tool_jwk` — `Ltix.JWK.t()` (the tool's private signing key for this registration)

  ## Examples

      iex> {:ok, reg} = Ltix.Registration.new(%{
      ...>   issuer: "https://platform.example.com",
      ...>   client_id: "tool-123",
      ...>   auth_endpoint: "https://platform.example.com/auth",
      ...>   jwks_uri: "https://platform.example.com/.well-known/jwks.json",
      ...>   tool_jwk: Ltix.JWK.generate()
      ...> })
      iex> reg.issuer
      "https://platform.example.com"

  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    errors =
      InvalidField.unknown_fields(__MODULE__, attrs, @fields) ++
        [
          validate_issuer(attrs[:issuer]),
          validate_client_id(attrs[:client_id]),
          validate_https_url(:auth_endpoint, attrs[:auth_endpoint]),
          validate_https_url(:jwks_uri, attrs[:jwks_uri]),
          validate_optional_https_url(:token_endpoint, attrs[:token_endpoint]),
          validate_tool_jwk(attrs[:tool_jwk])
        ]

    case Errors.collect(errors) do
      :ok -> {:ok, struct!(__MODULE__, attrs)}
      {:error, _error} = error -> error
    end
  end

  @doc """
  Same as `new/1`, but returns the registration or raises the error.

  ## Examples

      iex> registration = Ltix.Registration.new!(
      ...>   issuer: "https://platform.example.com",
      ...>   client_id: "tool-123",
      ...>   auth_endpoint: "https://platform.example.com/auth",
      ...>   jwks_uri: "https://platform.example.com/.well-known/jwks.json",
      ...>   tool_jwk: Ltix.JWK.generate()
      ...> )
      iex> registration.client_id
      "tool-123"
  """
  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, registration} -> registration
      {:error, error} -> raise error
    end
  end

  # [Sec §5.1.2](https://www.imsglobal.org/spec/security/v1p0/#id-token):
  # "The `iss` value is a case-sensitive URL using the HTTPS scheme that contains:
  # scheme, host; and, optionally, port number, and path components; and, no query
  # or fragment components."
  defp validate_issuer(issuer) do
    case validate_https_url(:issuer, issuer) do
      nil -> validate_issuer_components(issuer, URI.parse(issuer))
      error -> error
    end
  end

  defp validate_issuer_components(issuer, %URI{query: query}) when query != nil do
    invalid(
      :issuer,
      issuer,
      "must not include a query component",
      "Sec §5.1.2 (no query component)"
    )
  end

  defp validate_issuer_components(issuer, %URI{fragment: fragment}) when fragment != nil do
    invalid(
      :issuer,
      issuer,
      "must not include a fragment component",
      "Sec §5.1.2 (no fragment component)"
    )
  end

  defp validate_issuer_components(_issuer, _uri), do: nil

  # [Sec §5.1.1.2](https://www.imsglobal.org/spec/security/v1p0/#step-2-authentication-request)
  defp validate_client_id(nil), do: required(:client_id)
  defp validate_client_id(client_id) when is_binary(client_id) and client_id != "", do: nil

  defp validate_client_id(client_id) do
    invalid(:client_id, client_id, "must be a non-empty string", "Sec §5.1.1.2")
  end

  # [Sec §3](https://www.imsglobal.org/spec/security/v1p0/#transport-security)
  defp validate_https_url(field, nil), do: required(field)

  defp validate_https_url(field, url) do
    if https_url?(url),
      do: nil,
      else: invalid(field, url, "must be an HTTPS URL", "Sec §3 (HTTPS required)")
  end

  defp validate_optional_https_url(_field, nil), do: nil
  defp validate_optional_https_url(field, url), do: validate_https_url(field, url)

  defp https_url?(url) when is_binary(url) do
    uri = URI.parse(url)
    uri.scheme == "https" and is_binary(uri.host) and uri.host != ""
  end

  defp https_url?(_url), do: false

  # [Sec §7.2](https://www.imsglobal.org/spec/security/v1p0/#h_key-management):
  # "A system SHOULD NOT use a single key pair to secure message signing for more
  # than one system." Keys are per-registration, exchanged during setup [Sec §6].
  defp validate_tool_jwk(nil), do: required(:tool_jwk)
  defp validate_tool_jwk(%JWK{}), do: nil

  defp validate_tool_jwk(tool_jwk) do
    invalid(
      :tool_jwk,
      tool_jwk,
      "must be an %Ltix.JWK{} struct",
      "Sec §7.2 (per-registration key)"
    )
  end

  defp required(field), do: InvalidField.required(__MODULE__, field)

  defp invalid(field, value, reason, spec_ref),
    do: InvalidField.invalid(__MODULE__, field, value, reason, spec_ref)
end

defimpl Ltix.Registerable, for: Ltix.Registration do
  def to_registration(registration), do: Ltix.Registration.new(Map.from_struct(registration))
end
