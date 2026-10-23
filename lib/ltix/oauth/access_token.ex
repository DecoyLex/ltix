defmodule Ltix.OAuth.AccessToken do
  @moduledoc """
  OAuth 2.0 access token response.

  A cacheable struct holding the parsed token data from a platform's token
  endpoint. Applications can store this and reuse it across contexts via
  `Ltix.OAuth.Client.from_access_token/2`. To store it outside the VM, such as
  in a database, save `to_map/1` as JSON and restore it with `from_map/1`.

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

  alias Ltix.Errors
  alias Ltix.Errors.Invalid.InvalidField
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

  @derive {Inspect, except: [:access_token]}
  defstruct [:access_token, :token_type, :granted_scopes, :issued_at, :expires_at]

  @type t :: %__MODULE__{
          access_token: String.t(),
          token_type: String.t(),
          granted_scopes: MapSet.t(String.t()),
          issued_at: DateTime.t() | nil,
          expires_at: DateTime.t()
        }

  @doc """
  Parse a bearer access token from a token endpoint response body.

  If `"expires_in"` is omitted, the lifetime defaults to 3600 seconds.

  ## Options

    * `:requested_scopes` - list of scope strings that were requested, used
      when the response omits `"scope"`.
    * `:now` - override current time (defaults to `DateTime.utc_now/0`).
  """
  # [Sec §4.1](https://www.imsglobal.org/spec/security/v1p0/#using-oauth-2-0-client-credentials-grant)
  # [RFC 6749 §5.1](https://www.rfc-editor.org/rfc/rfc6749#section-5.1)
  @spec from_response(term(), keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def from_response(body, opts \\ []) do
    parse_response(body, Options.parse!(opts, @options_schema))
  end

  @doc """
  Check whether the token has expired.

  A token counts as expired 60 seconds before its expiry, so it isn't used
  when about to expire. A token with a lifetime under two minutes counts as
  expired halfway through its lifetime. Without an `issued_at` time,
  the 60 seconds apply.

  ## Examples

      iex> token = %Ltix.OAuth.AccessToken{expires_at: DateTime.add(DateTime.utc_now(), 3600)}
      iex> Ltix.OAuth.AccessToken.expired?(token)
      false
  """
  # [Sec §7.1](https://www.imsglobal.org/spec/security/v1p0/#access-token-management)
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{issued_at: issued_at, expires_at: expires_at}) do
    buffered = DateTime.add(expires_at, -expiry_buffer(issued_at, expires_at))
    DateTime.compare(DateTime.utc_now(), buffered) != :lt
  end

  defp expiry_buffer(%DateTime{} = issued_at, expires_at),
    do: min(@expiry_buffer_seconds, div(DateTime.diff(expires_at, issued_at), 2))

  defp expiry_buffer(nil, _expires_at), do: @expiry_buffer_seconds

  @doc """
  Convert a token to a map with string keys and values that encodes to JSON.

  Restore it with `from_map/1`.

  ## Examples

      iex> token = %Ltix.OAuth.AccessToken{
      ...>   access_token: "tok",
      ...>   token_type: "bearer",
      ...>   granted_scopes: MapSet.new(["scope:write", "scope:read"]),
      ...>   expires_at: ~U[2025-01-01 01:00:00Z]
      ...> }
      iex> Ltix.OAuth.AccessToken.to_map(token)
      %{
        "access_token" => "tok",
        "scope" => "scope:read scope:write",
        "expires_at" => "2025-01-01T01:00:00Z"
      }
  """
  @spec to_map(t()) :: %{String.t() => String.t()}
  def to_map(%__MODULE__{} = token) do
    %{
      "access_token" => token.access_token,
      "scope" => Enum.join(Enum.sort(token.granted_scopes), " "),
      "issued_at" => token.issued_at && DateTime.to_iso8601(token.issued_at),
      "expires_at" => DateTime.to_iso8601(token.expires_at)
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  @doc """
  Restore a token from a map returned by `to_map/1`.

  Returns `Ltix.Errors.Invalid.InvalidField` for a missing or malformed
  field.

  ## Examples

      iex> {:ok, token} = Ltix.OAuth.AccessToken.from_map(%{
      ...>   "access_token" => "tok",
      ...>   "scope" => "scope:read",
      ...>   "expires_at" => "2025-01-01T01:00:00Z"
      ...> })
      iex> {token.access_token, token.granted_scopes, token.expires_at}
      {"tok", MapSet.new(["scope:read"]), ~U[2025-01-01 01:00:00Z]}
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_map(map) when is_map(map) do
    fields = [
      access_token: stored_access_token(map["access_token"]),
      granted_scopes: stored_scopes(map["scope"]),
      issued_at: stored_time(:issued_at, map["issued_at"]),
      expires_at: stored_time(:expires_at, map["expires_at"])
    ]

    case for {_field, {:error, error}} <- fields, do: error do
      [] ->
        values = for {field, {:ok, value}} <- fields, do: {field, value}
        {:ok, struct!(__MODULE__, [token_type: "bearer"] ++ values)}

      errors ->
        {:error, Errors.combine(errors)}
    end
  end

  # The token is redacted from errors.
  defp stored_access_token(nil), do: {:error, InvalidField.required(__MODULE__, :access_token)}

  defp stored_access_token(token) do
    if bearer_credential?(token),
      do: {:ok, token},
      else:
        {:error,
         InvalidField.invalid(__MODULE__, :access_token, "[redacted]", "must be a bearer token")}
  end

  defp stored_scopes(scope) when scope in [nil, ""], do: {:ok, MapSet.new()}

  defp stored_scopes(scope) do
    if is_binary(scope) and scope_tokens?(scope),
      do: {:ok, MapSet.new(String.split(scope, " "))},
      else:
        {:error,
         InvalidField.invalid(
           __MODULE__,
           :granted_scopes,
           scope,
           "must be space-separated scopes"
         )}
  end

  defp stored_time(:issued_at, nil), do: {:ok, nil}
  defp stored_time(field, nil), do: {:error, InvalidField.required(__MODULE__, field)}

  defp stored_time(field, time) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, date_time, _offset} -> {:ok, date_time}
      {:error, _reason} -> invalid_time(field, time)
    end
  end

  defp stored_time(field, time), do: invalid_time(field, time)

  defp invalid_time(field, time),
    do:
      {:error, InvalidField.invalid(__MODULE__, field, time, "must be an ISO 8601 date and time")}

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
         issued_at: now,
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
      not bearer_credential?(access_token) ->
        malformed_response("access_token must be a nonempty bearer credential")

      not Regex.match?(~r/\Abearer\z/i, token_type) ->
        malformed_response("unsupported token_type")

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
    case scope_tokens?(scope) do
      true -> {:ok, MapSet.new(String.split(scope, " "))}
      false -> malformed_response("scope must contain space-separated OAuth scope tokens")
    end
  end

  defp parse_scopes(_scope, _requested_scopes) do
    malformed_response("scope must be a string")
  end

  # [RFC 6750 §2.1](https://www.rfc-editor.org/rfc/rfc6750#section-2.1)
  defp bearer_credential?(token),
    do: is_binary(token) and Regex.match?(~r/\A[A-Za-z0-9._~+\/-]+=*\z/, token)

  # [RFC 6749 §3.3](https://www.rfc-editor.org/rfc/rfc6749#section-3.3)
  defp scope_tokens?(scope),
    do: Regex.match?(~r/\A[\x21\x23-\x5B\x5D-\x7E]+(?: [\x21\x23-\x5B\x5D-\x7E]+)*\z/, scope)

  defp malformed_response(reason) do
    {:error, MalformedResponse.exception(service: :oauth, reason: reason)}
  end
end
