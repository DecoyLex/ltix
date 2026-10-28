defmodule Ltix.OAuth do
  alias Ltix.Claims
  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.Launch
  alias Ltix.OAuth.Client
  alias Ltix.OAuth.ClientCredentials
  alias Ltix.Options
  alias Ltix.PluginSet
  alias Ltix.Registerable

  @registration_schema Zoi.keyword(
                         [
                           endpoints:
                             Zoi.map(Zoi.atom(), Zoi.any(),
                               description: "Map of service modules to endpoint structs."
                             )
                             |> Zoi.required()
                         ] ++ Client.registration_option_fields(),
                         unrecognized_keys: :error
                       )

  @launch_schema Zoi.keyword(
                   [
                     services:
                       Zoi.list(Zoi.atom(),
                         description:
                           "Service modules whose endpoints are read from the launch claims."
                       )
                       |> Zoi.min(1)
                       |> Zoi.required()
                   ] ++ Client.option_fields(),
                   unrecognized_keys: :error
                 )

  @token_options [
    :storage_adapter,
    :storage_adapter_options,
    :deployment,
    :req_options,
    :local_network_access
  ]

  @moduledoc """
  OAuth 2.0 client credentials authentication for LTI Advantage services.

  Acquires an access token from the platform's token endpoint and returns
  an authenticated `Ltix.OAuth.Client` ready for service calls.

  ## From a launch

      {:ok, client} = Ltix.OAuth.authenticate(launch,
        services: [Ltix.MembershipsService, MyApp.AttendanceService]
      )

  ## From a registration

      {:ok, client} = Ltix.OAuth.authenticate(registration,
        endpoints: %{
          Ltix.MembershipsService => memberships_endpoint,
          Ltix.GradeService => ags_endpoint
        }
      )

  A token request from a launch includes the launch's deployment ID. With a registration, pass `:deployment` to include one. A platform may require it before it issues a token.

      {:ok, client} = Ltix.OAuth.authenticate(registration,
        endpoints: %{Ltix.GradeService => ags_endpoint},
        deployment: deployment
      )

  The platform may grant only some of the scopes the endpoints need. Each service operation returns a `Ltix.Errors.Invalid.ScopeMismatch` error when its scope was not granted. Pass `require_all_scopes: true` to get that error from `authenticate/2`.
  """

  @doc """
  Requests an access token for the services' endpoints and returns a
  client for their calls.

  From an `Ltix.Launch`, list the services in `:services`. From an
  `Ltix.Registration`, or your own struct that implements
  `Ltix.Registerable`, pass saved endpoints in `:endpoints`.

  ## Errors

    * `Ltix.Errors.Invalid.ServiceNotAvailable` - the launch has no
      endpoint for a service, no plugin in use provides a module in
      `:services` or `:endpoints`, or the registration has no token endpoint
    * `Ltix.Errors.Invalid.InvalidField` - a saved endpoint or the
      `:deployment` ID is invalid
    * `Ltix.Errors.Unknown.InvalidPluginSet` - two plugins in use conflict,
      such as two that declare the same claim
    * `Ltix.Errors.Unknown.StorageError` - the storage adapter doesn't
      implement `c:Ltix.StorageAdapter.key_id/2` or
      `c:Ltix.StorageAdapter.sign/4`, or one of them fails
    * `Ltix.Errors.Invalid.TokenRequestFailed` - the platform refused the
      token request. Its `error` and `error_description` fields have the
      platform's reason
    * `Ltix.Errors.Invalid.MalformedResponse` - the token response isn't a
      valid bearer token
    * `Ltix.Errors.Invalid.ScopeMismatch` - with `require_all_scopes: true`,
      the platform didn't grant a scope
    * an error a plugin's `Ltix.ClientAssertion` step returns

  A registration that doesn't implement `Ltix.Registerable`, or a
  `:deployment` that doesn't implement `Ltix.Deployable`, raises
  `ArgumentError`.
  [Error Handling](error-handling.md) lists the errors any platform request
  can return.

  ## Options

  When you [configure](`m:Ltix#module-configuration`) an option, the configured
  value is its default.

  ### From a launch

  #{Zoi.describe(@launch_schema)}

  ### From a registration

  #{Zoi.describe(@registration_schema)}
  """
  # [Sec §4.1](https://www.imsglobal.org/spec/security/v1p0/#using-oauth-2-0-client-credentials-grant)
  @spec authenticate(Launch.t() | Registerable.t(), keyword()) ::
          {:ok, Client.t()} | {:error, Exception.t()}
  def authenticate(launch_or_registerable, opts \\ [])

  def authenticate(%Launch{} = launch, opts) do
    {services, opts} = Keyword.pop!(Options.parse!(opts, @launch_schema), :services)

    with {:ok, endpoints} <- launch_endpoints(launch, services) do
      request_client(
        launch.source_registration,
        endpoints,
        opts
        |> Keyword.put_new(:plugins, launch.plugins)
        |> Keyword.put(:deployment, launch.source_deployment)
      )
    end
  end

  def authenticate(registerable, opts) do
    {endpoints, opts} = Keyword.pop!(Options.parse!(opts, @registration_schema), :endpoints)
    request_client(registerable, endpoints, opts)
  end

  @doc """
  Same as `authenticate/2` but raises on error.
  """
  @spec authenticate!(Launch.t() | Registerable.t(), keyword()) :: Client.t()
  def authenticate!(launch_or_registerable, opts \\ []) do
    case authenticate(launch_or_registerable, opts) do
      {:ok, client} -> client
      {:error, error} -> raise error
    end
  end

  defp request_client(registerable, endpoints, opts) do
    token_options = Keyword.take(opts, @token_options)

    with {:ok, plugins} <- PluginSet.resolve(opts[:plugins]),
         :ok <- Claims.validate_endpoints(endpoints, plugins),
         {:ok, assertion} <- ClientCredentials.client_assertion(endpoints, plugins),
         {:ok, token} <-
           ClientCredentials.request_token_span(
             :authenticate,
             registerable,
             assertion,
             token_options
           ) do
      client =
        struct!(
          Client,
          [token: token, registration: registerable, endpoints: endpoints, plugins: plugins] ++
            token_options
        )

      if Keyword.fetch!(opts, :require_all_scopes),
        do: Client.require_all_scopes(client, assertion.scopes),
        else: {:ok, client}
    end
  end

  # [Core §6.1](https://www.imsglobal.org/spec/lti/v1p3/#services-exposed-as-additional-claims)
  defp launch_endpoints(%Launch{endpoints: endpoints}, services) do
    case Enum.reject(services, &Map.has_key?(endpoints, &1)) do
      [] ->
        {:ok, Map.take(endpoints, services)}

      missing ->
        errors =
          for service <- missing do
            ServiceNotAvailable.exception(
              service: service,
              reason: "The launch has no endpoint claim for this service"
            )
          end

        {:error, Ltix.Errors.combine(errors)}
    end
  end
end
