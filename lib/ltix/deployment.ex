defmodule Ltix.Deployment do
  @moduledoc """
  Deployment identity
  [Core §3.1.3](https://www.imsglobal.org/spec/lti/v1p3/#tool-deployment).

  > [Core §3.1.3](https://www.imsglobal.org/spec/lti/v1p3/#tool-deployment):
  > "When a user deploys a tool within their tool platform, the platform MUST
  > generate an immutable `deployment_id` identifier to identify the integration."
  """

  alias Ltix.Errors.Invalid.{InvalidClaim, MissingClaim}

  defstruct [:deployment_id]

  @type t :: %__MODULE__{
          deployment_id: String.t()
        }

  @max_length 255

  @doc """
  Create a new deployment with validation.

  ## Validation rules
  [Core §5.3.3](https://www.imsglobal.org/spec/lti/v1p3/#lti-deployment-id-claim)

  - `deployment_id` MUST be a non-empty string
  - `deployment_id` MUST NOT exceed 255 ASCII characters in length
  - `deployment_id` MUST contain only ASCII characters

  ## Examples

      iex> Ltix.Deployment.new("deploy-001")
      {:ok, %Ltix.Deployment{deployment_id: "deploy-001"}}

      Ltix.Deployment.new("")
      #=> {:error, %Ltix.Errors.Invalid.MissingClaim{claim: "deployment_id"}}

  """
  @spec new(String.t() | nil) :: {:ok, t()} | {:error, Exception.t()}
  def new(deployment_id) when is_binary(deployment_id) and byte_size(deployment_id) > 0 do
    cond do
      not String.printable?(deployment_id) or not ascii?(deployment_id) ->
        {:error,
         InvalidClaim.exception(
           claim: "deployment_id",
           value: deployment_id,
           spec_ref: "Core §5.3.3 (ASCII only)"
         )}

      String.length(deployment_id) > @max_length ->
        {:error,
         InvalidClaim.exception(
           claim: "deployment_id",
           value: "#{String.length(deployment_id)} chars",
           spec_ref: "Core §5.3.3 (MUST NOT exceed 255 ASCII characters)"
         )}

      true ->
        {:ok, %__MODULE__{deployment_id: deployment_id}}
    end
  end

  def new(_) do
    {:error,
     MissingClaim.exception(
       claim: "deployment_id",
       spec_ref: "Core §5.3.3"
     )}
  end

  defp ascii?(string), do: string == for(<<c <- string>>, c < 128, into: "", do: <<c>>)
end
