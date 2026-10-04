defmodule Ltix.OAuth do
  @authenticate_schema Zoi.keyword(
                         [
                           endpoints:
                             Zoi.map(Zoi.atom(), Zoi.any(),
                               description: "Map of service modules to endpoint structs."
                             )
                             |> Zoi.required(),
                           req_options:
                             Zoi.keyword(Zoi.any(),
                               description: "Options passed through to `Req.request/2`."
                             )
                             |> Zoi.default([]),
                           require_all_scopes:
                             Zoi.boolean(
                               description:
                                 "Return a `ScopeMismatch` error unless the platform grants every requested scope."
                             )
                             |> Zoi.default(false)
                         ],
                         unrecognized_keys: :error
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

  The platform may grant only some of the scopes the endpoints need. Each service operation returns a `Ltix.Errors.Invalid.ScopeMismatch` error when its scope was not granted. Pass `require_all_scopes: true` to get that error from `authenticate/2` instead.

  ## Options

  #{Zoi.describe(@authenticate_schema)}
  """

  alias Ltix.OAuth.AccessToken
  alias Ltix.OAuth.Client
  alias Ltix.OAuth.ClientCredentials
  alias Ltix.Options
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
    opts = Options.parse!(opts, @authenticate_schema)
    endpoints = Keyword.fetch!(opts, :endpoints)
    req_options = Keyword.fetch!(opts, :req_options)

    with {:ok, registration} <- Registerable.to_registration(registerable),
         :ok <- Client.validate_endpoints(endpoints),
         scopes = Client.collect_scopes(endpoints),
         {:ok, token} <- do_request_token(registration, scopes, req_options) do
      token
      |> Client.new(registration, endpoints, req_options)
      |> Client.check_granted_scopes(Keyword.fetch!(opts, :require_all_scopes))
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
