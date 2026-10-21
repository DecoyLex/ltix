defmodule Ltix.MembershipsService do
  @moduledoc """
  Query context membership (roster) from a platform using the
  [Names and Roles Provisioning Service (NRPS) v2.0](https://www.imsglobal.org/spec/lti-nrps/v2p0/).

  Given a successful LTI 1.3 launch that includes the memberships endpoint
  claim, retrieve the list of users enrolled in the course or resource link.

  ## From a launch

      {:ok, client} = Ltix.MembershipsService.authenticate(launch)
      {:ok, roster} = Ltix.MembershipsService.list_members(client)

      Enum.each(roster, fn member ->
        IO.puts("\#{member.name}: \#{inspect(member.roles)}")
      end)

  ## From a registration

      alias Ltix.MembershipsService.Endpoint

      {:ok, client} = Ltix.MembershipsService.authenticate(registration,
        endpoint: Endpoint.new!("https://lms.example.com/memberships")
      )

      {:ok, roster} = Ltix.MembershipsService.list_members(client, role: Ltix.Role.context_learner())

  ## Streaming large rosters

      {:ok, stream} = Ltix.MembershipsService.stream_members(client)

      stream
      |> Stream.filter(&(&1.status == :active))
      |> Enum.each(&process_member/1)
  """

  @behaviour Ltix.Plugin

  use Ltix.Provider

  alias Ltix.Claims
  alias Ltix.Errors.Invalid.CollectionTooLarge
  alias Ltix.Errors.Invalid.MalformedResponse
  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.Launch
  alias Ltix.MembershipsService.AddScope
  alias Ltix.MembershipsService.Endpoint
  alias Ltix.MembershipsService.Member
  alias Ltix.MembershipsService.MembershipContainer
  alias Ltix.OAuth
  alias Ltix.OAuth.Client
  alias Ltix.Options
  alias Ltix.Plugin
  alias Ltix.PluginSet
  alias Ltix.Registerable

  @version Mix.Project.config()[:version]

  @media_type "application/vnd.ims.lti-nrps.v2.membershipcontainer+json"

  @impl Ltix.Plugin
  def plugin(_opts) do
    Plugin.new(name: "LTI Names and Role Provisioning Services 2.0", version: @version)
    |> Plugin.add(__MODULE__)
    |> Plugin.add(Member)
    |> Plugin.add(MembershipContainer)
    |> Plugin.add(Endpoint)
    |> Plugin.add(AddScope)
  end

  @auth_fields Client.option_fields()

  @launch_auth_schema Zoi.keyword(@auth_fields, unrecognized_keys: :error)

  @registration_auth_schema Zoi.keyword(
                              [
                                endpoint:
                                  Zoi.struct(Endpoint,
                                    description:
                                      "`Ltix.MembershipsService.Endpoint` struct for the service endpoint."
                                  )
                                  |> Zoi.required()
                              ] ++ Client.registration_option_fields(),
                              unrecognized_keys: :error
                            )

  @doc """
  Acquire an OAuth token for the memberships service.

  Accepts a `%Ltix.Launch{}` or any struct implementing `Ltix.Registerable`
  (including `Ltix.Registration`). With a launch, the endpoint is
  extracted from the launch claims. With a registration, pass the endpoint
  via the `:endpoint` option.

  ## From a launch

      {:ok, client} = Ltix.MembershipsService.authenticate(launch)

  ## From a registration

      {:ok, client} = Ltix.MembershipsService.authenticate(registration,
        endpoint: Ltix.MembershipsService.Endpoint.new!("https://lms.example.com/memberships")
      )

  ## Options (launch)

  #{Zoi.describe(@launch_auth_schema)}

  ## Options (registration)

  #{Zoi.describe(@registration_auth_schema)}
  """
  @spec authenticate(Launch.t() | Registerable.t(), keyword()) ::
          {:ok, Client.t()} | {:error, Exception.t()}
  def authenticate(launch_or_registerable, opts \\ [])

  def authenticate(%Launch{} = launch, opts) do
    opts = Options.parse!(opts, @launch_auth_schema)
    OAuth.authenticate(launch, Keyword.put(opts, :services, [__MODULE__]))
  end

  def authenticate(registerable, opts) do
    opts = Options.parse!(opts, @registration_auth_schema)
    {endpoint, opts} = Keyword.pop!(opts, :endpoint)
    OAuth.authenticate(registerable, Keyword.put(opts, :endpoints, %{__MODULE__ => endpoint}))
  end

  @doc """
  Same as `authenticate/2` but raises on error.
  """
  @spec authenticate!(Launch.t() | Registerable.t(), keyword()) :: Client.t()
  def authenticate!(launch_or_registerable, opts \\ []) do
    case authenticate(launch_or_registerable, opts) do
      {:ok, client} -> client
      {:error, error} -> raise error
    end
  end

  @query_fields [
    endpoint:
      Zoi.struct(Endpoint,
        description: "Override the endpoint stored on the client."
      ),
    plugins:
      Zoi.list(Zoi.any(),
        description:
          "Plugins for this call, each as `MyPlugin` or `{MyPlugin, opts}`. " <>
            "Defaults to the client's plugins."
      ),
    role:
      Zoi.string(
        description: "Only members with this role URI, such as `Ltix.Role.context_learner/0`."
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

    with_pages(:list_members, client, opts, fn pages, plugins ->
      limit_error = [service: __MODULE__, option: :max_members]

      with {:ok, [first | _] = containers} <-
             collect(containers(pages, plugins), max, limit_error) do
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
  Use this for large rosters where you want to process members
  incrementally or stop early. `list_members/2` returns the whole roster.
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

    with_pages(:stream_members, client, opts, fn pages, plugins ->
      {:ok, Stream.flat_map(raise_errors(containers(pages, plugins)), & &1.members)}
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

    run(operation, client, url, fn url ->
      with {:ok, plugins} <- PluginSet.resolve(opts[:plugins] || client.plugins),
           {:ok, pages} <-
             Client.request_pages(client, __MODULE__,
               url: url,
               headers: [{"accept", @media_type}],
               params: query_params(opts)
             ) do
        consume.(pages, plugins)
      end
    end)
  end

  # Runs `request` with the URL inside a `[:ltix, :memberships_service,
  # operation]` telemetry span, whose `endpoint` metadata is the URL, or `nil`
  # when `url` is an error. Returns `AccessTokenExpired` when the client's
  # token has expired, and `ScopeMismatch` when it wasn't granted the
  # memberships scope.
  # [NRPS §3.6.1.2](https://www.imsglobal.org/spec/lti-nrps/v2p0/#scope-for-access)
  defp run(operation, client, url, request) do
    metadata = %{endpoint: requested_url(url)}

    :telemetry.span([:ltix, :memberships_service, operation], metadata, fn ->
      result =
        with :ok <- Client.require_unexpired(client),
             :ok <- Client.require_any_scope(client, [AddScope.scope()]),
             {:ok, url} <- url do
          request.(url)
        end

      {result, metadata}
    end)
  end

  defp requested_url({:ok, url}), do: url
  defp requested_url({:error, _error}), do: nil

  # Collects the containers of `{:ok, container}` and `{:error, error}`
  # results. Returns the first error, or `CollectionTooLarge` when the
  # containers have more than `max` members.
  defp collect(containers, max, limit_error) do
    collected =
      Enum.reduce_while(containers, {:ok, [], 0}, fn
        {:ok, container}, {:ok, collected, total} ->
          total = total + length(container.members)

          if max != :infinity && total > max do
            {:halt,
             {:error, CollectionTooLarge.exception([count: total, max: max] ++ limit_error)}}
          else
            {:cont, {:ok, [container | collected], total}}
          end

        {:error, _error} = error, _collected ->
          {:halt, error}
      end)

    with {:ok, collected, _total} <- collected, do: {:ok, Enum.reverse(collected)}
  end

  defp raise_errors(results) do
    Stream.map(results, fn
      {:ok, container} -> container
      {:error, error} -> raise error
    end)
  end

  # Emits `{:ok, container}` or `{:error, error}` for each page, so consumers
  # stop at the first failure without fetching later pages.
  defp containers(pages, plugins) do
    Stream.map(pages, fn
      {:ok, body} -> parse_container(body, plugins)
      {:error, _error} = error -> error
    end)
  end

  # A container without a context is parsed as one with a `null` context.
  # [NRPS §2.1](https://www.imsglobal.org/spec/lti-nrps/v2p0/#membership-container-media-type)
  defp parse_container(%{"members" => members} = body, plugins) when is_list(members) do
    Ltix.Type.from_json(MembershipContainer, Map.put_new(body, "context", nil),
      plugins: plugins,
      name: "membership"
    )
  end

  defp parse_container(body, _plugins) when is_map(body),
    do: malformed("expected members to be a JSON array")

  defp parse_container(_body, _plugins), do: malformed("expected JSON object")

  defp malformed(reason) do
    {:error, MalformedResponse.exception(service: __MODULE__, reason: reason)}
  end

  # The `:endpoint` option overrides the client's endpoint and is validated like it.
  defp resolve_endpoint(%Client{} = client, opts) do
    case Keyword.fetch(opts, :endpoint) do
      {:ok, %Endpoint{} = endpoint} -> validated(endpoint, opts[:plugins] || client.plugins)
      :error -> client_endpoint(client)
    end
  end

  defp validated(endpoint, plugins) do
    with {:ok, plugins} <- PluginSet.resolve(plugins),
         :ok <- Claims.validate_endpoints(%{__MODULE__ => endpoint}, plugins),
         do: {:ok, endpoint}
  end

  defp client_endpoint(%Client{endpoints: %{__MODULE__ => endpoint}}), do: {:ok, endpoint}

  # [NRPS §3.6.1](https://www.imsglobal.org/spec/lti-nrps/v2p0/#lti-1-3-integration)
  defp client_endpoint(_client) do
    {:error,
     ServiceNotAvailable.exception(
       service: __MODULE__,
       reason:
         "The client has no memberships service endpoint. Authenticate with one or pass the endpoint option"
     )}
  end

  # [NRPS §2.4.1](https://www.imsglobal.org/spec/lti-nrps/v2p0/#role-query-parameter)
  # [NRPS §3](https://www.imsglobal.org/spec/lti-nrps/v2p0/#resource-link-level-membership-service)
  defp query_params(opts) do
    for {option, param} <- [role: "role", per_page: "limit", resource_link_id: "rlid"],
        value = Keyword.get(opts, option),
        into: %{},
        do: {param, to_string(value)}
  end

  @doc false
  @spec media_type(:membership_container) :: String.t()
  def media_type(:membership_container), do: @media_type
end
