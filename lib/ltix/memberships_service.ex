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

  alias Ltix.Errors.Invalid.{
    InvalidEndpoint,
    MalformedResponse,
    RosterTooLarge,
    ServiceNotAvailable
  }

  alias Ltix.Errors.Security.AccessTokenExpired
  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.LaunchClaims
  alias Ltix.LaunchClaims.{Context, MembershipsEndpoint, Role}
  alias Ltix.LaunchContext
  alias Ltix.MembershipsService.{Member, MembershipContainer}
  alias Ltix.OAuth
  alias Ltix.OAuth.Client
  alias Ltix.Pagination
  alias Ltix.Registration

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

  @context_auth_schema NimbleOptions.new!(
                         req_options: [
                           type: :keyword_list,
                           default: [],
                           doc: "Options passed through to `Req.request/2`."
                         ]
                       )

  @registration_auth_schema NimbleOptions.new!(
                              endpoint: [
                                type: {:struct, MembershipsEndpoint},
                                required: true,
                                doc: "MembershipsEndpoint struct for the service endpoint."
                              ],
                              req_options: [
                                type: :keyword_list,
                                default: [],
                                doc: "Options passed through to `Req.request/2`."
                              ]
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

  #{NimbleOptions.docs(@context_auth_schema)}

  ## Options (registration)

  #{NimbleOptions.docs(@registration_auth_schema)}
  """
  @spec authenticate(LaunchContext.t() | Registration.t(), keyword()) ::
          {:ok, Client.t()} | {:error, Exception.t()}
  def authenticate(context_or_registration, opts \\ [])

  def authenticate(%LaunchContext{} = context, opts) do
    opts = NimbleOptions.validate!(opts, @context_auth_schema)

    case endpoint_from_claims(context.claims) do
      {:ok, endpoint} ->
        with :ok <- validate_service_version(endpoint) do
          OAuth.authenticate(context.registration,
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

  def authenticate(%Registration{} = registration, opts) do
    opts = NimbleOptions.validate!(opts, @registration_auth_schema)
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

  @query_schema [
    endpoint: [
      type: {:struct, MembershipsEndpoint},
      doc: "Override the endpoint stored on the client."
    ],
    role: [
      type: {:or, [:atom, :string, {:struct, Role}]},
      doc:
        "Filter by role. Accepts a role atom (e.g., `:learner`), URI string, " <>
          "`%Role{}` struct, or short name string (e.g., `\"Learner\"`)."
    ],
    resource_link_id: [
      type: :string,
      doc: "Query resource link membership."
    ],
    per_page: [
      type: :pos_integer,
      doc: "Page size hint. The platform may return more or fewer than requested."
    ]
  ]

  @get_members_schema NimbleOptions.new!(
                        @query_schema ++
                          [
                            max_members: [
                              type: {:or, [:pos_integer, {:in, [:infinity]}]},
                              default: 10_000,
                              doc:
                                "Safety limit for eager fetch. Returns a `RosterTooLarge` error " <>
                                  "if exceeded. Set to `:infinity` to disable."
                            ]
                          ]
                      )

  @stream_members_schema NimbleOptions.new!(@query_schema)

  @doc """
  Fetch all members from the memberships endpoint.

  Follows all `rel="next"` pagination links and returns a complete
  `%MembershipContainer{}`. The container implements `Enumerable`,
  so you can pipe it directly into `Enum` or `Stream` functions.

  ## Options

  #{NimbleOptions.docs(@get_members_schema)}
  """
  # [NRPS §2.4](https://www.imsglobal.org/spec/lti-nrps/v2p0/#membership-container-media-type)
  @spec get_members(Client.t(), keyword()) ::
          {:ok, MembershipContainer.t()} | {:error, Exception.t()}
  def get_members(%Client{} = client, opts \\ []) do
    with {:ok, opts} <- NimbleOptions.validate(opts, @get_members_schema) do
      max = Keyword.get(opts, :max_members)
      query_opts = Keyword.drop(opts, [:max_members])

      with :ok <- check_expiry(client),
           :ok <- Client.require_scope(client, @nrps_scope),
           {:ok, body, next_url} <- fetch_first_page(client, query_opts),
           first_members when is_list(first_members) <- parse_members(body),
           {:ok, rest} <- stream_remaining(next_url, client) do
        all = Stream.concat(first_members, rest)
        enforce_limit(all, body, max)
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

  #{NimbleOptions.docs(@stream_members_schema)}
  """
  # [NRPS §2.4.2](https://www.imsglobal.org/spec/lti-nrps/v2p0/#limit-query-parameter)
  @spec stream_members(Client.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def stream_members(%Client{} = client, opts \\ []) do
    with {:ok, opts} <- NimbleOptions.validate(opts, @stream_members_schema),
         :ok <- check_expiry(client),
         :ok <- Client.require_scope(client, @nrps_scope) do
      {url, headers, params} = prepare_request(client, opts)

      Pagination.stream(url, headers,
        parse: &parse_members/1,
        params: params,
        req_options: client.req_options
      )
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

  # Fetch the first page directly so get_members/2 can extract the
  # container-level context before streaming remaining pages.
  defp fetch_first_page(%Client{} = client, opts) do
    {url, headers, params} = prepare_request(client, opts)
    req_options = merge_req_options(client.req_options)

    req_opts =
      req_options
      |> Keyword.put(:url, url)
      |> Keyword.put(:headers, headers)
      |> then(fn opts ->
        if params == %{}, do: opts, else: Keyword.put(opts, :params, params)
      end)

    case Req.get(req_opts) do
      {:ok, %Req.Response{status: 200, body: body, headers: resp_headers}} when is_map(body) ->
        next_url = Pagination.parse_next_link(resp_headers)
        {:ok, body, next_url}

      {:ok, %Req.Response{status: 200}} ->
        {:error,
         MalformedResponse.exception(
           service: __MODULE__,
           reason: "expected JSON object",
           spec_ref: "NRPS §2.4"
         )}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, TransportError.exception(status: status, body: body, url: url)}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp stream_remaining(nil, _client), do: {:ok, []}

  defp stream_remaining(next_url, %Client{} = client) do
    Pagination.stream(next_url, request_headers(client),
      parse: &parse_members/1,
      req_options: client.req_options
    )
  end

  defp parse_members(body) when is_map(body) do
    members = body["members"] || []

    Enum.reduce_while(members, {:ok, []}, fn member_json, {:ok, acc} ->
      case Member.from_json(member_json) do
        {:ok, member} -> {:cont, {:ok, [member | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
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

  defp enforce_limit(stream, body, max) do
    members =
      if max == :infinity do
        Enum.to_list(stream)
      else
        stream |> Stream.take(max + 1) |> Enum.to_list()
      end

    if max != :infinity and length(members) > max do
      {:error,
       RosterTooLarge.exception(
         count: length(members),
         max: max,
         spec_ref: "NRPS §2.4.2"
       )}
    else
      build_container(members, body)
    end
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

  defp merge_req_options(req_options) do
    default = Application.get_env(:ltix, :req_options, [])
    Keyword.merge(default, req_options)
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

  defp resolve_role(atom) when is_atom(atom) do
    role = %Role{type: :context, name: atom, sub_role: nil}

    case Role.to_uri(role) do
      {:ok, uri} -> uri
      :error -> Atom.to_string(atom)
    end
  end

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
