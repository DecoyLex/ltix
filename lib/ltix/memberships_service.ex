defmodule Ltix.MembershipsService do
  @moduledoc """
  Query context membership (roster) from a platform using the
  [Names and Roles Provisioning Service (NRPS) v2.0](https://www.imsglobal.org/spec/lti-nrps/v2p0/).

  Given a successful LTI 1.3 launch that includes the memberships endpoint
  claim, retrieve the list of users enrolled in the course or resource link.

  ## From a launch context

      {:ok, client} = Ltix.MembershipsService.authenticate(launch_context)
      {:ok, roster} = Ltix.MembershipsService.get_members(client)

      Enum.each(roster, fn member ->
        IO.puts("\#{member.name}: \#{inspect(member.roles)}")
      end)

  ## From a registration

      alias Ltix.LaunchClaims.MembershipsEndpoint

      {:ok, client} = Ltix.MembershipsService.authenticate(registration,
        endpoint: MembershipsEndpoint.new("https://lms.example.com/memberships")
      )

      {:ok, roster} = Ltix.MembershipsService.get_members(client, role: :learner)

  ## Streaming large rosters

      {:ok, stream} = Ltix.MembershipsService.stream_members(client)

      stream
      |> Stream.filter(&(&1.status == :active))
      |> Enum.each(&process_member/1)
  """

  @behaviour Ltix.AdvantageService

  alias Ltix.MembershipsService.Member
  alias Ltix.MembershipsService.MembershipContainer

  alias Ltix.LaunchClaims
  alias Ltix.LaunchClaims.Context
  alias Ltix.LaunchClaims.MembershipsEndpoint
  alias Ltix.LaunchClaims.Role
  alias Ltix.LaunchContext

  alias Ltix.OAuth
  alias Ltix.OAuth.Client
  alias Ltix.Pagination
  alias Ltix.Registerable
  alias Ltix.Registration

  alias Ltix.Errors.Invalid.InvalidEndpoint
  alias Ltix.Errors.Invalid.MalformedResponse
  alias Ltix.Errors.Invalid.RosterTooLarge
  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.Errors.Security.AccessTokenExpired

  @nrps_scope "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"
  @media_type "application/vnd.ims.lti-nrps.v2.membershipcontainer+json"

  @impl Ltix.AdvantageService
  # [NRPS §3.6.1.1](https://www.imsglobal.org/spec/lti-nrps/v2p0/#lti-1-3-integration)
  def endpoint_from_claims(%LaunchClaims{memberships_endpoint: %MembershipsEndpoint{} = ep}),
    do: {:ok, ep}

  def endpoint_from_claims(_), do: :error

  @impl Ltix.AdvantageService
  def validate_endpoint(%MembershipsEndpoint{}), do: :ok

  def validate_endpoint(_),
    do: {:error, InvalidEndpoint.exception(service: __MODULE__, spec_ref: "NRPS §3.6.1")}

  @impl Ltix.AdvantageService
  # [NRPS §3.6.1.2](https://www.imsglobal.org/spec/lti-nrps/v2p0/#scope-for-access)
  def scopes(%MembershipsEndpoint{}), do: [@nrps_scope]

  @context_auth_schema Zoi.keyword(
                         req_options:
                           Zoi.keyword(Zoi.any(),
                             description: "Options passed through to `Req.request/2`."
                           )
                           |> Zoi.default([])
                       )

  @registration_auth_schema Zoi.keyword(
                              endpoint:
                                Zoi.struct(MembershipsEndpoint,
                                  description:
                                    "MembershipsEndpoint struct for the service endpoint."
                                )
                                |> Zoi.required(),
                              req_options:
                                Zoi.keyword(Zoi.any(),
                                  description: "Options passed through to `Req.request/2`."
                                )
                                |> Zoi.default([])
                            )

  @doc """
  Acquire an OAuth token for the memberships service.

  Accepts a `%LaunchContext{}` or a `%Registration{}`. With a launch context,
  the endpoint is extracted from the launch claims. With a registration,
  pass the endpoint via the `:endpoint` option.

  ## From a launch context

      {:ok, client} = Ltix.MembershipsService.authenticate(launch_context)

  ## From a registration

      {:ok, client} = Ltix.MembershipsService.authenticate(registration,
        endpoint: MembershipsEndpoint.new("https://lms.example.com/memberships")
      )

  ## Options (launch context)

  #{Zoi.describe(@context_auth_schema)}

  ## Options (registration)

  #{Zoi.describe(@registration_auth_schema)}
  """
  @spec authenticate(LaunchContext.t() | Registration.t(), keyword()) ::
          {:ok, Client.t()} | {:error, Exception.t()}
  def authenticate(context_or_registration, opts \\ [])

  def authenticate(%LaunchContext{} = context, opts) do
    opts = Zoi.parse!(@context_auth_schema, opts)

    with {:ok, registration} <- Registerable.to_registration(context.registration) do
      case endpoint_from_claims(context.claims) do
        {:ok, endpoint} ->
          with :ok <- validate_service_version(endpoint) do
            OAuth.authenticate(registration,
              endpoints: %{__MODULE__ => endpoint},
              req_options: Keyword.get(opts, :req_options, [])
            )
          end

        :error ->
          {:error,
           ServiceNotAvailable.exception(
             service: __MODULE__,
             spec_ref: "NRPS §3.6.1.1"
           )}
      end
    end
  end

  def authenticate(%Registration{} = registration, opts) do
    opts = Zoi.parse!(@registration_auth_schema, opts)
    endpoint = Keyword.fetch!(opts, :endpoint)

    OAuth.authenticate(registration,
      endpoints: %{__MODULE__ => endpoint},
      req_options: Keyword.get(opts, :req_options, [])
    )
  end

  @doc """
  Same as `authenticate/2` but raises on error.
  """
  @spec authenticate!(LaunchContext.t() | Registration.t(), keyword()) :: Client.t()
  def authenticate!(context_or_registration, opts \\ []) do
    case authenticate(context_or_registration, opts) do
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

  @get_members_schema Zoi.keyword(
                        @query_fields ++
                          [
                            max_members:
                              Zoi.union(
                                [Zoi.integer() |> Zoi.positive(), Zoi.literal(:infinity)],
                                description:
                                  "Safety limit for eager fetch. Returns a `RosterTooLarge` error " <>
                                    "if exceeded. Set to `:infinity` to disable."
                              )
                              |> Zoi.default(10_000)
                          ]
                      )

  @stream_members_schema Zoi.keyword(@query_fields)

  @doc """
  Fetch all members from the memberships endpoint.

  Follows all `rel="next"` pagination links and returns a complete
  `%MembershipContainer{}`. The container implements `Enumerable`,
  so you can pipe it directly into `Enum` or `Stream` functions.

  ## Options

  #{Zoi.describe(@get_members_schema)}
  """
  # [NRPS §2.4](https://www.imsglobal.org/spec/lti-nrps/v2p0/#membership-container-media-type)
  @spec get_members(Client.t(), keyword()) ::
          {:ok, MembershipContainer.t()} | {:error, Exception.t()}
  def get_members(%Client{} = client, opts \\ []) do
    with {:ok, opts} <- parse_opts(@get_members_schema, opts) do
      max = Keyword.get(opts, :max_members)
      query_opts = Keyword.drop(opts, [:max_members])

      with :ok <- check_expiry(client),
           :ok <- Client.require_scope(client, @nrps_scope),
           {:ok, pages} <- fetch_pages(client, query_opts) do
        collect_roster(pages, max)
      end
    end
  end

  @doc """
  Same as `get_members/2` but raises on error.
  """
  @spec get_members!(Client.t(), keyword()) :: MembershipContainer.t()
  def get_members!(%Client{} = client, opts \\ []) do
    case get_members(client, opts) do
      {:ok, container} -> container
      {:error, error} -> raise error
    end
  end

  @doc """
  Fetch members as a lazy stream.

  Returns `{:ok, stream}` where each element is a `%Member{}`.
  Use this instead of `get_members/2` for large rosters where you
  want to process members incrementally or stop early.

  ## Options

  #{Zoi.describe(@stream_members_schema)}
  """
  # [NRPS §2.4.2](https://www.imsglobal.org/spec/lti-nrps/v2p0/#limit-query-parameter)
  @spec stream_members(Client.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def stream_members(%Client{} = client, opts \\ []) do
    with {:ok, opts} <- parse_opts(@stream_members_schema, opts),
         :ok <- check_expiry(client),
         :ok <- Client.require_scope(client, @nrps_scope),
         {:ok, pages} <- fetch_pages(client, opts) do
      {:ok, Stream.flat_map(pages, &parse_members!/1)}
    end
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

  defp fetch_pages(%Client{} = client, opts) do
    {url, headers, params} = prepare_request(client, opts)
    Pagination.stream(url, headers, params: params, req_options: client.req_options)
  end

  defp prepare_request(%Client{} = client, opts) do
    endpoint = Keyword.get(opts, :endpoint) || get_endpoint(client)
    url = endpoint.context_memberships_url
    params = query_params(opts)
    {url, request_headers(client), params}
  end

  defp request_headers(%Client{access_token: token}) do
    [
      {"accept", @media_type},
      {"authorization", "Bearer #{token}"}
    ]
  end

  defp get_endpoint(%Client{endpoints: endpoints}) do
    Map.fetch!(endpoints, __MODULE__)
  end

  defp parse_opts(schema, opts) do
    case Zoi.parse(schema, opts) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, Zoi.ParseError.exception(errors: errors)}
    end
  end

  defp check_expiry(%Client{} = client) do
    if Client.expired?(client) do
      {:error,
       AccessTokenExpired.exception(
         expires_at: client.expires_at,
         spec_ref: "Sec §7.1"
       )}
    else
      :ok
    end
  end

  defp collect_roster(pages, max) do
    limit = if max == :infinity, do: :infinity, else: max + 1

    pages
    |> Enum.reduce_while({nil, [], 0}, &accumulate_page(&1, &2, limit))
    |> finalize_roster(max)
  end

  defp accumulate_page(body, {first_body, chunks, count}, limit) do
    first_body = first_body || body

    case parse_members(body) do
      members when is_list(members) ->
        count = count + length(members)

        if limit != :infinity and count >= limit do
          {:halt, {first_body, [members | chunks], count}}
        else
          {:cont, {first_body, [members | chunks], count}}
        end

      {:error, _} = error ->
        {:halt, error}
    end
  end

  defp finalize_roster({:error, _} = error, _max), do: error

  defp finalize_roster({_first_body, _chunks, count}, max)
       when max != :infinity and count > max do
    {:error, RosterTooLarge.exception(count: count, max: max, spec_ref: "NRPS §2.4.2")}
  end

  defp finalize_roster({first_body, chunks, _count}, _max) do
    members =
      chunks
      |> Enum.reverse()
      |> List.flatten()

    build_container(members, first_body)
  end

  defp parse_members!(body) do
    case parse_members(body) do
      members when is_list(members) -> members
      {:error, reason} -> raise reason
    end
  end

  defp parse_members(body) when is_map(body) do
    members = body["members"] || []

    result =
      Enum.reduce_while(members, {:ok, []}, fn member_json, {:ok, acc} ->
        case Member.from_json(member_json) do
          {:ok, member} -> {:cont, {:ok, [member | acc]}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case result do
      {:ok, acc} -> Enum.reverse(acc)
      {:error, _} = error -> error
    end
  end

  defp parse_members(_body) do
    {:error,
     MalformedResponse.exception(
       service: __MODULE__,
       reason: "expected JSON object",
       spec_ref: "NRPS §2.4"
     )}
  end

  defp build_container(members, body) do
    context_json = body["context"] || %{}

    case Context.from_json(context_json) do
      {:ok, context} ->
        {:ok,
         %MembershipContainer{
           id: body["id"],
           context: context,
           members: members
         }}

      {:error, _} = error ->
        error
    end
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

  defp resolve_role(atom) when is_atom(atom), do: Role.from_atom(atom).uri

  defp resolve_role(%Role{uri: uri}) when is_binary(uri), do: uri

  defp resolve_role(%Role{} = role) do
    case Role.to_uri(role) do
      {:ok, uri} -> uri
      :error -> raise ArgumentError, "could not resolve role to URI: #{inspect(role)}"
    end
  end

  defp resolve_role(string) when is_binary(string), do: string

  # [NRPS §3.6.1](https://www.imsglobal.org/spec/lti-nrps/v2p0/#lti-1-3-integration)
  defp validate_service_version(%MembershipsEndpoint{service_versions: nil}), do: :ok

  defp validate_service_version(%MembershipsEndpoint{service_versions: versions}) do
    if "2.0" in versions do
      :ok
    else
      {:error,
       ServiceNotAvailable.exception(
         service: __MODULE__,
         spec_ref: "NRPS §3.6.1"
       )}
    end
  end
end
