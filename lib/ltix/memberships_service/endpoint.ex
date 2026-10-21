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

  # [NRPS §3.6.1.1](https://www.imsglobal.org/spec/lti-nrps/v2p0/#claim-for-inclusion-in-lti-messages)
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

  @doc """
  Create a memberships endpoint from a URL string.

  ## Examples

      iex> {:ok, endpoint} = Ltix.MembershipsService.Endpoint.new("https://lms.example.com/memberships")
      iex> endpoint.context_memberships_url
      "https://lms.example.com/memberships"

      iex> {:error, error} = Ltix.MembershipsService.Endpoint.new("http://lms.example.com/memberships")
      iex> error.field
      :context_memberships_url
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

      iex> endpoint = Ltix.MembershipsService.Endpoint.new!("https://lms.example.com/memberships")
      iex> endpoint.context_memberships_url
      "https://lms.example.com/memberships"
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
end
