defmodule Ltix.OAuth do
  @authenticate_schema Zoi.keyword(
                         endpoints:
                           Zoi.map(Zoi.atom(), Zoi.any(),
                             description: "Map of service modules to endpoint structs."
                           )
                           |> Zoi.required(),
                         req_options:
                           Zoi.keyword(Zoi.any(),
                             description: "Options passed through to `Req.request/2`."
                           )
                           |> Zoi.default([])
                       )

  @moduledoc """
  OAuth 2.0 client credentials authentication for LTI Advantage services.

  Acquires an access token from the platform's token endpoint and returns
  an authenticated `Ltix.OAuth.Client` ready for service calls.

  ## Single service

      {:ok, client} = Ltix.OAuth.authenticate(registration,
        endpoints: %{Ltix.MembershipsService => endpoint}
      )

  ## Multiple services

      {:ok, client} = Ltix.OAuth.authenticate(registration,
        endpoints: %{
          Ltix.MembershipsService => memberships_endpoint,
          Ltix.GradeService => ags_endpoint
        }
      )

  Scopes from all endpoints are combined into a single token request.

  ## Options

  #{Zoi.describe(@authenticate_schema)}
  """

  alias Ltix.OAuth.AccessToken
  alias Ltix.OAuth.Client
  alias Ltix.OAuth.ClientCredentials
  alias Ltix.Registerable

  @doc """
  Given a registration, authenticate with a platform's token endpoint.

  Accepts any struct that implements `Ltix.Registerable`, including
  `Ltix.Registration` itself.

  Request scopes by passing service endpoints in the `:endpoints` option.
  """
  # [Sec §4.1](https://www.imsglobal.org/spec/security/v1p0/#using-oauth-2-0-client-credentials-grant)
  @spec authenticate(Registerable.t(), keyword()) ::
          {:ok, Client.t()} | {:error, Exception.t()}
  def authenticate(registerable, opts \\ []) do
    opts = Zoi.parse!(@authenticate_schema, opts)
    endpoints = Keyword.fetch!(opts, :endpoints)
    req_options = Keyword.fetch!(opts, :req_options)

    with {:ok, registration} <- Registerable.to_registration(registerable),
         :ok <- validate_endpoints(endpoints),
         scopes = collect_scopes(endpoints),
         {:ok, token} <- do_request_token(registration, scopes, req_options) do
      {:ok,
       %Client{
         access_token: token.access_token,
         expires_at: token.expires_at,
         scopes: MapSet.new(token.granted_scopes),
         registration: registration,
         req_options: req_options,
         endpoints: endpoints
       }}
    end
  end

  @doc """
  Same as `authenticate/2` but raises on error.
  """
  @spec authenticate!(Registerable.t(), keyword()) :: Client.t()
  def authenticate!(registerable, opts \\ []) do
    case authenticate(registerable, opts) do
      {:ok, client} -> client
      {:error, error} -> raise error
    end
  end

  defp validate_endpoints(endpoints) do
    Enum.reduce_while(endpoints, :ok, fn {module, endpoint}, :ok ->
      case module.validate_endpoint(endpoint) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp collect_scopes(endpoints) do
    endpoints
    |> Enum.flat_map(fn {module, endpoint} -> module.scopes(endpoint) end)
    |> Enum.uniq()
  end

  defp do_request_token(registration, scopes, req_options) do
    metadata = %{scopes_requested: scopes}

    :telemetry.span([:ltix, :oauth, :authenticate], metadata, fn ->
      result = ClientCredentials.request_token(registration, scopes, req_options: req_options)
      {result, Map.merge(metadata, stop_metadata(scopes, result))}
    end)
  end

  defp stop_metadata(scopes_requested, {:ok, %AccessToken{} = token}) do
    expires_in = DateTime.diff(token.expires_at, DateTime.utc_now())

    %{
      scopes_requested: scopes_requested,
      scopes_granted: token.granted_scopes,
      expires_in: expires_in
    }
  end

  defp stop_metadata(scopes_requested, {:error, _}) do
    %{scopes_requested: scopes_requested, scopes_granted: nil, expires_in: nil}
  end
end
