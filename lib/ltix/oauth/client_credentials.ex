defmodule Ltix.OAuth.ClientCredentials do
  @moduledoc false

  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.Errors.Invalid.TokenRequestFailed
  alias Ltix.HTTP
  alias Ltix.OAuth.AccessToken
  alias Ltix.Registration

  @grant_type "client_credentials"
  @assertion_type "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

  @doc """
  Request an OAuth 2.0 access token via the client credentials grant.

  Builds a signed JWT assertion and POSTs it to the platform's token
  endpoint. Returns a parsed `AccessToken` on success.

  ## Options

    * `:req_options` - options passed through to `Req.request/2` (default: `[]`)
  """
  @spec request_token(Registration.t(), [String.t()], keyword()) ::
          {:ok, AccessToken.t()} | {:error, Exception.t()}
  def request_token(registration, scopes, opts \\ [])

  def request_token(%Registration{token_endpoint: nil}, _scopes, _opts) do
    {:error,
     ServiceNotAvailable.exception(
       service: :oauth,
       reason: "The registration has no token endpoint",
       spec_ref: "Sec §4.1"
     )}
  end

  def request_token(%Registration{} = registration, scopes, opts) do
    req_options = req_options(opts)
    assertion = build_assertion(registration)

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
      |> Keyword.put(:decode_body, false)

    with {:ok, response} <- HTTP.request(Keyword.put(req_opts, :method, :post)) do
      parse_response(decode_response(response), scopes)
    end
  end

  # Requests a token inside a `[:ltix, :oauth, action]` telemetry span.
  @doc false
  @spec request_token_span(atom(), Registration.t(), [String.t()], keyword()) ::
          {:ok, AccessToken.t()} | {:error, Exception.t()}
  def request_token_span(action, registration, scopes, req_options) do
    metadata = %{scopes_requested: scopes}

    :telemetry.span([:ltix, :oauth, action], metadata, fn ->
      result = request_token(registration, scopes, req_options: req_options)
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

  defp decode_response(%Req.Response{body: body} = response) when is_binary(body) do
    with [content_type] <- Req.Response.get_header(response, "content-type"),
         [media_type | _parameters] <- String.split(content_type, ";", parts: 2),
         "application/json" <- String.downcase(String.trim(media_type)),
         {:ok, decoded_body} <- Ltix.AppConfig.json_library!().decode(body) do
      %{response | body: decoded_body}
    else
      _ -> response
    end
  end

  defp decode_response(response), do: response

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
  # Build and sign the JWT client assertion with all MUST claims.
  defp build_assertion(%Registration{} = registration) do
    now = System.system_time(:second)
    jose_jwk = Ltix.JWK.to_jose(registration.tool_jwk)
    {_kty, fields} = JOSE.JWK.to_map(jose_jwk)

    claims = %{
      "iss" => registration.client_id,
      "sub" => registration.client_id,
      "aud" => registration.token_endpoint,
      "iat" => now,
      "exp" => now + 300,
      "jti" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    }

    # [Sec §6.1](https://www.imsglobal.org/spec/security/v1p0/#rsa-key)
    jws = JOSE.JWS.from_map(%{"typ" => "JWT", "alg" => "RS256", "kid" => fields["kid"]})
    jwt = JOSE.JWT.from_map(claims)

    {_meta, token} =
      jose_jwk
      |> JOSE.JWT.sign(jws, jwt)
      |> JOSE.JWS.compact()

    token
  end

  defp req_options(opts) do
    HTTP.req_options(Keyword.get(opts, :req_options, []), __MODULE__)
  end
end
