defmodule Ltix.Launch.LookUpDeployment do
  @moduledoc false
  use Ltix.Launch

  alias Ltix.StorageAdapter

  # [Core §3.1.3](https://www.imsglobal.org/spec/lti/v1p3/#tool-deployment)
  # [Core §5.3.3](https://www.imsglobal.org/spec/lti/v1p3/#lti-deployment-id-claim)
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
