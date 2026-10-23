defmodule Ltix.LaunchClaims.AGSEndpoint do
  @moduledoc """
  Assignment and Grade Services (AGS) endpoint claim.

  Provides URLs for managing line items and scores. `:scopes` lists the grade service scopes the tool may request, `:line_items` is the URL of the line items container, and `:line_item` is the URL of the line item coupled to the resource link.

  Launches include this claim. To call the grade service outside a launch, build the endpoint with `new/1` from the URLs and scopes you saved.

  ## Examples

      iex> Ltix.LaunchClaims.AGSEndpoint.from_json(%{"lineitems" => "https://example.com/lineitems"})
      {:ok, %Ltix.LaunchClaims.AGSEndpoint{scopes: nil, line_items: "https://example.com/lineitems", line_item: nil}}
  """

  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.HTTP
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

  # [AGS §3.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#assignment-and-grade-service-claim)
  # [Sec §3](https://www.imsglobal.org/spec/security/v1p0/#transport-security)
  @https_url Zoi.refine(Zoi.string(), {__MODULE__, :validate_url, []})

  @new_schema Zoi.struct(
                __MODULE__,
                %{
                  scopes: Zoi.list(Zoi.string()) |> Zoi.min(1),
                  line_items: Zoi.optional(@https_url),
                  line_item: Zoi.optional(@https_url)
                },
                coerce: true,
                unrecognized_keys: :error,
                empty_values: [nil]
              )

  @doc false
  def schema, do: @schema

  @type t :: unquote(Zoi.type_spec(@struct_schema))
  @enforce_keys Zoi.Struct.enforce_keys(@struct_schema)
  defstruct Zoi.Struct.struct_fields(@struct_schema)

  @doc """
  Build an endpoint from a keyword list or a map.

  `:scopes` is required. `:line_items` and `:line_item` are optional absolute HTTPS URLs that may be `nil`.

  ## Examples

      iex> Ltix.LaunchClaims.AGSEndpoint.new(
      ...>   line_item: "https://lms.example.com/lineitems/1",
      ...>   scopes: ["https://purl.imsglobal.org/spec/lti-ags/scope/score"]
      ...> )
      {:ok, %Ltix.LaunchClaims.AGSEndpoint{scopes: ["https://purl.imsglobal.org/spec/lti-ags/scope/score"], line_items: nil, line_item: "https://lms.example.com/lineitems/1"}}

      iex> {:error, error} = Ltix.LaunchClaims.AGSEndpoint.new(line_item: "https://lms.example.com/lineitems/1")
      iex> Exception.message(error)
      "Ltix.LaunchClaims.AGSEndpoint field :scopes is required"
  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, Exception.t()}
  # [AGS §3.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#assignment-and-grade-service-claim)
  # [Sec §3](https://www.imsglobal.org/spec/security/v1p0/#transport-security)
  def new(attributes) when is_list(attributes) or is_map(attributes) do
    InvalidField.parse(__MODULE__, @new_schema, Map.new(attributes))
  end

  @doc """
  Same as `new/1` but raises on error.
  """
  @spec new!(keyword() | map()) :: t()
  def new!(attributes) do
    case new(attributes) do
      {:ok, endpoint} -> endpoint
      {:error, error} -> raise error
    end
  end

  @doc false
  @spec validate_url(term(), keyword()) :: :ok | {:error, String.t()}
  def validate_url(url, _opts) do
    case HTTP.validate_url(url) do
      {:ok, _uri} -> :ok
      {:error, _error} -> {:error, "must be an absolute HTTPS URL"}
    end
  end

  @doc """
  Parse an AGS endpoint claim from a JSON map.

  ## Examples

      iex> Ltix.LaunchClaims.AGSEndpoint.from_json(%{})
      {:ok, %Ltix.LaunchClaims.AGSEndpoint{scopes: nil, line_items: nil, line_item: nil}}
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(json) do
    ClaimHelpers.from_json(
      @schema,
      json,
      "https://purl.imsglobal.org/spec/lti-ags/claim/endpoint"
    )
  end
end
