defmodule Ltix.GradeService.Endpoint do
  @moduledoc """
  The grade service endpoint from a launch, with the URLs and scopes for
  calling the grade service.

  From a launch, each field is `nil` when the platform leaves it out. To call
  the grade service later, save the fields and rebuild the endpoint with
  `new/1`. [Persisting Service Endpoints](persisting-service-endpoints.md) has
  an example.
  """

  # [AGS, Assignment and Grade Service claim](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#assignment-and-grade-service-claim)
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

  alias Ltix.HTTP

  # [AGS, Assignment and Grade Service claim](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#assignment-and-grade-service-claim)
  # [Sec §3](https://www.imsglobal.org/spec/security/v1p0/#transport-security)
  @https_url Zoi.refine(Zoi.string(), {HTTP, :https_url, []})

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

  `:scopes` needs at least one scope. `:line_items` and `:line_item` are
  optional HTTPS URLs, or HTTP for a loopback or private network host. The
  fields can include plugin properties by name, and the endpoint has their
  values in `extensions`.
  Returns `Ltix.Errors.Invalid.InvalidField` for a missing, unknown, or
  invalid field.

  ## Examples

  ```elixir
  iex> {:ok, endpoint} = Ltix.GradeService.Endpoint.new(
  ...>   line_item: "https://lms.example.com/lineitems/1",
  ...>   scopes: ["https://purl.imsglobal.org/spec/lti-ags/scope/score"]
  ...> )
  iex> endpoint.line_item
  "https://lms.example.com/lineitems/1"

  iex> {:error, error} = Ltix.GradeService.Endpoint.new(line_item: "https://lms.example.com/lineitems/1")
  iex> Exception.message(error)
  "Ltix.GradeService.Endpoint field :scopes is required"
  ```
  """
  @impl Ltix.Claim
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, Exception.t()}
  # [AGS, Assignment and Grade Service claim](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#assignment-and-grade-service-claim)
  # [Sec §3](https://www.imsglobal.org/spec/security/v1p0/#transport-security)
  def new(attributes) when is_list(attributes) or is_map(attributes),
    do: Ltix.Type.new(__MODULE__, attributes, schema: @new_schema)

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

  @doc """
  Adds an anonymous property of AGS endpoints to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)
end
