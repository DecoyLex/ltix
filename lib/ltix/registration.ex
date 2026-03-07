defmodule Ltix.Registration do
  @moduledoc """
  Everything the tool knows about a registered platform, established
  out-of-band before any launch occurs.

  Multiple deployments on a given platform may share the same `client_id`.
  """

  alias Ltix.Errors.Invalid.InvalidClaim

  defstruct [
    :issuer,
    :client_id,
    :auth_endpoint,
    :jwks_uri,
    :token_endpoint
  ]

  @type t :: %__MODULE__{
          issuer: String.t(),
          client_id: String.t(),
          auth_endpoint: String.t(),
          jwks_uri: String.t(),
          token_endpoint: String.t() | nil
        }

  @doc """
  Create a new registration with validation.

  ## Validation rules

  - `issuer` — HTTPS URL with no query or fragment
  - `client_id` — non-empty string
  - `auth_endpoint` — HTTPS URL
  - `jwks_uri` — HTTPS URL
  - `token_endpoint` — HTTPS URL (when present)

  ## Examples

      iex> Ltix.Registration.new(%{
      ...>   issuer: "https://platform.example.com",
      ...>   client_id: "tool-123",
      ...>   auth_endpoint: "https://platform.example.com/auth",
      ...>   jwks_uri: "https://platform.example.com/.well-known/jwks.json"
      ...> })
      {:ok, %Ltix.Registration{
        issuer: "https://platform.example.com",
        client_id: "tool-123",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri: "https://platform.example.com/.well-known/jwks.json",
        token_endpoint: nil
      }}

      Ltix.Registration.new(%{issuer: "http://not-https.example.com", ...})
      #=> {:error, %Ltix.Errors.Invalid.InvalidClaim{claim: "issuer"}}

  """
  @spec new(map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_issuer(attrs[:issuer]),
         :ok <- validate_client_id(attrs[:client_id]),
         :ok <- validate_https_url(attrs[:auth_endpoint], "auth_endpoint"),
         :ok <- validate_https_url(attrs[:jwks_uri], "jwks_uri"),
         :ok <- validate_optional_https_url(attrs[:token_endpoint], "token_endpoint") do
      {:ok,
       %__MODULE__{
         issuer: attrs[:issuer],
         client_id: attrs[:client_id],
         auth_endpoint: attrs[:auth_endpoint],
         jwks_uri: attrs[:jwks_uri],
         token_endpoint: attrs[:token_endpoint]
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
             spec_ref: "Sec §5.1.2 (no query component)"
           )}

        uri.fragment != nil ->
          {:error,
           InvalidClaim.exception(
             claim: "issuer",
             value: issuer,
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
         spec_ref: "Sec §3 (HTTPS required)"
       )}
    end
  end

  defp validate_https_url(_, field) do
    {:error,
     InvalidClaim.exception(
       claim: field,
       value: nil,
       spec_ref: "Sec §3 (HTTPS required)"
     )}
  end

  defp validate_optional_https_url(nil, _field), do: :ok
  defp validate_optional_https_url(url, field), do: validate_https_url(url, field)
end
