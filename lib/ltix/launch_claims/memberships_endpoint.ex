defmodule Ltix.LaunchClaims.MembershipsEndpoint do
  @moduledoc """
  Memberships service endpoint claim.

  Provides a URL for retrieving context membership. All fields are optional
  when parsed from launch claims; the `context_memberships_url` is required
  when constructing an endpoint manually via `new/1`.

  ## Examples

      iex> Ltix.LaunchClaims.MembershipsEndpoint.from_json(%{"context_memberships_url" => "https://example.com/members"})
      {:ok, %Ltix.LaunchClaims.MembershipsEndpoint{context_memberships_url: "https://example.com/members", service_versions: nil}}
  """

  defstruct [:context_memberships_url, :service_versions]

  @type t :: %__MODULE__{
          context_memberships_url: String.t() | nil,
          service_versions: [String.t()] | nil
        }

  @doc """
  Create a memberships endpoint from a URL string.

  ## Examples

      iex> Ltix.LaunchClaims.MembershipsEndpoint.new("https://lms.example.com/memberships")
      %Ltix.LaunchClaims.MembershipsEndpoint{context_memberships_url: "https://lms.example.com/memberships", service_versions: nil}
  """
  @spec new(String.t()) :: t()
  def new(url) when is_binary(url) do
    %__MODULE__{context_memberships_url: url}
  end

  @doc """
  Parse a memberships endpoint claim from a JSON map.

  ## Examples

      iex> Ltix.LaunchClaims.MembershipsEndpoint.from_json(%{})
      {:ok, %Ltix.LaunchClaims.MembershipsEndpoint{context_memberships_url: nil, service_versions: nil}}
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
