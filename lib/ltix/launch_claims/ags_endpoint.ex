defmodule Ltix.LaunchClaims.AgsEndpoint do
  @moduledoc """
  Assignment and Grade Services (AGS) endpoint claim.

  Provides URLs for managing line items and scores. All fields are optional.

  ## Examples

      iex> Ltix.LaunchClaims.AgsEndpoint.from_json(%{"lineitems" => "https://example.com/lineitems"})
      {:ok, %Ltix.LaunchClaims.AgsEndpoint{scope: nil, lineitems: "https://example.com/lineitems", lineitem: nil}}
  """

  alias Ltix.LaunchClaims.ClaimHelpers

  # [AGS §3.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#assignment-and-grade-service-claim)
  @schema Zoi.struct(
            __MODULE__,
            %{
              scope: Zoi.list(Zoi.string(coerce: true)) |> Zoi.optional(),
              lineitems: Zoi.string(coerce: true) |> Zoi.optional(),
              lineitem: Zoi.string(coerce: true) |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Parse an AGS endpoint claim from a JSON map.

  ## Examples

      iex> Ltix.LaunchClaims.AgsEndpoint.from_json(%{})
      {:ok, %Ltix.LaunchClaims.AgsEndpoint{scope: nil, lineitems: nil, lineitem: nil}}
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(json) when is_map(json) do
    ClaimHelpers.from_json(@schema, json, "ags_endpoint", "AGS §3.1")
  end
end
