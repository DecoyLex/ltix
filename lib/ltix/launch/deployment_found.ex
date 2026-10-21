defmodule Ltix.Launch.DeploymentFound do
  @moduledoc """
  The [launch phase](`m:Ltix.Launch#module-phases`) after Ltix looks up the
  deployment, the last phase of a launch.

  A step ordered after it can read `:deployment`, along with
  `:source_deployment`, the record your storage adapter returned for the
  deployment. Ltix doesn't look up the deployment of a launch with errors, so
  in that launch both are `nil`.
  """
  use Ltix.Launch

  @impl Ltix.Step
  def call(launch, _opts), do: {:ok, launch}

  @impl Ltix.Ordered
  def after?(Ltix.Launch.LookUpDeployment), do: true
  def after?(_module), do: false
end
