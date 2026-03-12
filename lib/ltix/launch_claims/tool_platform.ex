defmodule Ltix.LaunchClaims.ToolPlatform do
  @moduledoc """
  Information about the platform instance that initiated the launch.

  `guid` is required and stable for a given platform instance.

  ## Examples

      iex> Ltix.LaunchClaims.ToolPlatform.from_json(%{"guid" => "plat-1", "name" => "LMS"})
      {:ok, %Ltix.LaunchClaims.ToolPlatform{guid: "plat-1", name: "LMS", contact_email: nil, description: nil, url: nil, product_family_code: nil, version: nil}}
  """

  alias Ltix.LaunchClaims.ClaimHelpers

  # [Core §5.4.2](https://www.imsglobal.org/spec/lti/v1p3/#tool-platform-claim)
  @schema Zoi.struct(
            __MODULE__,
            %{
              guid: Zoi.string(coerce: true),
              name: Zoi.string(coerce: true) |> Zoi.optional(),
              contact_email: Zoi.string(coerce: true) |> Zoi.optional(),
              description: Zoi.string(coerce: true) |> Zoi.optional(),
              url: Zoi.string(coerce: true) |> Zoi.optional(),
              product_family_code: Zoi.string(coerce: true) |> Zoi.optional(),
              version: Zoi.string(coerce: true) |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Parse a tool platform claim from a JSON map.

  ## Examples

      iex> Ltix.LaunchClaims.ToolPlatform.from_json(%{"guid" => "plat-1"})
      {:ok, %Ltix.LaunchClaims.ToolPlatform{guid: "plat-1", name: nil, contact_email: nil, description: nil, url: nil, product_family_code: nil, version: nil}}
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(json) when is_map(json) do
    ClaimHelpers.from_json(@schema, json, "tool_platform", "Core §5.4.2")
  end
end
