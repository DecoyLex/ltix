defmodule Ltix.Test.SetDeployment do
  @moduledoc false
  # Takes the place of `Ltix.Launch.LookUpDeployment` in
  # `Ltix.Test.build_launch/2`. Sets the launch's `:deployment` and
  # `:source_deployment` to the options of the same name for each launch the
  # lookup would look up, without calling the storage adapter.
  use Ltix.Step

  @impl Ltix.Step
  def call(%Ltix.Launch{errors: [], claims: %{deployment_id: deployment_id}} = launch, opts)
      when deployment_id != nil do
    {:ok,
     %{
       launch
       | deployment: Keyword.fetch!(opts, :deployment),
         source_deployment: Keyword.fetch!(opts, :source_deployment)
     }}
  end

  def call(%Ltix.Launch{} = launch, _opts), do: {:ok, launch}
end
