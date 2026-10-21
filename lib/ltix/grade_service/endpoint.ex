defmodule Ltix.GradeService.Endpoint do
  @moduledoc """
  The grade service endpoint from a launch, with the URLs and scopes for
  calling the grade service.

  From a launch, each field is `nil` when the platform leaves it out. To call
  the grade service later, save the fields and rebuild the endpoint with
  `new/1`. [Persisting Service Endpoints](persisting-service-endpoints.md) has
  an example.
  """

  # [AGS §3.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#assignment-and-grade-service-claim)
  use Ltix.Claim,
    claim: "https://purl.imsglobal.org/spec/lti-ags/claim/endpoint",
    name: :ags_endpoint,
    strict: false,
    service: Ltix.GradeService,
    fields: [
      scopes:
        Zoi.list(Zoi.string(),
          description: "The grade service scopes the tool may request.",
          metadata: [json_key: "scope"]
        )
        |> Zoi.optional(),
      line_items:
        Zoi.string(
          description: "The URL of the context's line items.",
          metadata: [json_key: "lineitems"]
        )
        |> Zoi.optional(),
      line_item:
        Zoi.string(
          description:
            "The URL of the [coupled line item](`Ltix.GradeService`), for a resource link that has one.",
          metadata: [json_key: "lineitem"]
        )
        |> Zoi.optional()
    ]

  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.HTTP

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

  @doc """
  Builds an endpoint from its fields, as a keyword list or map.

  `:scopes` is required. `:line_items` and `:line_item` are optional absolute HTTPS URLs that may be `nil`.

  ## Examples

      iex> {:ok, endpoint} = Ltix.GradeService.Endpoint.new(
      ...>   line_item: "https://lms.example.com/lineitems/1",
      ...>   scopes: ["https://purl.imsglobal.org/spec/lti-ags/scope/score"]
      ...> )
      iex> endpoint.line_item
      "https://lms.example.com/lineitems/1"

      iex> {:error, error} = Ltix.GradeService.Endpoint.new(line_item: "https://lms.example.com/lineitems/1")
      iex> Exception.message(error)
      "Ltix.GradeService.Endpoint field :scopes is required"
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
end
