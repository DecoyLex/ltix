defmodule Ltix.OAuth do
  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.LaunchContext
  alias Ltix.OAuth.Client
  alias Ltix.OAuth.ClientCredentials
  alias Ltix.Options
  alias Ltix.Records
  alias Ltix.Registerable

  @shared_fields Client.option_fields()

  @registration_schema Zoi.keyword(
                         [
                           endpoints:
                             Zoi.map(Zoi.atom(), Zoi.any(),
                               description: "Map of service modules to endpoint structs."
                             )
                             |> Zoi.required()
                         ] ++ @shared_fields,
                         unrecognized_keys: :error
                       )

  @context_schema Zoi.keyword(
                    [
                      services:
                        Zoi.list(Zoi.atom(),
                          description:
                            "Service modules whose endpoints are read from the launch claims."
                        )
                        |> Zoi.min(1)
                        |> Zoi.required()
                    ] ++ @shared_fields,
                    unrecognized_keys: :error
                  )

  @moduledoc """
  OAuth 2.0 client credentials authentication for LTI Advantage services.

  Acquires an access token from the platform's token endpoint and returns
  an authenticated `Ltix.OAuth.Client` ready for service calls.

  ## From a launch context

      {:ok, client} = Ltix.OAuth.authenticate(launch_context,
        services: [Ltix.MembershipsService, MyApp.AttendanceService]
      )

  ## From a registration

      {:ok, client} = Ltix.OAuth.authenticate(registration,
        endpoints: %{
          Ltix.MembershipsService => memberships_endpoint,
          Ltix.GradeService => ags_endpoint
        }
      )

  The platform may grant only some of the scopes the endpoints need. Each service operation returns a `Ltix.Errors.Invalid.ScopeMismatch` error when its scope was not granted. Pass `require_all_scopes: true` to get that error from `authenticate/2` instead.

  ## Options (launch context)

  #{Zoi.describe(@context_schema)}

  ## Options (registration)

  #{Zoi.describe(@registration_schema)}
  """

  @doc """
  Authenticate with a platform's token endpoint.

  Accepts a `%LaunchContext{}` or any struct implementing `Ltix.Registerable`,
  including `Ltix.Registration` itself. With a launch context, list the
  services in the `:services` option, and Ltix reads each endpoint from the
  launch claims. With a registration, pass the endpoints in the `:endpoints` option.
  A service missing from the launch returns a `ServiceNotAvailable` error.
  """
  # [Sec §4.1](https://www.imsglobal.org/spec/security/v1p0/#using-oauth-2-0-client-credentials-grant)
  @spec authenticate(LaunchContext.t() | Registerable.t(), keyword()) ::
          {:ok, Client.t()} | {:error, Exception.t()}
  def authenticate(context_or_registerable, opts \\ [])

  def authenticate(%LaunchContext{} = context, opts) do
    {services, opts} = Keyword.pop!(Options.parse!(opts, @context_schema), :services)

    case endpoints_from_claims(context.claims, services) do
      {:ok, endpoints} -> request_client(context.registration, endpoints, opts)
      {:error, _} = error -> error
    end
  end

  def authenticate(registerable, opts) do
    {endpoints, opts} = Keyword.pop!(Options.parse!(opts, @registration_schema), :endpoints)
    request_client(registerable, endpoints, opts)
  end

  @doc """
  Same as `authenticate/2` but raises on error.
  """
  @spec authenticate!(LaunchContext.t() | Registerable.t(), keyword()) :: Client.t()
  def authenticate!(context_or_registerable, opts \\ []) do
    case authenticate(context_or_registerable, opts) do
      {:ok, client} -> client
      {:error, error} -> raise error
    end
  end

  defp request_client(registerable, endpoints, opts) do
    with {:ok, registration} <- Records.convert!(registerable, :registration),
         :ok <- Client.validate_endpoints(endpoints),
         {:ok, token} <-
           ClientCredentials.request_token_span(
             :authenticate,
             registration,
             Client.collect_scopes(endpoints),
             Keyword.take(opts, [:storage_adapter, :req_options, :local_network_access])
           ) do
      Client.from_access_token(token, [registration: registration, endpoints: endpoints] ++ opts)
    end
  end

  # [Core §6.1](https://www.imsglobal.org/spec/lti/v1p3/#services-exposed-as-additional-claims)
  defp endpoints_from_claims(claims, services) do
    results = Enum.map(services, &{&1, &1.endpoint_from_claims(claims)})

    case for({service, :error} <- results, do: service) do
      [] ->
        {:ok, Map.new(results, fn {service, {:ok, endpoint}} -> {service, endpoint} end)}

      missing ->
        errors =
          for service <- missing do
            ServiceNotAvailable.exception(
              service: service,
              reason: "The launch has no endpoint claim for this service",
              spec_ref: "Core §6.1"
            )
          end

        {:error, Ltix.Errors.combine(errors)}
    end
  end
end
