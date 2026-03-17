defmodule Ltix.OAuth.ClientCredentials do
  @moduledoc false

  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.Errors.Invalid.TokenRequestFailed
  alias Ltix.OAuth.AccessToken
  alias Ltix.Registration

  @grant_type "client_credentials"
  @assertion_type "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

  @doc """
  Request an OAuth 2.0 access token via the client credentials grant.

  Builds a signed JWT assertion and POSTs it to the platform's token
  endpoint. Returns a parsed `AccessToken` on success.

  ## Options

    * `:req_options` - options passed through to `Req.post/1` (default: `[]`)
  """
  @spec request_token(Registration.t(), [String.t()], keyword()) ::
          {:ok, AccessToken.t()} | {:error, Exception.t()}
  def request_token(registration, scopes, opts \\ [])

  def request_token(%Registration{token_endpoint: nil}, _scopes, _opts) do
    {:error,
     ServiceNotAvailable.exception(
       service: :oauth,
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

    case Req.post(req_opts) do
      {:ok, %Req.Response{body: %{"access_token" => _} = body}} ->
        AccessToken.from_response(body, requested_scopes: scopes)

      {:ok, %Req.Response{status: _status, body: body}} when is_map(body) ->
        {:error,
         TokenRequestFailed.exception(
           error: body["error"],
           error_description: body["error_description"],
           status: nil,
           body: body,
           spec_ref: "Sec §4.1"
         )}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         TokenRequestFailed.exception(
           status: status,
           body: body,
           spec_ref: "Sec §4.1"
         )}

      {:error, exception} ->
        {:error, exception}
    end
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
    default = Application.get_env(:ltix, :req_options, [])
    Keyword.merge(default, Keyword.get(opts, :req_options, []))
  end
end
