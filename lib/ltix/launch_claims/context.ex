defmodule Ltix.LaunchClaims.Context do
  @moduledoc """
  The context (e.g. course or section) in which the launch occurs.

  `id` is required and uniquely identifies the context within a deployment.

  ## Examples

      iex> Ltix.LaunchClaims.Context.from_json(%{"id" => "ctx-1", "label" => "CS101"})
      {:ok, %Ltix.LaunchClaims.Context{id: "ctx-1", label: "CS101", title: nil, type: nil}}
  """

  alias Ltix.LaunchClaims.ClaimHelpers

  # [Core §5.4.1](https://www.imsglobal.org/spec/lti/v1p3/#context-claim)
  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              label: Zoi.string() |> ClaimHelpers.optional(),
              title: Zoi.string() |> ClaimHelpers.optional(),
              type: Zoi.list(Zoi.string()) |> ClaimHelpers.optional()
            },
            coerce: true
          )

  @doc false
  def schema, do: @schema

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Parse a context claim from a JSON map.

  ## Examples

      iex> Ltix.LaunchClaims.Context.from_json(%{"id" => "ctx-1"})
      {:ok, %Ltix.LaunchClaims.Context{id: "ctx-1", label: nil, title: nil, type: nil}}
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(json) do
    ClaimHelpers.from_json(@schema, json, "context", "Core §5.4.1")
  end

  @doc """
  Serialize a context to a map with the claim's JSON keys, omitting fields that are `nil`.

  ## Examples

      iex> Ltix.LaunchClaims.Context.to_map(%Ltix.LaunchClaims.Context{id: "ctx-1", label: "CS101"})
      %{"id" => "ctx-1", "label" => "CS101"}
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = context) do
    for {field, value} <- Map.from_struct(context), not is_nil(value), into: %{} do
      {Atom.to_string(field), value}
    end
  end
end
