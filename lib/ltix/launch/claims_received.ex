defmodule Ltix.Launch.ClaimsReceived do
  @moduledoc """
  The [launch phase](`m:Ltix.Launch#module-phases`) before Ltix parses the
  claims.

  Order a step after `Ltix.Launch.Verified` and before this phase to change the
  claims before Ltix parses and checks them. Such a step can

    * change `:raw`, the decoded JSON keyed by claim name. Ltix parses and
      checks it as changed, and doesn't verify the change.
    * add a claim to `:claims` by its [short name](`m:Ltix.Core#module-claims`),
      already parsed, such as an `Ltix.Claims.Context` for `:context`. Ltix runs
      the claim's checks and counts it toward the claims the message type
      requires. A claim the platform sent with the same short name replaces it.

  Change an endpoint claim in `:raw`, since Ltix sets `:endpoints` from the
  claims it parses.

  `:errors` has only the errors that other steps returned with
  `{:error, exception}`.
  """
  use Ltix.Launch

  @impl Ltix.Step
  def call(launch, _opts), do: {:ok, launch}

  @impl Ltix.Ordered
  def after?(Ltix.Launch.Verified), do: true
  def after?(_module), do: false
end
