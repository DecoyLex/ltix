defmodule Ltix.Launch.Validated do
  @moduledoc """
  The [launch phase](`m:Ltix.Launch#module-phases`) after Ltix checks the
  message type and the claims it requires.

  After this phase, a launch without errors has every claim its message type
  requires. Ltix looks up the deployment after this phase. To read
  `:deployment`, order a step after `Ltix.Launch.DeploymentFound`.

  `:errors` can have an error for a message type no plugin declares, and one
  for the required claims the launch is missing.
  [Declare a message type](writing-claim-and-launch-plugins.md#declare-a-message-type)
  says which claims a message type requires. Steps ordered after this phase
  still run.
  """
  use Ltix.Launch

  @impl Ltix.Step
  def call(launch, _opts), do: {:ok, launch}

  @impl Ltix.Ordered
  def after?(Ltix.Launch.ClaimsParsed), do: true
  def after?(_module), do: false
end
