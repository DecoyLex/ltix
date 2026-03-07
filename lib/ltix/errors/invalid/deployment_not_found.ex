defmodule Ltix.Errors.Invalid.DeploymentNotFound do
  @moduledoc "Unknown deployment_id [Core §3.1.3; Core §5.3.3]."
  use Splode.Error, fields: [:deployment_id], class: :invalid

  def message(%{deployment_id: deployment_id}) do
    "Deployment not found: #{deployment_id}"
  end
end
