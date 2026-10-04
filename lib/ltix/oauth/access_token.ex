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
      MapSet.new(["https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"])
      iex> token.expires_at
      ~U[2025-01-01 01:00:00Z]
  """

  alias Ltix.Errors.Invalid.MalformedResponse
  alias Ltix.Options

  @options_schema Zoi.keyword(
                    [
                      requested_scopes: Zoi.list(Zoi.string()) |> Zoi.default([]),
                      now: Zoi.struct(DateTime)
                    ],
                    unrecognized_keys: :error
                  )

  @expiry_buffer_seconds 60

  defstruct [:access_token, :token_type, :granted_scopes, :expires_at]

  @type t :: %__MODULE__{
          access_token: String.t(),
          token_type: String.t(),
          granted_scopes: MapSet.t(String.t()),
          expires_at: DateTime.t()
        }

  @doc """
  Parse a bearer access token from a token endpoint response body.

  If `"expires_in"` is omitted, the lifetime defaults to 3600 seconds.

  ## Options

    * `:requested_scopes` - list of scope strings that were requested, used
      as fallback when the response omits `"scope"`.
    * `:now` - override current time (default: `DateTime.utc_now/0`).
  """
  # [Sec §4.1](https://www.imsglobal.org/spec/security/v1p0/#using-oauth-2-0-client-credentials-grant)
  # [RFC 6749 §5.1](https://www.rfc-editor.org/rfc/rfc6749#section-5.1)
  @spec from_response(term(), keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def from_response(body, opts \\ []) do
    parse_response(body, Options.parse!(opts, @options_schema))
  end

  @doc """
  Check whether the token has expired.

  Uses a 60-second buffer to avoid using a token that is about to expire.

  ## Examples

      iex> token = %Ltix.OAuth.AccessToken{expires_at: DateTime.add(DateTime.utc_now(), 3600)}
      iex> Ltix.OAuth.AccessToken.expired?(token)
      false
  """
  # [Sec §7.1](https://www.imsglobal.org/spec/security/v1p0/#access-token-management)
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expires_at: expires_at}) do
    buffered = DateTime.add(expires_at, -@expiry_buffer_seconds)
    DateTime.compare(DateTime.utc_now(), buffered) != :lt
  end

  defp parse_response(
         %{"access_token" => access_token, "token_type" => token_type} = body,
         opts
       )
       when is_binary(access_token) and byte_size(access_token) > 0 and
              is_binary(token_type) and byte_size(token_type) > 0 do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    requested_scopes = Keyword.fetch!(opts, :requested_scopes)

    with :ok <- validate_token(access_token, token_type),
         {:ok, expires_at} <- parse_expiry(Map.fetch(body, "expires_in"), now),
         {:ok, granted_scopes} <- parse_scopes(Map.fetch(body, "scope"), requested_scopes) do
      {:ok,
       %__MODULE__{
         access_token: access_token,
         token_type: "bearer",
         granted_scopes: granted_scopes,
         expires_at: expires_at
       }}
    end
  end

  defp parse_response(_body, _opts) do
    malformed_response("missing access_token or token_type, or invalid value in token response")
  end

  # [RFC 6750 §2.1](https://www.rfc-editor.org/rfc/rfc6750#section-2.1)
  # [RFC 6749 §7.1](https://www.rfc-editor.org/rfc/rfc6749#section-7.1)
  defp validate_token(access_token, token_type) do
    cond do
      not Regex.match?(~r/\A[A-Za-z0-9._~+\/-]+=*\z/, access_token) ->
        malformed_response("access_token must be a nonempty bearer credential", "RFC 6750 §2.1")

      not Regex.match?(~r/\Abearer\z/i, token_type) ->
        malformed_response("unsupported token_type", "RFC 6749 §7.1")

      true ->
        :ok
    end
  end

  defp parse_expiry(:error, now), do: parse_expiry({:ok, 3600}, now)

  # [RFC 6749 §A.14](https://www.rfc-editor.org/rfc/rfc6749#appendix-A.14)
  defp parse_expiry({:ok, expires_in}, now) when is_integer(expires_in) and expires_in >= 0 do
    case DateTime.from_unix(DateTime.to_unix(now) + expires_in) do
      {:ok, _datetime} -> {:ok, DateTime.add(now, expires_in, :second)}
      {:error, _reason} -> malformed_response("expires_in exceeds the supported expiration range")
    end
  end

  defp parse_expiry(_expires_in, _now) do
    malformed_response("expires_in must be a nonnegative JSON integer")
  end

  # [RFC 6749 §3.3](https://www.rfc-editor.org/rfc/rfc6749#section-3.3)
  defp parse_scopes(:error, requested_scopes), do: {:ok, MapSet.new(requested_scopes)}

  defp parse_scopes({:ok, scope}, _requested_scopes) when is_binary(scope) do
    case Regex.match?(~r/\A[\x21\x23-\x5B\x5D-\x7E]+(?: [\x21\x23-\x5B\x5D-\x7E]+)*\z/, scope) do
      true -> {:ok, MapSet.new(String.split(scope, " "))}
      false -> malformed_response("scope must contain space-separated OAuth scope tokens")
    end
  end

  defp parse_scopes(_scope, _requested_scopes) do
    malformed_response("scope must be a string")
  end

  defp malformed_response(reason, spec_ref \\ "RFC 6749 §5.1") do
    {:error, MalformedResponse.exception(service: :oauth, reason: reason, spec_ref: spec_ref)}
  end
end
