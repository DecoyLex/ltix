defmodule CustomDeployment do
  @moduledoc false

  # Intentionally different shape from %Ltix.Deployment{} — includes
  # app-specific fields that Ltix doesn't know about.

  defstruct [:id, :registration_id, :platform_deployment_id, :label]

  defimpl Ltix.Deployable do
    def to_deployment(dep) do
      Ltix.Deployment.new(dep.platform_deployment_id)
    end
  end
end
