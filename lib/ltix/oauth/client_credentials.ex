defmodule Ltix.OAuth.ClientCredentials do
  @moduledoc false

  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.Errors.Invalid.TokenRequestFailed
  alias Ltix.HTTP
  alias Ltix.OAuth.AccessToken
  alias Ltix.Options
  alias Ltix.Records
  alias Ltix.Registerable
  alias Ltix.Registration
  alias Ltix.StorageAdapter

  @grant_type "client_credentials"
  @assertion_type "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

  @doc """
  Request an OAuth 2.0 access token via the client credentials grant.

  Takes any record implementing `Ltix.Registerable`. Builds a JWT assertion
  signed by the storage adapter and POSTs it to the platform's token
  endpoint. Returns a parsed `AccessToken` on success.

  ## Options

    * `:storage_adapter` - module implementing `Ltix.StorageAdapter` with the
      signing callbacks (defaults to application config)
    * `:req_options` - options passed through to `Req.request/2` (defaults to `[]`)
    * `:local_network_access` - see `Ltix.HTTP.local_network_access_option/0`
  """
  @spec request_token(Registerable.t(), [String.t()], keyword()) ::
          {:ok, AccessToken.t()} | {:error, Exception.t()}
  def request_token(registerable, scopes, opts \\ []) do
    with {:ok, registration} <- Records.convert!(registerable, :registration),
         :ok <- require_token_endpoint(registration),
         {:ok, assertion} <-
           StorageAdapter.sign_jwt(
             Options.fetch_configured!(opts, :storage_adapter),
             registerable,
             assertion_claims(registration)
           ) do
      send_token_request(registration, scopes, opts, assertion)
    end
  end

  defp require_token_endpoint(%Registration{token_endpoint: nil}) do
    {:error,
     ServiceNotAvailable.exception(
       service: :oauth,
       reason: "The registration has no token endpoint",
       spec_ref: "Sec §4.1"
     )}
  end

  defp require_token_endpoint(%Registration{}), do: :ok

  defp send_token_request(registration, scopes, opts, assertion) do
    req_options = req_options(opts)

    body =
      URI.encode_query(%{
        "grant_type" => @grant_type,
        "client_assertion_type" => @assertion_type,
        "client_assertion" => assertion,
        "scope" => Enum.join(scopes, " ")
      })

    req_opts =
      req_options
      |> Keyword.put(:url, registration.token_endpoint)
      |> Keyword.put(:headers, [{"content-type", "application/x-www-form-urlencoded"}])
      |> Keyword.put(:body, body)
      |> Keyword.put(:retry, false)
      |> Keyword.put(:local_network_access, Keyword.get(opts, :local_network_access))
      |> Keyword.merge(method: :post, service: :oauth, spec_ref: "RFC 6749 §5.1")

    with {:ok, response} <- HTTP.request(req_opts) do
      parse_response(response, scopes)
    end
  end

  # Requests a token inside a `[:ltix, :oauth, action]` telemetry span.
  @doc false
  @spec request_token_span(atom(), Registerable.t(), [String.t()], keyword()) ::
          {:ok, AccessToken.t()} | {:error, Exception.t()}
  def request_token_span(action, registerable, scopes, opts) do
    metadata = %{scopes_requested: scopes}

    :telemetry.span([:ltix, :oauth, action], metadata, fn ->
      result = request_token(registerable, scopes, opts)
      {result, Map.merge(metadata, stop_metadata(result))}
    end)
  end

  defp stop_metadata({:ok, %AccessToken{} = token}) do
    %{
      scopes_granted: MapSet.to_list(token.granted_scopes),
      expires_in: DateTime.diff(token.expires_at, DateTime.utc_now())
    }
  end

  defp stop_metadata({:error, _}), do: %{scopes_granted: nil, expires_in: nil}

  # [RFC 6749 §5.1](https://www.rfc-editor.org/rfc/rfc6749#section-5.1)
  defp parse_response(%Req.Response{status: 200, body: body}, scopes) do
    AccessToken.from_response(body, requested_scopes: scopes)
  end

  # [RFC 6749 §5.2](https://www.rfc-editor.org/rfc/rfc6749#section-5.2)
  defp parse_response(%Req.Response{status: status, body: body}, _scopes) when is_map(body) do
    {:error,
     TokenRequestFailed.exception(
       error: body["error"],
       error_description: body["error_description"],
       status: status,
       body: body,
       spec_ref: "Sec §4.1"
     )}
  end

  defp parse_response(%Req.Response{status: status, body: body}, _scopes) do
    {:error,
     TokenRequestFailed.exception(
       status: status,
       body: body,
       spec_ref: "Sec §4.1"
     )}
  end

  # [Sec §4.1.1](https://www.imsglobal.org/spec/security/v1p0/#using-json-web-tokens-with-oauth-2-0-client-credentials-grant)
  # The MUST claims of the JWT client assertion.
  defp assertion_claims(%Registration{} = registration) do
    now = System.system_time(:second)

    %{
      "iss" => registration.client_id,
      "sub" => registration.client_id,
      "aud" => registration.audience || registration.token_endpoint,
      "iat" => now,
      "exp" => now + 300,
      "jti" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    }
  end

  defp req_options(opts) do
    HTTP.req_options(Keyword.get(opts, :req_options, []), __MODULE__)
  end
end
