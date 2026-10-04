defmodule Ltix.Deployment do
  @moduledoc """
  A specific installation of a tool on a platform, identified by an
  immutable `deployment_id` assigned by the platform.
  """

  alias Ltix.Errors.Invalid.InvalidField

  @enforce_keys [:deployment_id]
  defstruct [:deployment_id]

  @type t :: %__MODULE__{
          deployment_id: String.t()
        }

  @max_length 255

  @doc """
  Create a new deployment with validation.

  ## Validation rules

  - `deployment_id` — non-empty string
  - `deployment_id` — 255 ASCII characters max
  - `deployment_id` — ASCII characters only

  ## Examples

      iex> Ltix.Deployment.new("deploy-001")
      {:ok, %Ltix.Deployment{deployment_id: "deploy-001"}}

      Ltix.Deployment.new("")
      #=> {:error, %Ltix.Errors.Invalid.InvalidField{field: :deployment_id, value: ""}}

  """
  # [Core §5.3.3](https://www.imsglobal.org/spec/lti/v1p3/#lti-deployment-id-claim)
  @spec new(String.t() | nil) :: {:ok, t()} | {:error, Exception.t()}
  def new(nil) do
    {:error, InvalidField.required(__MODULE__, :deployment_id)}
  end

  def new(deployment_id) when is_binary(deployment_id) and deployment_id != "" do
    cond do
      not ascii?(deployment_id) ->
        invalid(deployment_id, "must contain only ASCII characters", "Core §5.3.3 (ASCII only)")

      byte_size(deployment_id) > @max_length ->
        invalid(
          deployment_id,
          "must not exceed 255 ASCII characters",
          "Core §5.3.3 (MUST NOT exceed 255 ASCII characters)"
        )

      true ->
        {:ok, %__MODULE__{deployment_id: deployment_id}}
    end
  end

  def new(deployment_id), do: invalid(deployment_id, "must be a non-empty string", "Core §5.3.3")

  defp ascii?(string), do: String.printable?(string) and string =~ ~r/\A[\x00-\x7F]*\z/

  defp invalid(deployment_id, reason, spec_ref) do
    {:error, InvalidField.invalid(__MODULE__, :deployment_id, deployment_id, reason, spec_ref)}
  end
end

defimpl Ltix.Deployable, for: Ltix.Deployment do
  def to_deployment(deployment), do: Ltix.Deployment.new(deployment.deployment_id)
end
