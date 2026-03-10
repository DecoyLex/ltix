defmodule Ltix.OAuth do
  @authenticate_schema NimbleOptions.new!(
                         endpoints: [
                           type: {:map, :atom, :any},
                           required: true,
                           doc: "Map of service modules to endpoint structs."
                         ],
                         req_options: [
                           type: :keyword_list,
                           default: [],
                           doc: "Options passed through to `Req.request/2`."
                         ]
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

  #{NimbleOptions.docs(@authenticate_schema)}
  """

  alias Ltix.OAuth.{Client, ClientCredentials}
  alias Ltix.Registration

  @doc """
  Given a registration, authenticate with a platform's token endpoint.

  Request scopes by passing service endpoints in the `:endpoints` option.
  """
  # [Sec §4.1](https://www.imsglobal.org/spec/security/v1p0/#using-oauth-2-0-client-credentials-grant)
  @spec authenticate(Registration.t(), keyword()) ::
          {:ok, Client.t()} | {:error, Exception.t()}
  def authenticate(%Registration{} = registration, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @authenticate_schema)
    endpoints = Keyword.fetch!(opts, :endpoints)
    req_options = Keyword.fetch!(opts, :req_options)

    with :ok <- validate_endpoints(endpoints),
         scopes = collect_scopes(endpoints),
         {:ok, token} <-
           ClientCredentials.request_token(registration, scopes, req_options: req_options) do
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
  @spec authenticate!(Registration.t(), keyword()) :: Client.t()
  def authenticate!(%Registration{} = registration, opts \\ []) do
    case authenticate(registration, opts) do
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
end
