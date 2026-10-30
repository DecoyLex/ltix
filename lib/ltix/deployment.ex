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

  - `deployment_id` - non-empty string
  - `deployment_id` - 255 ASCII characters max
  - `deployment_id` - ASCII characters only

  ## Examples

  ```elixir
  iex> Ltix.Deployment.new("deploy-001")
  {:ok, %Ltix.Deployment{deployment_id: "deploy-001"}}

  Ltix.Deployment.new("")
  #=> {:error, %Ltix.Errors.Invalid.InvalidField{field: :deployment_id, value: ""}}
  ```

  """
  # [Core, LTI Deployment ID claim](https://standards.1edtech.org/lti/specifications/core/lti-spec#lti-deployment-id-claim)
  @spec new(String.t() | nil) :: {:ok, t()} | {:error, Exception.t()}
  def new(nil) do
    {:error, InvalidField.required(__MODULE__, :deployment_id)}
  end

  def new(deployment_id) when is_binary(deployment_id) and deployment_id != "" do
    cond do
      !ascii?(deployment_id) ->
        invalid(deployment_id, "must contain only ASCII characters")

      byte_size(deployment_id) > @max_length ->
        invalid(
          deployment_id,
          "must not exceed 255 ASCII characters"
        )

      true ->
        {:ok, %__MODULE__{deployment_id: deployment_id}}
    end
  end

  def new(deployment_id), do: invalid(deployment_id, "must be a non-empty string")

  @doc """
  Same as `new/1`, but returns the deployment or raises the error.

  ## Examples

  ```elixir
  iex> Ltix.Deployment.new!("deploy-001")
  %Ltix.Deployment{deployment_id: "deploy-001"}
  ```
  """
  @spec new!(String.t() | nil) :: t()
  def new!(deployment_id) do
    case new(deployment_id) do
      {:ok, deployment} -> deployment
      {:error, error} -> raise error
    end
  end

  defp ascii?(string), do: String.printable?(string) && string =~ ~r/\A[\x00-\x7F]*\z/

  defp invalid(deployment_id, reason) do
    {:error, InvalidField.invalid(__MODULE__, :deployment_id, deployment_id, reason)}
  end
end

defimpl Ltix.Deployable, for: Ltix.Deployment do
  def to_deployment(deployment), do: Ltix.Deployment.new(deployment.deployment_id)
end
