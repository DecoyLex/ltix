defmodule Ltix.MembershipsService.Endpoint do
  @moduledoc """
  The memberships service endpoint from a launch, with the URL for reading
  the context's memberships.

  A launch's endpoint has `nil` for a field the platform leaves out. `new/1`
  requires the URL. To call the memberships service later, save the URL and
  rebuild the endpoint with `new/1`.
  [Persisting Service Endpoints](persisting-service-endpoints.md) has an
  example.
  """

  # [NRPS, Claim for inclusion in LTI messages](https://standards.1edtech.org/lti/specifications/services/names_roles/names-role-provisioning-spec#claim-for-inclusion-in-lti-messages)
  use Ltix.Claim,
    claim: "https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice",
    name: :memberships_endpoint,
    strict: false,
    service: Ltix.MembershipsService,
    fields: [
      context_memberships_url:
        Zoi.string(description: "The URL of the context's memberships.") |> Zoi.optional(),
      service_versions:
        Zoi.list(Zoi.string(),
          description: "The service versions the platform supports, such as `[\"2.0\"]`."
        )
        |> Zoi.optional()
    ]

  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.Errors.Invalid.ServiceNotAvailable

  @new_schema Zoi.struct(
                __MODULE__,
                %{
                  context_memberships_url: Zoi.refine(Zoi.string(), {Ltix.HTTP, :https_url, []}),
                  service_versions: Zoi.list(Zoi.string()) |> Zoi.optional()
                },
                coerce: true,
                unrecognized_keys: :error,
                empty_values: [nil, ""]
              )

  @doc """
  Builds an endpoint from its URL, or from its fields as a keyword list or map.
  The fields can include plugin properties by name, and the endpoint has their
  values in `extensions`.

  The URL must use HTTPS, or HTTP for a loopback or private network host. Returns
  `Ltix.Errors.Invalid.InvalidField` for any other URL, and for an unknown
  or invalid field. Returns `Ltix.Errors.Invalid.ServiceNotAvailable` for
  fields without a URL, or with `:service_versions` that leave out `"2.0"`.

  ## Examples

      iex> {:ok, endpoint} = Ltix.MembershipsService.Endpoint.new("https://lms.example.com/memberships")
      iex> endpoint.context_memberships_url
      "https://lms.example.com/memberships"

      iex> {:ok, endpoint} = Ltix.MembershipsService.Endpoint.new(
      ...>   context_memberships_url: "https://lms.example.com/memberships",
      ...>   service_versions: ["2.0"]
      ...> )
      iex> endpoint.service_versions
      ["2.0"]

      iex> {:error, error} = Ltix.MembershipsService.Endpoint.new("http://lms.example.com/memberships")
      iex> error.field
      :context_memberships_url
  """
  @impl Ltix.Claim
  @spec new(String.t() | nil | keyword() | map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(url_or_fields)

  # [NRPS, Claim for inclusion in LTI messages](https://standards.1edtech.org/lti/specifications/services/names_roles/names-role-provisioning-spec#claim-for-inclusion-in-lti-messages)
  def new(url) when url in [nil, ""],
    do: {:error, InvalidField.required(__MODULE__, :context_memberships_url)}

  def new(url) when is_binary(url), do: new(context_memberships_url: url)

  # [Sec §3](https://www.imsglobal.org/spec/security/v1p0/#transport-security)
  def new(attributes) when is_list(attributes) or is_map(attributes) do
    attributes = Map.new(attributes)

    with :ok <- require_url(attributes[:context_memberships_url]),
         {:ok, endpoint} <- Ltix.Type.new(__MODULE__, attributes, schema: @new_schema),
         do: validate_service_versions(endpoint)
  end

  @doc """
  Same as `new/1` but raises on error.
  """
  @spec new!(String.t() | nil | keyword() | map()) :: t()
  def new!(url_or_fields) do
    case new(url_or_fields) do
      {:ok, endpoint} -> endpoint
      {:error, error} -> raise error
    end
  end

  # [NRPS, LTI 1.3 integration](https://standards.1edtech.org/lti/specifications/services/names_roles/names-role-provisioning-spec#lti-1-3-integration)
  defp require_url(url) when url in [nil, ""],
    do: not_available("The endpoint has no context memberships URL")

  defp require_url(_url), do: :ok

  defp validate_service_versions(%__MODULE__{service_versions: nil} = endpoint),
    do: {:ok, endpoint}

  defp validate_service_versions(%__MODULE__{service_versions: versions} = endpoint) do
    if "2.0" in versions,
      do: {:ok, endpoint},
      else: not_available("The endpoint does not support NRPS version 2.0")
  end

  defp not_available(reason) do
    {:error, ServiceNotAvailable.exception(service: Ltix.MembershipsService, reason: reason)}
  end

  @doc """
  Adds an anonymous property of NRPS endpoints to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)
end
