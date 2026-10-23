defmodule Ltix.LaunchClaims.MembershipsEndpoint do
  @moduledoc """
  Memberships service endpoint claim.

  Provides a URL for retrieving context membership. All fields are optional
  when parsed from launch claims. An absolute HTTPS `context_memberships_url`
  is required when constructing an endpoint manually via `new/1`.

  ## Examples

      iex> Ltix.LaunchClaims.MembershipsEndpoint.from_json(%{"context_memberships_url" => "https://example.com/members"})
      {:ok, %Ltix.LaunchClaims.MembershipsEndpoint{context_memberships_url: "https://example.com/members", service_versions: nil}}
  """

  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.LaunchClaims.ClaimHelpers

  # [NRPS §3.6.1.1](https://www.imsglobal.org/spec/lti-nrps/v2p0/#claim-for-inclusion-in-lti-messages)
  @schema Zoi.struct(
            __MODULE__,
            %{
              context_memberships_url: Zoi.string() |> ClaimHelpers.optional(),
              service_versions: Zoi.list(Zoi.string()) |> ClaimHelpers.optional()
            },
            coerce: true
          )

  @doc false
  def schema, do: @schema

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Create a memberships endpoint from a URL string.

  ## Examples

      iex> Ltix.LaunchClaims.MembershipsEndpoint.new("https://lms.example.com/memberships")
      {:ok, %Ltix.LaunchClaims.MembershipsEndpoint{context_memberships_url: "https://lms.example.com/memberships", service_versions: nil}}

      Ltix.LaunchClaims.MembershipsEndpoint.new("http://lms.example.com/memberships")
      #=> {:error, %Ltix.Errors.Invalid.InvalidField{field: :context_memberships_url}}
  """
  @spec new(String.t() | nil) :: {:ok, t()} | {:error, Exception.t()}
  # [NRPS §3.6.1.1](https://www.imsglobal.org/spec/lti-nrps/v2p0/#claim-for-inclusion-in-lti-messages)
  def new(url) when url in [nil, ""] do
    {:error, InvalidField.required(__MODULE__, :context_memberships_url)}
  end

  def new(url) do
    endpoint = %__MODULE__{context_memberships_url: url}
    with :ok <- validate_url(endpoint), do: {:ok, endpoint}
  end

  @doc """
  Same as `new/1` but raises on an invalid URL.

  ## Examples

      iex> Ltix.LaunchClaims.MembershipsEndpoint.new!("https://lms.example.com/memberships")
      %Ltix.LaunchClaims.MembershipsEndpoint{context_memberships_url: "https://lms.example.com/memberships", service_versions: nil}
  """
  @spec new!(String.t()) :: t()
  def new!(url) do
    case new(url) do
      {:ok, endpoint} -> endpoint
      {:error, error} -> raise error
    end
  end

  @doc false
  # [Sec §3](https://www.imsglobal.org/spec/security/v1p0/#transport-security)
  @spec validate_url(t()) :: :ok | {:error, Exception.t()}
  def validate_url(%__MODULE__{context_memberships_url: url}) do
    case Ltix.HTTP.validate_url(url) do
      {:ok, _uri} ->
        :ok

      {:error, _} ->
        {:error,
         InvalidField.invalid(
           __MODULE__,
           :context_memberships_url,
           url,
           "must be an absolute HTTPS URL"
         )}
    end
  end

  @doc """
  Parse a memberships endpoint claim from a JSON map.

  ## Examples

      iex> Ltix.LaunchClaims.MembershipsEndpoint.from_json(%{})
      {:ok, %Ltix.LaunchClaims.MembershipsEndpoint{context_memberships_url: nil, service_versions: nil}}
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(json) do
    ClaimHelpers.from_json(
      @schema,
      json,
      "https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice"
    )
  end
end
