defmodule Ltix.Registration do
  @moduledoc """
  Everything the tool stores about a registered platform, established
  out-of-band before any launch occurs.

  A registration contains the values exchanged during out-of-band setup
  between the tool and platform. Multiple deployments on a given platform
  may share the same `client_id`.

  ## Fields

    * `:issuer` - HTTPS URL identifying the platform (no query or fragment)
    * `:client_id` - OAuth client ID assigned by the platform
    * `:auth_endpoint` - HTTPS URL for the OIDC authorization endpoint
    * `:jwks_uri` - HTTPS URL where the platform publishes its public keys
    * `:token_endpoint` - HTTPS URL for OAuth token requests (required for
      Advantage services, `nil` if not using them)
    * `:audience` - the audience the platform expects in token requests,
      when it gives you one that differs from the token endpoint. Defaults
      to the token endpoint.

  ## Examples

      {:ok, reg} = Ltix.Registration.new(%{
        issuer: "https://canvas.example.edu",
        client_id: "10000000000042",
        auth_endpoint: "https://canvas.example.edu/api/lti/authorize_redirect",
        jwks_uri: "https://canvas.example.edu/api/lti/security/jwks",
        token_endpoint: "https://canvas.example.edu/login/oauth2/token"
      })
  """

  alias Ltix.Errors
  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.HTTP

  @fields [:issuer, :client_id, :auth_endpoint, :jwks_uri, :token_endpoint, :audience]

  @enforce_keys [:issuer, :client_id, :auth_endpoint, :jwks_uri]
  defstruct @fields

  @type t :: %__MODULE__{
          issuer: String.t(),
          client_id: String.t(),
          auth_endpoint: String.t(),
          jwks_uri: String.t(),
          token_endpoint: String.t() | nil,
          audience: String.t() | nil
        }

  @doc """
  Create a new registration with validation from a keyword list or an
  atom-keyed map. Unknown fields are rejected.

  ## Validation rules

  - `issuer` - HTTPS URL with no query or fragment
  - `client_id` - non-empty string
  - `auth_endpoint` - HTTPS URL
  - `jwks_uri` - HTTPS URL
  - `token_endpoint` - HTTPS URL (when present)
  - `audience` - non-empty string, and a URI if it includes a colon (when present)

  HTTPS URLs must be absolute and must not include a userinfo component (RFC 3986 §3.2.1).
  HTTP URLs are accepted for platforms on a loopback or local host, such as
  `http://localhost:8080`.

  ## Examples

      iex> {:ok, reg} = Ltix.Registration.new(%{
      ...>   issuer: "https://platform.example.com",
      ...>   client_id: "tool-123",
      ...>   auth_endpoint: "https://platform.example.com/auth",
      ...>   jwks_uri: "https://platform.example.com/.well-known/jwks.json"
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
          validate_audience(attrs[:audience])
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
      ...>   jwks_uri: "https://platform.example.com/.well-known/jwks.json"
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

  # [Sec §5.1.2](https://www.imsglobal.org/spec/security/v1p0/#id-token)
  # "The `iss` value is a case-sensitive URL using the HTTPS scheme that contains:
  # scheme, host; and, optionally, port number, and path components; and, no query
  # or fragment components."
  defp validate_issuer(nil), do: required(:issuer)

  defp validate_issuer(issuer) do
    case HTTP.validate_url(issuer) do
      {:ok, uri} -> validate_issuer_components(issuer, uri)
      {:error, _error} -> not_https_url(:issuer, issuer)
    end
  end

  defp validate_issuer_components(issuer, %URI{query: query}) when query != nil do
    invalid(
      :issuer,
      issuer,
      "must not include a query component"
    )
  end

  defp validate_issuer_components(issuer, %URI{fragment: fragment}) when fragment != nil do
    invalid(
      :issuer,
      issuer,
      "must not include a fragment component"
    )
  end

  defp validate_issuer_components(_issuer, _uri), do: nil

  # [Sec §5.1.1.2](https://www.imsglobal.org/spec/security/v1p0/#step-2-authentication-request)
  defp validate_client_id(nil), do: required(:client_id)
  defp validate_client_id(client_id) when is_binary(client_id) and client_id != "", do: nil

  defp validate_client_id(client_id) do
    invalid(:client_id, client_id, "must be a non-empty string")
  end

  # [Sec §3](https://www.imsglobal.org/spec/security/v1p0/#transport-security)
  defp validate_https_url(field, nil), do: required(field)

  defp validate_https_url(field, url) do
    case HTTP.validate_url(url) do
      {:ok, _uri} -> nil
      {:error, _error} -> not_https_url(field, url)
    end
  end

  defp not_https_url(field, url),
    do: invalid(field, url, "must be an absolute HTTPS URL")

  defp validate_optional_https_url(_field, nil), do: nil
  defp validate_optional_https_url(field, url), do: validate_https_url(field, url)

  # [Sec §4.1.1](https://www.imsglobal.org/spec/security/v1p0/#using-json-web-tokens-with-oauth-2-0-client-credentials-grant)
  # The audience is a StringOrURI.
  # [RFC 7519 §2](https://www.rfc-editor.org/rfc/rfc7519#section-2)
  defp validate_audience(nil), do: nil

  defp validate_audience(audience) when is_binary(audience) and audience != "" do
    if String.contains?(audience, ":") &&
         !match?({:ok, %URI{scheme: scheme}} when scheme != nil, URI.new(audience)) do
      invalid(:audience, audience, "must be a URI when it includes a colon")
    end
  end

  defp validate_audience(audience) do
    invalid(:audience, audience, "must be a non-empty string")
  end

  defp required(field), do: InvalidField.required(__MODULE__, field)

  defp invalid(field, value, reason), do: InvalidField.invalid(__MODULE__, field, value, reason)
end

defimpl Ltix.Registerable, for: Ltix.Registration do
  def to_registration(registration), do: Ltix.Registration.new(Map.from_struct(registration))
end
