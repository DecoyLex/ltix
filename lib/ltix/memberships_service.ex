defmodule Ltix.MembershipsService do
  @moduledoc """
  Query context membership (roster) from a platform using the
  [Names and Roles Provisioning Service (NRPS) v2.0](https://www.imsglobal.org/spec/lti-nrps/v2p0/).

  Given a successful LTI 1.3 launch that includes the memberships endpoint
  claim, retrieve the list of users enrolled in the course or resource link.

  ## From a launch context

      {:ok, client} = Ltix.MembershipsService.authenticate(launch_context)
      {:ok, roster} = Ltix.MembershipsService.list_members(client)

      Enum.each(roster, fn member ->
        IO.puts("\#{member.name}: \#{inspect(member.roles)}")
      end)

  ## From a registration

      alias Ltix.LaunchClaims.MembershipsEndpoint

      {:ok, client} = Ltix.MembershipsService.authenticate(registration,
        endpoint: MembershipsEndpoint.new!("https://lms.example.com/memberships")
      )

      {:ok, roster} = Ltix.MembershipsService.list_members(client, role: :learner)

  ## Streaming large rosters

      {:ok, stream} = Ltix.MembershipsService.stream_members(client)

      stream
      |> Stream.filter(&(&1.status == :active))
      |> Enum.each(&process_member/1)
  """

  @behaviour Ltix.AdvantageService

  alias Ltix.AdvantageService.Operation
  alias Ltix.Errors.Invalid.InvalidEndpoint
  alias Ltix.Errors.Invalid.InvalidOption
  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.HTTP
  alias Ltix.LaunchClaims
  alias Ltix.LaunchClaims.MembershipsEndpoint
  alias Ltix.LaunchClaims.Role
  alias Ltix.LaunchContext
  alias Ltix.MembershipsService.MembershipContainer
  alias Ltix.OAuth
  alias Ltix.OAuth.Client
  alias Ltix.Options
  alias Ltix.Pagination
  alias Ltix.Registerable

  @nrps_scope "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"
  @media_type "application/vnd.ims.lti-nrps.v2.membershipcontainer+json"

  @impl Ltix.AdvantageService
  # [NRPS §3.6.1.1](https://www.imsglobal.org/spec/lti-nrps/v2p0/#lti-1-3-integration)
  def endpoint_from_claims(%LaunchClaims{
        memberships_endpoint: %MembershipsEndpoint{} = endpoint
      }),
      do: {:ok, endpoint}

  def endpoint_from_claims(_claims), do: :error

  @impl Ltix.AdvantageService
  def validate_endpoint(%MembershipsEndpoint{context_memberships_url: url}) when url in [nil, ""],
    do: not_available("The endpoint has no context memberships URL")

  def validate_endpoint(%MembershipsEndpoint{} = endpoint) do
    with :ok <- MembershipsEndpoint.validate_url(endpoint),
         do: validate_service_version(endpoint)
  end

  def validate_endpoint(_),
    do: {:error, InvalidEndpoint.exception(service: __MODULE__, spec_ref: "NRPS §3.6.1")}

  @impl Ltix.AdvantageService
  # [NRPS §3.6.1.2](https://www.imsglobal.org/spec/lti-nrps/v2p0/#scope-for-access)
  def scopes(%MembershipsEndpoint{}), do: [@nrps_scope]

  @auth_fields Client.option_fields()

  @context_auth_schema Zoi.keyword(@auth_fields, unrecognized_keys: :error)

  @registration_auth_schema Zoi.keyword(
                              [
                                endpoint:
                                  Zoi.struct(MembershipsEndpoint,
                                    description:
                                      "MembershipsEndpoint struct for the service endpoint."
                                  )
                                  |> Zoi.required()
                              ] ++ @auth_fields,
                              unrecognized_keys: :error
                            )

  @doc """
  Acquire an OAuth token for the memberships service.

  Accepts a `%LaunchContext{}` or any struct implementing `Ltix.Registerable`
  (including `Ltix.Registration`). With a launch context, the endpoint is
  extracted from the launch claims. With a registration, pass the endpoint
  via the `:endpoint` option.

  ## From a launch context

      {:ok, client} = Ltix.MembershipsService.authenticate(launch_context)

  ## From a registration

      {:ok, client} = Ltix.MembershipsService.authenticate(registration,
        endpoint: MembershipsEndpoint.new!("https://lms.example.com/memberships")
      )

  ## Options (launch context)

  #{Zoi.describe(@context_auth_schema)}

  ## Options (registration)

  #{Zoi.describe(@registration_auth_schema)}
  """
  @spec authenticate(LaunchContext.t() | Registerable.t(), keyword()) ::
          {:ok, Client.t()} | {:error, Exception.t()}
  def authenticate(context_or_registerable, opts \\ [])

  def authenticate(%LaunchContext{} = context, opts) do
    opts = Options.parse!(opts, @context_auth_schema)
    OAuth.authenticate(context, Keyword.put(opts, :services, [__MODULE__]))
  end

  def authenticate(registerable, opts) do
    opts = Options.parse!(opts, @registration_auth_schema)
    {endpoint, opts} = Keyword.pop!(opts, :endpoint)
    OAuth.authenticate(registerable, Keyword.put(opts, :endpoints, %{__MODULE__ => endpoint}))
  end

  @doc """
  Same as `authenticate/2` but raises on error.
  """
  @spec authenticate!(LaunchContext.t() | Registerable.t(), keyword()) :: Client.t()
  def authenticate!(context_or_registerable, opts \\ []) do
    case authenticate(context_or_registerable, opts) do
      {:ok, client} -> client
      {:error, error} -> raise error
    end
  end

  @query_fields [
    endpoint:
      Zoi.struct(MembershipsEndpoint,
        description: "Override the endpoint stored on the client."
      ),
    role:
      Zoi.union([Zoi.atom(), Zoi.string(), Zoi.struct(Role)],
        description:
          "Filter by role. Accepts a role atom (e.g., `:learner`), URI string, " <>
            "`%Role{}` struct, or short name string (e.g., `\"Learner\"`)."
      ),
    resource_link_id: Zoi.string(description: "Query resource link membership."),
    per_page:
      Zoi.integer(
        description: "Page size hint. The platform may return more or fewer than requested."
      )
      |> Zoi.positive()
  ]

  @list_members_schema Zoi.keyword(
                         @query_fields ++
                           [
                             max_members:
                               Zoi.union(
                                 [Zoi.integer() |> Zoi.positive(), Zoi.literal(:infinity)],
                                 description:
                                   "Safety limit for eager fetch. Returns a `CollectionTooLarge` error " <>
                                     "if exceeded. Set to `:infinity` to disable."
                               )
                               |> Zoi.default(10_000)
                           ],
                         unrecognized_keys: :error
                       )

  @stream_members_schema Zoi.keyword(@query_fields, unrecognized_keys: :error)

  @doc """
  Fetch all members from the memberships endpoint.

  Follows all `rel="next"` pagination links and returns a complete
  `%MembershipContainer{}`. The container implements `Enumerable`,
  so you can pipe it directly into `Enum` or `Stream` functions.

  ## Options

  #{Zoi.describe(@list_members_schema)}
  """
  # [NRPS §2.4](https://www.imsglobal.org/spec/lti-nrps/v2p0/#membership-container-media-type)
  @spec list_members(Client.t(), keyword()) ::
          {:ok, MembershipContainer.t()} | {:error, Exception.t()}
  def list_members(%Client{} = client, opts \\ []) do
    opts = Options.parse!(opts, @list_members_schema)
    {max, opts} = Keyword.pop!(opts, :max_members)

    with_pages(:list_members, client, opts, fn pages ->
      limit_error = [service: __MODULE__, option: :max_members, spec_ref: "NRPS §2.4.2"]

      with {:ok, [first | _] = containers} <-
             Operation.collect(containers(pages), max, limit_error, &length(&1.members)) do
        {:ok, %{first | members: Enum.flat_map(containers, & &1.members)}}
      end
    end)
  end

  @doc """
  Same as `list_members/2` but raises on error.
  """
  @spec list_members!(Client.t(), keyword()) :: MembershipContainer.t()
  def list_members!(%Client{} = client, opts \\ []) do
    case list_members(client, opts) do
      {:ok, container} -> container
      {:error, error} -> raise error
    end
  end

  @doc """
  Fetch members as a lazy stream.

  Returns `{:ok, stream}` where each element is a `%Member{}`.
  Use this instead of `list_members/2` for large rosters where you
  want to process members incrementally or stop early.
  Later page failures and member parsing errors raise during enumeration.

  Streams take no `:max_members` limit because they fetch one page at a
  time. Use `Stream.take/2` to stop after a number of members.

  ## Options

  #{Zoi.describe(@stream_members_schema)}
  """
  # [NRPS §2.4.2](https://www.imsglobal.org/spec/lti-nrps/v2p0/#limit-query-parameter)
  @spec stream_members(Client.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def stream_members(%Client{} = client, opts \\ []) do
    opts = Options.parse!(opts, @stream_members_schema)

    with_pages(:stream_members, client, opts, fn pages ->
      {:ok, Stream.flat_map(Operation.stream(containers(pages)), & &1.members)}
    end)
  end

  @doc """
  Same as `stream_members/2` but raises on error.
  """
  @spec stream_members!(Client.t(), keyword()) :: Enumerable.t()
  def stream_members!(%Client{} = client, opts \\ []) do
    case stream_members(client, opts) do
      {:ok, stream} -> stream
      {:error, error} -> raise error
    end
  end

  defp with_pages(operation, client, opts, consume) do
    url =
      with {:ok, endpoint} <- resolve_endpoint(client, opts),
           do: {:ok, endpoint.context_memberships_url}

    Operation.run([:ltix, :memberships_service, operation], client, [@nrps_scope], url, fn url ->
      with {:ok, pages} <-
             Pagination.stream_results(url, request_headers(client),
               params: query_params(opts),
               req_options: HTTP.req_options(client.req_options, __MODULE__),
               local_network_access: client.local_network_access
             ) do
        consume.(pages)
      end
    end)
  end

  # Emits `{:ok, container}` or `{:error, error}` for each page, so consumers
  # stop at the first failure without fetching later pages.
  defp containers(pages) do
    Stream.map(pages, fn
      {:ok, body} -> MembershipContainer.from_json(body)
      {:error, _error} = error -> error
    end)
  end

  defp request_headers(%Client{token: %{access_token: token}}) do
    [
      {"accept", @media_type},
      {"authorization", "Bearer #{token}"}
    ]
  end

  # The `:endpoint` option overrides the client's endpoint and is validated like it.
  defp resolve_endpoint(%Client{} = client, opts) do
    case Keyword.fetch(opts, :endpoint) do
      {:ok, endpoint} -> validated(endpoint)
      :error -> client_endpoint(client)
    end
  end

  defp validated(endpoint) do
    with :ok <- validate_endpoint(endpoint), do: {:ok, endpoint}
  end

  defp client_endpoint(%Client{endpoints: %{__MODULE__ => endpoint}}), do: {:ok, endpoint}

  defp client_endpoint(_client) do
    not_available(
      "The client has no memberships service endpoint. Authenticate with one or pass the endpoint option"
    )
  end

  # [NRPS §2.4.1](https://www.imsglobal.org/spec/lti-nrps/v2p0/#role-query-parameter)
  defp query_params(opts) do
    params = %{}

    params =
      case Keyword.get(opts, :role) do
        nil -> params
        role -> Map.put(params, "role", resolve_role(role))
      end

    params =
      case Keyword.get(opts, :per_page) do
        nil -> params
        per_page -> Map.put(params, "limit", Integer.to_string(per_page))
      end

    # [NRPS §3](https://www.imsglobal.org/spec/lti-nrps/v2p0/#resource-link-level-membership-service)
    case Keyword.get(opts, :resource_link_id) do
      nil -> params
      rlid -> Map.put(params, "rlid", rlid)
    end
  end

  defp resolve_role(uri) when is_binary(uri), do: uri

  defp resolve_role(role) do
    Role.to_uri!(if is_atom(role), do: Role.from_atom(role), else: role)
  rescue
    ArgumentError ->
      reraise InvalidOption,
              [key: :role, value: role, reason: "it is not a known role"],
              __STACKTRACE__
  end

  # [NRPS §3.6.1](https://www.imsglobal.org/spec/lti-nrps/v2p0/#lti-1-3-integration)
  defp validate_service_version(%MembershipsEndpoint{service_versions: nil}), do: :ok

  defp validate_service_version(%MembershipsEndpoint{service_versions: versions}) do
    if "2.0" in versions do
      :ok
    else
      not_available("The endpoint does not support NRPS version 2.0")
    end
  end

  defp not_available(reason) do
    {:error,
     ServiceNotAvailable.exception(service: __MODULE__, reason: reason, spec_ref: "NRPS §3.6.1")}
  end

  @doc false
  @spec media_type(:membership_container) :: String.t()
  def media_type(:membership_container), do: @media_type
end
