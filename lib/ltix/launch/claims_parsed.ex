defmodule Ltix.Launch.ClaimsParsed do
  @moduledoc """
  The [launch phase](`m:Ltix.Launch#module-phases`) after Ltix parses the
  claims and runs their checks.

  A step ordered after it can read `:claims` and `:endpoints`. A malformed claim
  is `nil`, or `[]` for `:roles`.

  `:errors` has an error for the malformed claims and failed checks, which
  groups them when there are several. Steps ordered after this phase still run,
  and `Ltix.handle_callback/3` returns the error when the steps finish.
  """
  use Ltix.Launch

  @impl Ltix.Step
  def call(launch, _opts), do: {:ok, launch}

  @impl Ltix.Ordered
  def after?(Ltix.Launch.ClaimsReceived), do: true
  def after?(_module), do: false
end
