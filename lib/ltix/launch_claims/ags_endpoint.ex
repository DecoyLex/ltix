defmodule Ltix.LaunchClaims.AGSEndpoint do
  @moduledoc """
  Assignment and Grade Services (AGS) endpoint claim.

  Provides URLs for managing line items and scores. All fields are optional. `:scopes` lists the grade service scopes the tool may request, `:line_items` is the URL of the line items container, and `:line_item` is the URL of the line item coupled to the resource link.

  ## Examples

      iex> Ltix.LaunchClaims.AGSEndpoint.from_json(%{"lineitems" => "https://example.com/lineitems"})
      {:ok, %Ltix.LaunchClaims.AGSEndpoint{scopes: nil, line_items: "https://example.com/lineitems", line_item: nil}}
  """

  alias Ltix.LaunchClaims.ClaimHelpers

  # [AGS §3.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#assignment-and-grade-service-claim)
  @struct_schema Zoi.struct(
                   __MODULE__,
                   %{
                     scopes: Zoi.list(Zoi.string()) |> ClaimHelpers.optional(),
                     line_items: Zoi.string() |> ClaimHelpers.optional(),
                     line_item: Zoi.string() |> ClaimHelpers.optional()
                   },
                   coerce: true
                 )

  @schema ClaimHelpers.rename_claims(@struct_schema, %{
            "scope" => :scopes,
            "lineitems" => :line_items,
            "lineitem" => :line_item
          })

  @doc false
  def schema, do: @schema

  @type t :: unquote(Zoi.type_spec(@struct_schema))
  @enforce_keys Zoi.Struct.enforce_keys(@struct_schema)
  defstruct Zoi.Struct.struct_fields(@struct_schema)

  @doc """
  Parse an AGS endpoint claim from a JSON map.

  ## Examples

      iex> Ltix.LaunchClaims.AGSEndpoint.from_json(%{})
      {:ok, %Ltix.LaunchClaims.AGSEndpoint{scopes: nil, line_items: nil, line_item: nil}}
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(json) do
    ClaimHelpers.from_json(@schema, json, "ags_endpoint", "AGS §3.1")
  end
end
