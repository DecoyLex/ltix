defmodule Ltix.AdvantageService do
  @moduledoc """
  Behaviour for LTI Advantage service modules.

  Each Advantage service implements this behaviour to validate its endpoint
  and name the OAuth scopes it needs. `Ltix.OAuth` uses these callbacks to
  build OAuth clients for any service.

  `Ltix.Launch.get_endpoint/2` returns a launch's endpoint for a service when
  a plugin declares the service's endpoint claim. See `Ltix.Claim` for
  endpoint claims.

  ## Implementing a custom service

      defmodule MyApp.ProctorService do
        @behaviour Ltix.AdvantageService

        @impl true
        def validate_endpoint(%MyApp.ProctorEndpoint{}), do: :ok

        def validate_endpoint(_),
          do: {:error, Ltix.Errors.Invalid.InvalidEndpoint.exception(service: __MODULE__)}

        @impl true
        def scopes(%MyApp.ProctorEndpoint{}),
          do: ["https://example.com/scope/proctoring"]
      end

  Send the service's requests with `Ltix.OAuth.Client.request/3`.
  """

  @doc "Validate that the given value is a valid endpoint for this service."
  @callback validate_endpoint(term()) :: :ok | {:error, Exception.t()}

  @doc "Return the OAuth scope URIs required by this endpoint."
  @callback scopes(term()) :: [String.t()]
end
