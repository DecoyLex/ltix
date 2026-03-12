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
              id: Zoi.string(coerce: true),
              label: Zoi.string(coerce: true) |> Zoi.optional(),
              title: Zoi.string(coerce: true) |> Zoi.optional(),
              type: Zoi.list(Zoi.string(coerce: true)) |> Zoi.optional()
            },
            coerce: true
          )

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
  def from_json(json) when is_map(json) do
    ClaimHelpers.from_json(@schema, json, "context", "Core §5.4.1")
  end
end
