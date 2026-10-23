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
              guid: Zoi.string(),
              name: Zoi.string() |> ClaimHelpers.optional(),
              contact_email: Zoi.string() |> ClaimHelpers.optional(),
              description: Zoi.string() |> ClaimHelpers.optional(),
              url: Zoi.string() |> ClaimHelpers.optional(),
              product_family_code: Zoi.string() |> ClaimHelpers.optional(),
              version: Zoi.string() |> ClaimHelpers.optional()
            },
            coerce: true
          )

  @doc false
  def schema, do: @schema

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
  def from_json(json) do
    ClaimHelpers.from_json(@schema, json, "tool_platform")
  end
end
