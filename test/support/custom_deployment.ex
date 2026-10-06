defmodule CustomDeployment do
  @moduledoc false

  # Intentionally different shape from %Ltix.Deployment{}. It includes
  # app-specific fields that %Ltix.Deployment{} doesn't have.

  defstruct [:id, :registration_id, :platform_deployment_id, :label]

  defimpl Ltix.Deployable do
    def to_deployment(dep) do
      Ltix.Deployment.new(dep.platform_deployment_id)
    end
  end
end
