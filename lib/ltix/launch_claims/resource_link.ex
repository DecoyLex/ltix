defmodule Ltix.LaunchClaims.ResourceLink do
  @moduledoc """
  A placement of an LTI resource link within a context.

  `id` is required and stable across launches for the same link.

  ## Examples

      iex> Ltix.LaunchClaims.ResourceLink.from_json(%{"id" => "rl-1", "title" => "Quiz"})
      {:ok, %Ltix.LaunchClaims.ResourceLink{id: "rl-1", title: "Quiz", description: nil}}
  """

  alias Ltix.Errors.Invalid.MissingClaim

  defstruct [:id, :title, :description]

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t() | nil,
          description: String.t() | nil
        }

  @doc """
  Parse a resource link claim from a JSON map.

  ## Examples

      iex> Ltix.LaunchClaims.ResourceLink.from_json(%{"id" => "rl-1"})
      {:ok, %Ltix.LaunchClaims.ResourceLink{id: "rl-1", title: nil, description: nil}}
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(%{"id" => id} = json) do
    {:ok,
     %__MODULE__{
       id: id,
       title: json["title"],
       description: json["description"]
     }}
  end

  def from_json(_) do
    {:error, MissingClaim.exception(claim: "resource_link.id", spec_ref: "Core §5.3.5")}
  end
end
