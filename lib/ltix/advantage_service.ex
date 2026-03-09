defmodule Ltix.AdvantageService do
  @moduledoc """
  Behaviour for LTI Advantage service modules.

  Each Advantage service implements this behaviour to describe its endpoint
  type and required OAuth scopes. `Ltix.OAuth` uses these callbacks to
  validate endpoints, derive scopes, and build authenticated clients,
  without hardcoded knowledge of any specific service.

  ## Implementing a custom service

      defmodule MyApp.ProctorService do
        @behaviour Ltix.AdvantageService

        @impl true
        def endpoint_from_claims(%Ltix.LaunchClaims{} = _claims), do: :error

        @impl true
        def validate_endpoint(%MyApp.ProctorEndpoint{}), do: :ok

        def validate_endpoint(_),
          do: {:error, Ltix.Errors.Invalid.InvalidEndpoint.exception(service: __MODULE__)}

        @impl true
        def scopes(%MyApp.ProctorEndpoint{}),
          do: ["https://example.com/scope/proctoring"]
      end
  """

  @doc "Extract the service's endpoint from launch claims."
  @callback endpoint_from_claims(Ltix.LaunchClaims.t()) :: {:ok, term()} | :error

  @doc "Validate that the given value is a valid endpoint for this service."
  @callback validate_endpoint(term()) :: :ok | {:error, Exception.t()}

  @doc "Return the OAuth scope URIs required by this endpoint."
  @callback scopes(term()) :: [String.t()]
end
