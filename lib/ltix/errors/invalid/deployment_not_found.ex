defmodule Ltix.Errors.Invalid.DeploymentNotFound do
  @moduledoc "Unknown deployment ID."
  use Ltix.Errors, fields: [:deployment_id], class: :invalid

  def message(%{deployment_id: deployment_id}) do
    "Deployment not found: #{deployment_id}"
  end
end
