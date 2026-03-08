defmodule Ltix.Deployment do
  @moduledoc """
  A specific installation of a tool on a platform, identified by an
  immutable `deployment_id` assigned by the platform.
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

  - `deployment_id` — non-empty string
  - `deployment_id` — 255 ASCII characters max
  - `deployment_id` — ASCII characters only

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
           message: "deployment_id must contain only ASCII characters",
           spec_ref: "Core §5.3.3 (ASCII only)"
         )}

      String.length(deployment_id) > @max_length ->
        {:error,
         InvalidClaim.exception(
           claim: "deployment_id",
           value: "#{String.length(deployment_id)} chars",
           message: "deployment_id must not exceed 255 ASCII characters",
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
