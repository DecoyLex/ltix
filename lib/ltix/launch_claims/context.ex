defmodule Ltix.LaunchClaims.Context do
  @moduledoc """
  The context (e.g. course or section) in which the launch occurs.

  `id` is required and uniquely identifies the context within a deployment.

  ## Examples

      iex> Ltix.LaunchClaims.Context.from_json(%{"id" => "ctx-1", "label" => "CS101"})
      {:ok, %Ltix.LaunchClaims.Context{id: "ctx-1", label: "CS101", title: nil, type: nil}}
  """

  alias Ltix.Errors.Invalid.MissingClaim

  defstruct [:id, :label, :title, :type]

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t() | nil,
          title: String.t() | nil,
          type: [String.t()] | nil
        }

  @doc """
  Parse a context claim from a JSON map.

  ## Examples

      iex> Ltix.LaunchClaims.Context.from_json(%{"id" => "ctx-1"})
      {:ok, %Ltix.LaunchClaims.Context{id: "ctx-1", label: nil, title: nil, type: nil}}
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(%{"id" => id} = json) do
    {:ok,
     %__MODULE__{
       id: id,
       label: json["label"],
       title: json["title"],
       type: json["type"]
     }}
  end

  def from_json(_) do
    {:error, MissingClaim.exception(claim: "context.id", spec_ref: "Core §5.4.1")}
  end
end
