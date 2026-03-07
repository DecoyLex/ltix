defmodule Ltix.LaunchClaims.AgsEndpoint do
  @moduledoc """
  Assignment and Grade Services (AGS) endpoint claim.

  Provides URLs for managing line items and scores. All fields are optional.

  ## Examples

      iex> Ltix.LaunchClaims.AgsEndpoint.from_json(%{"lineitems" => "https://example.com/lineitems"})
      {:ok, %Ltix.LaunchClaims.AgsEndpoint{scope: nil, lineitems: "https://example.com/lineitems", lineitem: nil}}
  """

  defstruct [:scope, :lineitems, :lineitem]

  @type t :: %__MODULE__{
          scope: [String.t()] | nil,
          lineitems: String.t() | nil,
          lineitem: String.t() | nil
        }

  @doc """
  Parse an AGS endpoint claim from a JSON map.

  ## Examples

      iex> Ltix.LaunchClaims.AgsEndpoint.from_json(%{})
      {:ok, %Ltix.LaunchClaims.AgsEndpoint{scope: nil, lineitems: nil, lineitem: nil}}
  """
  @spec from_json(map()) :: {:ok, t()}
  def from_json(json) when is_map(json) do
    {:ok,
     %__MODULE__{
       scope: json["scope"],
       lineitems: json["lineitems"],
       lineitem: json["lineitem"]
     }}
  end
end
