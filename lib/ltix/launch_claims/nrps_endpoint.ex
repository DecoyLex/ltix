defmodule Ltix.LaunchClaims.NrpsEndpoint do
  @moduledoc """
  Names and Role Provisioning Services (NRPS) endpoint claim.

  Provides a URL for retrieving context membership. All fields are optional.

  ## Examples

      iex> Ltix.LaunchClaims.NrpsEndpoint.from_json(%{"context_memberships_url" => "https://example.com/members"})
      {:ok, %Ltix.LaunchClaims.NrpsEndpoint{context_memberships_url: "https://example.com/members", service_versions: nil}}
  """

  defstruct [:context_memberships_url, :service_versions]

  @type t :: %__MODULE__{
          context_memberships_url: String.t() | nil,
          service_versions: [String.t()] | nil
        }

  @doc """
  Parse an NRPS endpoint claim from a JSON map.

  ## Examples

      iex> Ltix.LaunchClaims.NrpsEndpoint.from_json(%{})
      {:ok, %Ltix.LaunchClaims.NrpsEndpoint{context_memberships_url: nil, service_versions: nil}}
  """
  @spec from_json(map()) :: {:ok, t()}
  def from_json(json) when is_map(json) do
    {:ok,
     %__MODULE__{
       context_memberships_url: json["context_memberships_url"],
       service_versions: json["service_versions"]
     }}
  end
end
