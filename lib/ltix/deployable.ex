defprotocol Ltix.Deployable do
  @moduledoc """
  Protocol for converting your deployment struct to an `Ltix.Deployment`.

  Implement it for your deployment struct, and your storage adapter can
  return that struct. An `Ltix.Launch` has your struct in `source_deployment`.

      defmodule MyApp.ToolDeployment do
        defstruct [:id, :registration_id, :deployment_id, :label]

        defimpl Ltix.Deployable do
          def to_deployment(dep) do
            Ltix.Deployment.new(dep.deployment_id)
          end
        end
      end

  `Ltix.Deployment` implements this protocol, so your storage adapter can
  also return a `%Deployment{}`. A launch returns the same error as
  `Ltix.Deployment.new/1` for an invalid one.
  """

  @doc """
  Return the `Ltix.Deployment` for the given struct.

  Build it with `Ltix.Deployment.new/1`, which validates the fields.
  """
  @spec to_deployment(t()) :: {:ok, Ltix.Deployment.t()} | {:error, Exception.t()}
  def to_deployment(source)
end
