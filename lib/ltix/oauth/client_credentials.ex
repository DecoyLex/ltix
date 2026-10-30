defmodule Ltix.OAuth.ClientCredentials do
  @moduledoc false

  alias Ltix.ClientAssertion
  alias Ltix.Deployment
  alias Ltix.Errors
  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.Errors.Invalid.TokenRequestFailed
  alias Ltix.HTTP
  alias Ltix.OAuth.AccessToken
  alias Ltix.Options
  alias Ltix.PluginSet
  alias Ltix.Records
  alias Ltix.Registerable
  alias Ltix.Registration
  alias Ltix.Step
  alias Ltix.StorageAdapter

  @grant_type "client_credentials"
  @assertion_type "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
  @deployment_claim "https://purl.imsglobal.org/spec/lti/claim/deployment_id"

  @doc """
  Runs the client assertion's steps with the endpoints.

  Returns the client assertion with each scope once, or the errors steps
  recorded, combined.
  """
  @spec client_assertion(%{module() => term()}, PluginSet.t()) ::
          {:ok, ClientAssertion.t()} | {:error, Exception.t()}
  def client_assertion(endpoints, %PluginSet{} = plugins) do
    assertion = Step.run(%ClientAssertion{endpoints: endpoints, plugins: plugins})

    with :ok <- Errors.collect(assertion.errors),
         do: {:ok, %{assertion | scopes: Enum.uniq(assertion.scopes)}}
  end

  # Requests an access token with the client credentials grant. Adds the
  # claims every client assertion requires to the steps' claims, signs them
  # with the storage adapter, and posts the signed assertion and the scopes to
  # the platform's token endpoint.
  defp request_token(registerable, %ClientAssertion{} = assertion, opts) do
    with {:ok, registration} <- Records.convert!(registerable, :registration),
         :ok <- require_token_endpoint(registration),
         {:ok, deployment} <- resolve_deployment(Keyword.get(opts, :deployment)),
         {:ok, signed} <-
           StorageAdapter.sign_jwt(
             Options.fetch_configured!(opts, :storage_adapter),
             registerable,
             Map.merge(assertion.claims, required_claims(registration, deployment)),
             Keyword.get(opts, :storage_adapter_options, [])
           ) do
      send_token_request(registration, assertion.scopes, opts, signed)
    end
  end

  defp require_token_endpoint(%Registration{token_endpoint: nil}) do
    {:error,
     ServiceNotAvailable.exception(
       service: :oauth,
       reason: "The registration has no token endpoint"
     )}
  end

  defp require_token_endpoint(%Registration{}), do: :ok

  # Returns the `Ltix.Deployment` for a `:deployment` option, which is a
  # struct implementing `Ltix.Deployable`, a deployment ID, or `nil`.
  @doc false
  @spec resolve_deployment(term()) :: {:ok, Deployment.t() | nil} | {:error, Exception.t()}
  def resolve_deployment(nil), do: {:ok, nil}

  def resolve_deployment(deployment_id) when is_binary(deployment_id),
    do: Deployment.new(deployment_id)

  def resolve_deployment(record), do: Records.convert!(record, :deployment, :deployment)

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
      |> Keyword.merge(method: :post, service: :oauth)

    with {:ok, response} <- HTTP.request(req_opts) do
      parse_response(response, scopes)
    end
  end

  # Requests a token inside a `[:ltix, :oauth, action]` telemetry span.
  @doc false
  @spec request_token_span(atom(), Registerable.t(), ClientAssertion.t(), keyword()) ::
          {:ok, AccessToken.t()} | {:error, Exception.t()}
  def request_token_span(action, registerable, %ClientAssertion{} = assertion, opts) do
    metadata = %{scopes_requested: assertion.scopes}

    :telemetry.span([:ltix, :oauth, action], metadata, fn ->
      result = request_token(registerable, assertion, opts)
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
       body: body
     )}
  end

  defp parse_response(%Req.Response{status: status, body: body}, _scopes) do
    {:error, TokenRequestFailed.exception(status: status, body: body)}
  end

  # [Sec §4.1.1](https://www.imsglobal.org/spec/security/v1p0/#using-json-web-tokens-with-oauth-2-0-client-credentials-grant)
  # The MUST claims of the JWT client assertion.
  defp required_claims(%Registration{} = registration, nil) do
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

  # [Core, Deployment ID](https://standards.1edtech.org/lti/specifications/core/lti-spec#deployment-id)
  defp required_claims(%Registration{} = registration, %Deployment{deployment_id: deployment_id}) do
    Map.put(required_claims(registration, nil), @deployment_claim, deployment_id)
  end

  defp req_options(opts) do
    HTTP.req_options(Keyword.get(opts, :req_options, []), __MODULE__)
  end
end
