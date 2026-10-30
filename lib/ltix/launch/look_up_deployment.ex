defmodule Ltix.Launch.LookUpDeployment do
  @moduledoc false
  use Ltix.Launch

  alias Ltix.StorageAdapter

  # [Core, Tool Deployment](https://standards.1edtech.org/lti/specifications/core/lti-spec#tool-deployment)
  # [Core, LTI Deployment ID claim](https://standards.1edtech.org/lti/specifications/core/lti-spec#lti-deployment-id-claim)
  @impl Ltix.Step
  def call(
        %Ltix.Launch{errors: [], claims: %{deployment_id: deployment_id}, private: private} =
          launch,
        _opts
      )
      when deployment_id != nil do
    case StorageAdapter.get_deployment(
           private.ltix_storage_adapter,
           launch.source_registration,
           deployment_id,
           private.ltix_storage_adapter_options
         ) do
      {:ok, source_deployment, deployment} ->
        {:ok, %{launch | deployment: deployment, source_deployment: source_deployment}}

      {:error, error} ->
        {:halt, error}
    end
  end

  def call(%Ltix.Launch{} = launch, _opts), do: {:ok, launch}

  @impl Ltix.Ordered
  def after?(Ltix.Launch.Validated), do: true
  def after?(_module), do: false
end
