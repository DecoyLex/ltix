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

  alias Ltix.LaunchClaims.ClaimHelpers

  # [NRPS §3.6.1.1](https://www.imsglobal.org/spec/lti-nrps/v2p0/#claim-for-inclusion-in-lti-messages)
  @schema Zoi.struct(
            __MODULE__,
            %{
              context_memberships_url: Zoi.string(coerce: true) |> Zoi.optional(),
              service_versions: Zoi.list(Zoi.string(coerce: true)) |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

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
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(json) when is_map(json) do
    ClaimHelpers.from_json(@schema, json, "memberships_endpoint", "NRPS §3.6.1.1")
  end
end
