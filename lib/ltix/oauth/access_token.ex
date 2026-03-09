defmodule Ltix.OAuth.AccessToken do
  @moduledoc """
  OAuth 2.0 access token response.

  A cacheable struct holding the parsed token data from a platform's token
  endpoint. Host apps can store this and reuse it across contexts via
  `Ltix.OAuth.Client.from_access_token/2`.

  ## Examples

      iex> {:ok, token} = Ltix.OAuth.AccessToken.from_response(
      ...>   %{
      ...>     "access_token" => "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9",
      ...>     "token_type" => "Bearer",
      ...>     "expires_in" => 3600,
      ...>     "scope" => "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"
      ...>   },
      ...>   now: ~U[2025-01-01 00:00:00Z]
      ...> )
      iex> token.access_token
      "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9"
      iex> token.token_type
      "bearer"
      iex> token.granted_scopes
      ["https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"]
      iex> token.expires_at
      ~U[2025-01-01 01:00:00Z]
  """

  alias Ltix.Errors.Invalid.MalformedResponse

  defstruct [:access_token, :token_type, :granted_scopes, :expires_at]

  @type t :: %__MODULE__{
          access_token: String.t(),
          token_type: String.t(),
          granted_scopes: [String.t()],
          expires_at: DateTime.t()
        }

  @doc """
  Parse an access token from a token endpoint response body.

  ## Options

    * `:requested_scopes` - list of scope strings that were requested, used
      as fallback when the response omits `"scope"`.
    * `:now` - override current time (default: `DateTime.utc_now/0`).
  """
  # [Sec §4.1](https://www.imsglobal.org/spec/security/v1p0/#using-oauth-2-0-client-credentials-grant)
  # RFC 6749 §5.1 — successful access token response
  @spec from_response(map(), keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def from_response(body, opts \\ [])

  def from_response(
        %{"access_token" => access_token, "token_type" => token_type} = body,
        opts
      )
      when is_binary(access_token) and is_binary(token_type) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    expires_in = body["expires_in"] || 3600
    requested_scopes = Keyword.get(opts, :requested_scopes, [])

    # RFC 6749 §5.1 — scope OPTIONAL if identical to what was requested
    granted_scopes = parse_scopes(body["scope"], requested_scopes)

    {:ok,
     %__MODULE__{
       access_token: access_token,
       token_type: String.downcase(token_type),
       granted_scopes: granted_scopes,
       expires_at: DateTime.add(now, expires_in, :second)
     }}
  end

  def from_response(_body, _opts) do
    {:error,
     MalformedResponse.exception(
       service: :oauth,
       reason: "missing access_token or token_type in token response",
       spec_ref: "Sec §4.1"
     )}
  end

  defp parse_scopes(nil, requested_scopes), do: requested_scopes
  defp parse_scopes(scope, _requested) when is_binary(scope), do: String.split(scope)
end
