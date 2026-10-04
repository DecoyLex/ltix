defmodule Ltix.LaunchClaims.Parser do
  @moduledoc """
  Defines a behavior for parsing a launch claim's raw value.

  Register a module implementing this behavior, or a 1-arity function
  with the same contract, under `:claim_parsers`. See
  [Custom Claim Parsers](custom-claim-parsers.md).

      defmodule MyApp.AnalyticsClaim do
        use Ltix.LaunchClaims.Parser

        @impl Ltix.LaunchClaims.Parser
        def parse(%{"session_id" => session_id}), do: {:ok, session_id}
        def parse(_value), do: {:error, "missing session_id"}
      end
  """

  @callback parse(value :: term()) :: {:ok, term()} | {:error, term()}

  defmacro __using__(_opts) do
    quote do
      @behaviour Ltix.LaunchClaims.Parser
    end
  end
end
