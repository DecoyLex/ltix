defmodule CustomDeployment do
  @moduledoc false

  defstruct [:id, :registration_id, :deployment_id, :label]

  defimpl Ltix.Deployable do
    def to_deployment(dep) do
      Ltix.Deployment.new(dep.deployment_id)
    end
  end
end
