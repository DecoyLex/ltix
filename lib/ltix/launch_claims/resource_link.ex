defmodule Ltix.LaunchClaims.ResourceLink do
  @moduledoc """
  A placement of an LTI resource link within a context.

  `id` is required and stable across launches for the same link.

  ## Examples

      iex> Ltix.LaunchClaims.ResourceLink.from_json(%{"id" => "rl-1", "title" => "Quiz"})
      {:ok, %Ltix.LaunchClaims.ResourceLink{id: "rl-1", title: "Quiz", description: nil}}
  """

  alias Ltix.LaunchClaims.ClaimHelpers

  # [Core §5.3.5](https://www.imsglobal.org/spec/lti/v1p3/#resource-link-claim)
  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(coerce: true),
              title: Zoi.string(coerce: true) |> Zoi.optional(),
              description: Zoi.string(coerce: true) |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Parse a resource link claim from a JSON map.

  ## Examples

      iex> Ltix.LaunchClaims.ResourceLink.from_json(%{"id" => "rl-1"})
      {:ok, %Ltix.LaunchClaims.ResourceLink{id: "rl-1", title: nil, description: nil}}
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(json) when is_map(json) do
    ClaimHelpers.from_json(@schema, json, "resource_link", "Core §5.3.5")
  end
end
