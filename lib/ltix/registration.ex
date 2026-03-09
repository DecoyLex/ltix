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
    * `:tool_jwk` — the tool's private signing key (`JOSE.JWK.t()`),
      used to sign client assertion JWTs. Generate one with
      `Ltix.JWK.generate_key_pair/1` and serve the matching public key
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

  alias Ltix.Errors.Invalid.InvalidClaim

  defstruct [
    :issuer,
    :client_id,
    :auth_endpoint,
    :jwks_uri,
    :token_endpoint,
    :tool_jwk
  ]

  @type t :: %__MODULE__{
          issuer: String.t(),
          client_id: String.t(),
          auth_endpoint: String.t(),
          jwks_uri: String.t(),
          token_endpoint: String.t() | nil,
          tool_jwk: JOSE.JWK.t()
        }

  @doc """
  Create a new registration with validation.

  ## Validation rules

  - `issuer` — HTTPS URL with no query or fragment
  - `client_id` — non-empty string
  - `auth_endpoint` — HTTPS URL
  - `jwks_uri` — HTTPS URL
  - `token_endpoint` — HTTPS URL (when present)
  - `tool_jwk` — `JOSE.JWK.t()` (the tool's private signing key for this registration)

  ## Examples

      iex> {:ok, reg} = Ltix.Registration.new(%{
      ...>   issuer: "https://platform.example.com",
      ...>   client_id: "tool-123",
      ...>   auth_endpoint: "https://platform.example.com/auth",
      ...>   jwks_uri: "https://platform.example.com/.well-known/jwks.json",
      ...>   tool_jwk: elem(Ltix.JWK.generate_key_pair(), 0)
      ...> })
      iex> reg.issuer
      "https://platform.example.com"

  """
  @spec new(map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_issuer(attrs[:issuer]),
         :ok <- validate_client_id(attrs[:client_id]),
         :ok <- validate_https_url(attrs[:auth_endpoint], "auth_endpoint"),
         :ok <- validate_https_url(attrs[:jwks_uri], "jwks_uri"),
         :ok <- validate_optional_https_url(attrs[:token_endpoint], "token_endpoint"),
         :ok <- validate_tool_jwk(attrs[:tool_jwk]) do
      {:ok,
       %__MODULE__{
         issuer: attrs[:issuer],
         client_id: attrs[:client_id],
         auth_endpoint: attrs[:auth_endpoint],
         jwks_uri: attrs[:jwks_uri],
         token_endpoint: attrs[:token_endpoint],
         tool_jwk: attrs[:tool_jwk]
       }}
    end
  end

  # [Sec §5.1.2](https://www.imsglobal.org/spec/security/v1p0/#id-token):
  # "The `iss` value is a case-sensitive URL using the HTTPS scheme that contains:
  # scheme, host; and, optionally, port number, and path components; and, no query
  # or fragment components."
  defp validate_issuer(issuer) do
    with :ok <- validate_https_url(issuer, "issuer") do
      uri = URI.parse(issuer)

      cond do
        uri.query != nil ->
          {:error,
           InvalidClaim.exception(
             claim: "issuer",
             value: issuer,
             message: "issuer must not include a query component",
             spec_ref: "Sec §5.1.2 (no query component)"
           )}

        uri.fragment != nil ->
          {:error,
           InvalidClaim.exception(
             claim: "issuer",
             value: issuer,
             message: "issuer must not include a fragment component",
             spec_ref: "Sec §5.1.2 (no fragment component)"
           )}

        true ->
          :ok
      end
    end
  end

  defp validate_client_id(client_id) when is_binary(client_id) and byte_size(client_id) > 0,
    do: :ok

  defp validate_client_id(_) do
    {:error,
     InvalidClaim.exception(
       claim: "client_id",
       value: nil,
       message: "client_id must be a non-empty string",
       spec_ref: "Sec §5.1.1.2"
     )}
  end

  defp validate_https_url(url, field) when is_binary(url) do
    uri = URI.parse(url)

    if uri.scheme == "https" and is_binary(uri.host) and uri.host != "" do
      :ok
    else
      {:error,
       InvalidClaim.exception(
         claim: field,
         value: url,
         message: "#{field} must be a valid HTTPS URL",
         spec_ref: "Sec §3 (HTTPS required)"
       )}
    end
  end

  defp validate_https_url(_, field) do
    {:error,
     InvalidClaim.exception(
       claim: field,
       value: nil,
       message: "#{field} must be a valid HTTPS URL",
       spec_ref: "Sec §3 (HTTPS required)"
     )}
  end

  defp validate_optional_https_url(nil, _field), do: :ok
  defp validate_optional_https_url(url, field), do: validate_https_url(url, field)

  # [Sec §7.2](https://www.imsglobal.org/spec/security/v1p0/#h_key-management):
  # "A system SHOULD NOT use a single key pair to secure message signing for more
  # than one system." Keys are per-registration, exchanged during setup [Sec §6].
  defp validate_tool_jwk(%JOSE.JWK{}), do: :ok

  defp validate_tool_jwk(_) do
    {:error,
     InvalidClaim.exception(
       claim: "tool_jwk",
       value: nil,
       message: "tool_jwk must be a valid JWK",
       spec_ref: "Sec §7.2 (per-registration key)"
     )}
  end
end
