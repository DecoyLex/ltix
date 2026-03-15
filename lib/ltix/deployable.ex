defprotocol Ltix.Deployable do
  @moduledoc """
  Protocol for extracting an `Ltix.Deployment` from a custom struct.

  Implement this protocol on your own deployment struct so that
  `Ltix.StorageAdapter` callbacks can return your struct directly.
  The library calls the protocol internally to extract the
  `Ltix.Deployment` it needs for launch validation. Your original
  struct is preserved in the `Ltix.LaunchContext` returned after a
  successful launch.

      defmodule MyApp.ToolDeployment do
        defstruct [:id, :registration_id, :deployment_id, :label]

        defimpl Ltix.Deployable do
          def to_deployment(dep) do
            Ltix.Deployment.new(dep.deployment_id)
          end
        end
      end

  `Ltix.Deployment` itself implements this protocol as an identity
  transform, so existing code that returns `%Deployment{}` from storage
  adapter callbacks continues to work.
  """

  @doc """
  Extract an `Ltix.Deployment` from the given struct.

  Implementations should typically delegate to `Ltix.Deployment.new/1`
  so that field validation is applied.
  """
  @spec to_deployment(t()) :: {:ok, Ltix.Deployment.t()} | {:error, Exception.t()}
  def to_deployment(source)
end
