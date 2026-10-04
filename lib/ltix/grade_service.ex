defmodule Ltix.GradeService do
  @moduledoc """
  Manage line items, post scores, and read results from a platform's
  gradebook using the
  [Assignment and Grade Services (AGS) v2.0](https://www.imsglobal.org/spec/lti-ags/v2p0/).

  AGS has two workflows depending on the launch claim:

  **Coupled** — the platform creates a single line item for the resource
  link. The tool posts scores against that line item directly.

      {:ok, client} = Ltix.GradeService.authenticate(launch_context)
      :ok = Ltix.GradeService.post_score(client, score)

  **Programmatic** — the tool manages its own line items and can create,
  update, or delete them.

      {:ok, client} = Ltix.GradeService.authenticate(launch_context)
      {:ok, items} = Ltix.GradeService.list_line_items(client)
      {:ok, item} = Ltix.GradeService.create_line_item(client,
        label: "Quiz 1", score_maximum: 100
      )
      :ok = Ltix.GradeService.post_score(client, score, line_item: item)
  """

  @behaviour Ltix.AdvantageService

  alias Ltix.GradeService.LineItem
  alias Ltix.GradeService.Result
  alias Ltix.GradeService.Score

  alias Ltix.AppConfig

  alias Ltix.LaunchClaims
  alias Ltix.LaunchClaims.AGSEndpoint
  alias Ltix.LaunchContext

  alias Ltix.OAuth
  alias Ltix.OAuth.Client
  alias Ltix.Options
  alias Ltix.Pagination
  alias Ltix.Registerable

  alias Ltix.Errors.Invalid.CollectionTooLarge
  alias Ltix.Errors.Invalid.CoupledLineItem
  alias Ltix.Errors.Invalid.InvalidEndpoint
  alias Ltix.Errors.Invalid.MalformedResponse
  alias Ltix.Errors.Invalid.MissingLineItemId
  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.Errors.Security.AccessTokenExpired

  @scope_lineitem "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem"
  @scope_lineitem_readonly "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem.readonly"
  @scope_result_readonly "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly"
  @scope_score "https://purl.imsglobal.org/spec/lti-ags/scope/score"

  @lineitem_media_type "application/vnd.ims.lis.v2.lineitem+json"
  @lineitem_container_media_type "application/vnd.ims.lis.v2.lineitemcontainer+json"
  @result_container_media_type "application/vnd.ims.lis.v2.resultcontainer+json"
  @score_media_type "application/vnd.ims.lis.v1.score+json"

  @no_endpoint "The client has no grade service endpoint. Authenticate with one or pass the endpoint option"

  @endpoint_option Zoi.struct(AGSEndpoint,
                     description: "Override the endpoint stored on the client."
                   )

  @max_line_items_option Zoi.union([Zoi.integer() |> Zoi.positive(), Zoi.literal(:infinity)],
                           description:
                             "Safety limit for eager fetch. Returns a `CollectionTooLarge` error if exceeded. " <>
                               "Set to `:infinity` to disable, or use `stream_line_items/2` for large gradebooks."
                         )
                         |> Zoi.default(10_000)

  @max_results_option Zoi.union([Zoi.integer() |> Zoi.positive(), Zoi.literal(:infinity)],
                        description:
                          "Safety limit for eager fetch. Returns a `CollectionTooLarge` error if exceeded. " <>
                            "Set to `:infinity` to disable, or use `stream_results/2` for large courses."
                      )
                      |> Zoi.default(10_000)

  @line_item_option Zoi.union([Zoi.string(), Zoi.struct(LineItem)],
                      description:
                        "Line item URL or struct. Defaults to the endpoint's `line_item`."
                    )

  @impl Ltix.AdvantageService
  # [AGS §3.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#assignment-and-grade-service-claim)
  def endpoint_from_claims(%LaunchClaims{ags_endpoint: %AGSEndpoint{} = ep}), do: {:ok, ep}
  def endpoint_from_claims(_), do: :error

  @impl Ltix.AdvantageService
  def validate_endpoint(%AGSEndpoint{} = endpoint) do
    with {:ok, _endpoint} <- AGSEndpoint.new(Map.from_struct(endpoint)), do: :ok
  end

  def validate_endpoint(_),
    do: {:error, InvalidEndpoint.exception(service: __MODULE__, spec_ref: "AGS §3.1")}

  @impl Ltix.AdvantageService
  # [AGS §3.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#assignment-and-grade-service-claim)
  def scopes(%AGSEndpoint{scopes: scopes}), do: List.wrap(scopes)

  @auth_fields Client.option_fields()

  @context_auth_schema Zoi.keyword(@auth_fields, unrecognized_keys: :error)

  @registration_auth_schema Zoi.keyword(
                              [
                                endpoint:
                                  Zoi.struct(AGSEndpoint, description: "AGS endpoint struct.")
                                  |> Zoi.required()
                              ] ++ @auth_fields,
                              unrecognized_keys: :error
                            )

  @doc """
  Acquire an OAuth token for the grade service.

  Accepts a `%LaunchContext{}` or any struct implementing `Ltix.Registerable`
  (including `Ltix.Registration`). With a launch context, the endpoint and
  scopes are extracted from the AGS claim. With a registration, pass the
  endpoint via the `:endpoint` option, built with
  `Ltix.LaunchClaims.AGSEndpoint.new/1`.

  ## From a launch context

      {:ok, client} = Ltix.GradeService.authenticate(launch_context)

  ## From a registration

      {:ok, client} = Ltix.GradeService.authenticate(registration,
        endpoint:
          AGSEndpoint.new!(
            line_items: "https://lms.example.com/lineitems",
            scopes: ["https://purl.imsglobal.org/spec/lti-ags/scope/lineitem"]
          )
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

    with {:ok, registration} <- Registerable.to_registration(context.registration),
         {:ok, endpoint} <- fetch_claim_endpoint(context.claims) do
      OAuth.authenticate(registration, Keyword.put(opts, :endpoints, %{__MODULE__ => endpoint}))
    end
  end

  def authenticate(registerable, opts) do
    opts = Options.parse!(opts, @registration_auth_schema)
    {endpoint, opts} = Keyword.pop!(opts, :endpoint)
    OAuth.authenticate(registerable, Keyword.put(opts, :endpoints, %{__MODULE__ => endpoint}))
  end

  defp fetch_claim_endpoint(claims) do
    case endpoint_from_claims(claims) do
      {:ok, _endpoint} = ok -> ok
      :error -> not_available("The launch has no grade service endpoint claim")
    end
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

  @line_items_query_fields [
    endpoint: @endpoint_option,
    resource_link_id:
      Zoi.string(description: "Filter to line items bound to this resource link."),
    resource_id: Zoi.string(description: "Filter by the tool's resource identifier."),
    tag: Zoi.string(description: "Filter by tag."),
    per_page: Zoi.integer(description: "Page size hint.") |> Zoi.positive()
  ]

  @list_line_items_schema Zoi.keyword(
                            @line_items_query_fields ++
                              [max_line_items: @max_line_items_option],
                            unrecognized_keys: :error
                          )

  @stream_line_items_schema Zoi.keyword(@line_items_query_fields, unrecognized_keys: :error)

  @doc """
  Fetch all line items from the container endpoint.

  Follows all `rel="next"` pagination links and returns a flat list
  of `%LineItem{}` structs.

  ## Options

  #{Zoi.describe(@list_line_items_schema)}
  """
  # [AGS §3.2.4](https://www.imsglobal.org/spec/lti-ags/v2p0/#container-request-filters)
  @spec list_line_items(Client.t(), keyword()) ::
          {:ok, [LineItem.t()]} | {:error, Exception.t()}
  def list_line_items(%Client{} = client, opts \\ []) do
    opts = Options.parse!(opts, @list_line_items_schema)
    {max, opts} = Keyword.pop(opts, :max_line_items)

    with_line_items(:list_line_items, client, opts, fn items ->
      collect(items, max, :max_line_items, "AGS §3.2.4")
    end)
  end

  @doc """
  Same as `list_line_items/2` but raises on error.
  """
  @spec list_line_items!(Client.t(), keyword()) :: [LineItem.t()]
  def list_line_items!(%Client{} = client, opts \\ []) do
    case list_line_items(client, opts) do
      {:ok, items} -> items
      {:error, error} -> raise error
    end
  end

  @doc """
  Fetch line items as a lazy stream.

  Returns `{:ok, stream}` where each element is a `%LineItem{}`. Use this
  instead of `list_line_items/2` for large gradebooks where you want to
  process line items incrementally or stop early. Later page failures and
  parsing errors raise during enumeration.

  ## Options

  #{Zoi.describe(@stream_line_items_schema)}
  """
  # [AGS §3.2.4](https://www.imsglobal.org/spec/lti-ags/v2p0/#container-request-filters)
  @spec stream_line_items(Client.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def stream_line_items(%Client{} = client, opts \\ []) do
    opts = Options.parse!(opts, @stream_line_items_schema)
    with_line_items(:stream_line_items, client, opts, &{:ok, stream(&1)})
  end

  @doc """
  Same as `stream_line_items/2` but raises on error.
  """
  @spec stream_line_items!(Client.t(), keyword()) :: Enumerable.t()
  def stream_line_items!(%Client{} = client, opts \\ []) do
    case stream_line_items(client, opts) do
      {:ok, stream} -> stream
      {:error, error} -> raise error
    end
  end

  defp with_line_items(operation, client, opts, consume) do
    url = line_items_url(endpoint(client, opts))

    run(operation, client, [@scope_lineitem, @scope_lineitem_readonly], url, fn url ->
      params = list_line_items_params(opts)

      with {:ok, pages} <- fetch_pages(client, url, @lineitem_container_media_type, params) do
        consume.(parse_pages(pages, :line_items))
      end
    end)
  end

  @get_line_item_schema Zoi.keyword(
                          [endpoint: @endpoint_option, line_item: @line_item_option],
                          unrecognized_keys: :error
                        )

  @doc """
  Fetch a single line item.

  ## Options

  #{Zoi.describe(@get_line_item_schema)}
  """
  # [AGS §3.2.3](https://www.imsglobal.org/spec/lti-ags/v2p0/#line-item-id-rest-endpoint)
  @spec get_line_item(Client.t(), keyword()) ::
          {:ok, LineItem.t()} | {:error, Exception.t()}
  def get_line_item(%Client{} = client, opts \\ []) do
    opts = Options.parse!(opts, @get_line_item_schema)
    url = resolve_line_item_url(endpoint(client, opts), opts)

    run(:get_line_item, client, [@scope_lineitem, @scope_lineitem_readonly], url, fn url ->
      with {:ok, body} <- send_request(client, :get, url, accept: @lineitem_media_type) do
        parse_line_item(body)
      end
    end)
  end

  @doc """
  Same as `get_line_item/2` but raises on error.
  """
  @spec get_line_item!(Client.t(), keyword()) :: LineItem.t()
  def get_line_item!(%Client{} = client, opts \\ []) do
    case get_line_item(client, opts) do
      {:ok, item} -> item
      {:error, error} -> raise error
    end
  end

  @create_line_item_schema Zoi.keyword(
                             [
                               endpoint: @endpoint_option,
                               label:
                                 Zoi.string(description: "Human-readable label.")
                                 |> Zoi.required(),
                               score_maximum:
                                 Zoi.number(description: "Maximum score (must be > 0).")
                                 |> Zoi.required(),
                               resource_link_id:
                                 Zoi.string(description: "Bind to a resource link."),
                               resource_id:
                                 Zoi.string(description: "Tool's resource identifier."),
                               tag: Zoi.string(description: "Qualifier tag."),
                               start_date_time:
                                 Zoi.struct(DateTime,
                                   description: "When the line item starts accepting submissions."
                                 ),
                               end_date_time:
                                 Zoi.struct(DateTime,
                                   description: "When the line item stops accepting submissions."
                                 ),
                               grades_released:
                                 Zoi.boolean(description: "Hint about releasing grades."),
                               extensions:
                                 Zoi.map(Zoi.string(), Zoi.any(),
                                   description:
                                     "Extension properties keyed by fully qualified URLs."
                                 )
                                 |> Zoi.default(%{})
                             ],
                             unrecognized_keys: :error
                           )

  @doc """
  Create a new line item.

  ## Options

  #{Zoi.describe(@create_line_item_schema)}
  """
  # [AGS §3.2.5](https://www.imsglobal.org/spec/lti-ags/v2p0/#creating-a-new-line-item)
  @spec create_line_item(Client.t(), keyword()) ::
          {:ok, LineItem.t()} | {:error, Exception.t()}
  def create_line_item(%Client{} = client, opts) do
    opts = Options.parse!(opts, @create_line_item_schema)
    url = line_items_url(endpoint(client, opts))
    item = struct!(LineItem, Keyword.delete(opts, :endpoint))

    run(:create_line_item, client, [@scope_lineitem], url, fn url ->
      with :ok <- LineItem.validate(item),
           {:ok, body} <- send_request(client, :post, url, body: {@lineitem_media_type, item}) do
        parse_line_item(body)
      end
    end)
  end

  @doc """
  Same as `create_line_item/2` but raises on error.
  """
  @spec create_line_item!(Client.t(), keyword()) :: LineItem.t()
  def create_line_item!(%Client{} = client, opts) do
    case create_line_item(client, opts) do
      {:ok, item} -> item
      {:error, error} -> raise error
    end
  end

  @doc """
  Update a line item.

  PUTs the full line item to its `id` URL. Callers should GET first to
  avoid overwriting fields they did not intend to change.
  """
  # [AGS §3.2.6](https://www.imsglobal.org/spec/lti-ags/v2p0/#updating-a-line-item)
  @spec update_line_item(Client.t(), LineItem.t()) ::
          {:ok, LineItem.t()} | {:error, Exception.t()}
  def update_line_item(%Client{} = client, %LineItem{} = item) do
    run(:update_line_item, client, [@scope_lineitem], line_item_url(item, nil), fn url ->
      with :ok <- LineItem.validate(item),
           {:ok, body} <- send_request(client, :put, url, body: {@lineitem_media_type, item}) do
        parse_line_item(body)
      end
    end)
  end

  @doc """
  Same as `update_line_item/2` but raises on error.
  """
  @spec update_line_item!(Client.t(), LineItem.t()) :: LineItem.t()
  def update_line_item!(%Client{} = client, %LineItem{} = item) do
    case update_line_item(client, item) do
      {:ok, item} -> item
      {:error, error} -> raise error
    end
  end

  @delete_line_item_schema Zoi.keyword(
                             [
                               endpoint: @endpoint_option,
                               line_item: @line_item_option,
                               force:
                                 Zoi.boolean(
                                   description:
                                     "Delete even if this is the coupled line item from the launch claim."
                                 )
                                 |> Zoi.default(false)
                             ],
                             unrecognized_keys: :error
                           )

  @doc """
  Delete a line item.

  Returns `:ok` on success.

  By default, refuses to delete the platform-coupled line item
  (the `line_item` URL from the launch claim). Pass `force: true`
  to override.

  ## Options

  #{Zoi.describe(@delete_line_item_schema)}
  """
  # [AGS §3.2.3](https://www.imsglobal.org/spec/lti-ags/v2p0/#line-item-id-rest-endpoint)
  @spec delete_line_item(Client.t(), keyword()) :: :ok | {:error, Exception.t()}
  def delete_line_item(%Client{} = client, opts \\ []) do
    opts = Options.parse!(opts, @delete_line_item_schema)
    endpoint = endpoint(client, opts)
    url = resolve_line_item_url(endpoint, opts)

    run(:delete_line_item, client, [@scope_lineitem], url, fn url ->
      with :ok <- check_coupled_guard(endpoint, url, Keyword.fetch!(opts, :force)),
           {:ok, _body} <- send_request(client, :delete, url) do
        :ok
      end
    end)
  end

  @doc """
  Same as `delete_line_item/2` but raises on error.
  """
  @spec delete_line_item!(Client.t(), keyword()) :: :ok
  def delete_line_item!(%Client{} = client, opts \\ []) do
    case delete_line_item(client, opts) do
      :ok -> :ok
      {:error, error} -> raise error
    end
  end

  @post_score_schema Zoi.keyword(
                       [endpoint: @endpoint_option, line_item: @line_item_option],
                       unrecognized_keys: :error
                     )

  @doc """
  Post a score for a user.

  The score is POSTed to `{line_item}/scores`. When no `:line_item` option
  is given, uses the endpoint's `line_item` URL (coupled flow).

  ## Options

  #{Zoi.describe(@post_score_schema)}
  """
  # [AGS §3.4](https://www.imsglobal.org/spec/lti-ags/v2p0/#score-publish-service)
  @spec post_score(Client.t(), Score.t(), keyword()) ::
          :ok | {:error, Exception.t()}
  def post_score(%Client{} = client, %Score{} = score, opts \\ []) do
    opts = Options.parse!(opts, @post_score_schema)
    url = derive_url(resolve_line_item_url(endpoint(client, opts), opts), "scores")

    run(:post_score, client, [@scope_score], url, fn url ->
      with {:ok, _body} <- send_request(client, :post, url, body: {@score_media_type, score}) do
        :ok
      end
    end)
  end

  @doc """
  Same as `post_score/3` but raises on error.
  """
  @spec post_score!(Client.t(), Score.t(), keyword()) :: :ok
  def post_score!(%Client{} = client, %Score{} = score, opts \\ []) do
    case post_score(client, score, opts) do
      :ok -> :ok
      {:error, error} -> raise error
    end
  end

  @results_query_fields [
    endpoint: @endpoint_option,
    line_item: @line_item_option,
    user_id: Zoi.string(description: "Filter results to a single user."),
    per_page: Zoi.integer(description: "Page size hint.") |> Zoi.positive()
  ]

  @list_results_schema Zoi.keyword(
                         @results_query_fields ++ [max_results: @max_results_option],
                         unrecognized_keys: :error
                       )

  @stream_results_schema Zoi.keyword(@results_query_fields, unrecognized_keys: :error)

  @doc """
  Fetch results for a line item.

  GETs `{line_item}/results`. Follows all `rel="next"` pagination links
  and returns a list of `%Result{}` structs.

  ## Options

  #{Zoi.describe(@list_results_schema)}
  """
  # [AGS §3.3](https://www.imsglobal.org/spec/lti-ags/v2p0/#result-service)
  @spec list_results(Client.t(), keyword()) ::
          {:ok, [Result.t()]} | {:error, Exception.t()}
  def list_results(%Client{} = client, opts \\ []) do
    opts = Options.parse!(opts, @list_results_schema)
    {max, opts} = Keyword.pop(opts, :max_results)

    with_results(:list_results, client, opts, fn results ->
      collect(results, max, :max_results, "AGS §3.3.6")
    end)
  end

  @doc """
  Same as `list_results/2` but raises on error.
  """
  @spec list_results!(Client.t(), keyword()) :: [Result.t()]
  def list_results!(%Client{} = client, opts \\ []) do
    case list_results(client, opts) do
      {:ok, results} -> results
      {:error, error} -> raise error
    end
  end

  @doc """
  Fetch results for a line item as a lazy stream.

  Returns `{:ok, stream}` where each element is a `%Result{}`. Use this
  instead of `list_results/2` for large courses where you want to process
  results incrementally or stop early. Later page failures and parsing
  errors raise during enumeration.

  ## Options

  #{Zoi.describe(@stream_results_schema)}
  """
  # [AGS §3.3](https://www.imsglobal.org/spec/lti-ags/v2p0/#result-service)
  @spec stream_results(Client.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def stream_results(%Client{} = client, opts \\ []) do
    opts = Options.parse!(opts, @stream_results_schema)
    with_results(:stream_results, client, opts, &{:ok, stream(&1)})
  end

  @doc """
  Same as `stream_results/2` but raises on error.
  """
  @spec stream_results!(Client.t(), keyword()) :: Enumerable.t()
  def stream_results!(%Client{} = client, opts \\ []) do
    case stream_results(client, opts) do
      {:ok, stream} -> stream
      {:error, error} -> raise error
    end
  end

  defp with_results(operation, client, opts, consume) do
    url = derive_url(resolve_line_item_url(endpoint(client, opts), opts), "results")

    run(operation, client, [@scope_result_readonly], url, fn url ->
      params = list_results_params(opts)

      with {:ok, pages} <- fetch_pages(client, url, @result_container_media_type, params) do
        consume.(parse_pages(pages, :results))
      end
    end)
  end

  # Telemetry metadata names the URL the operation requests, or `nil` when it
  # cannot be resolved.
  defp run(operation, %Client{} = client, scopes, url, request) do
    metadata = %{endpoint: requested_url(url)}

    :telemetry.span([:ltix, :grade_service, operation], metadata, fn ->
      result =
        with :ok <- check_expiry(client),
             :ok <- Client.require_any_scope(client, scopes),
             {:ok, url} <- url do
          request.(url)
        end

      {result, metadata}
    end)
  end

  defp requested_url({:ok, url}), do: url
  defp requested_url({:error, _error}), do: nil

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

  defp endpoint(%Client{endpoints: endpoints}, opts) do
    Keyword.get_lazy(opts, :endpoint, fn -> Map.get(endpoints, __MODULE__) end)
  end

  # [AGS §3.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#assignment-and-grade-service-claim)
  defp line_items_url(%AGSEndpoint{line_items: url}) when is_binary(url), do: {:ok, url}

  defp line_items_url(%AGSEndpoint{}), do: not_available("The endpoint has no line items URL")
  defp line_items_url(nil), do: not_available(@no_endpoint)

  defp resolve_line_item_url(endpoint, opts) do
    line_item_url(Keyword.get(opts, :line_item), endpoint)
  end

  # [AGS §3.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#assignment-and-grade-service-claim)
  defp line_item_url(nil, %AGSEndpoint{line_item: url}) when is_binary(url), do: {:ok, url}

  defp line_item_url(nil, %AGSEndpoint{}) do
    not_available("The endpoint has no coupled line item URL. Pass the line_item option")
  end

  defp line_item_url(nil, nil), do: not_available(@no_endpoint)

  # [AGS §3.2.3](https://www.imsglobal.org/spec/lti-ags/v2p0/#line-item-id-rest-endpoint)
  defp line_item_url(%LineItem{id: nil} = item, _endpoint) do
    {:error, MissingLineItemId.exception(line_item: item, spec_ref: "AGS §3.2.3")}
  end

  defp line_item_url(%LineItem{id: id}, _endpoint), do: {:ok, id}
  defp line_item_url(url, _endpoint) when is_binary(url), do: {:ok, url}

  defp not_available(reason) do
    {:error,
     ServiceNotAvailable.exception(service: __MODULE__, reason: reason, spec_ref: "AGS §3.1")}
  end

  # [AGS §3.3.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#result-service-endpoint)
  # [AGS §3.4.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#service-endpoint)
  defp derive_url({:ok, url}, suffix) do
    with {:ok, uri} <- Ltix.HTTP.validate_url(url) do
      path = String.trim_trailing(uri.path || "", "/") <> "/" <> suffix
      {:ok, URI.to_string(%{uri | path: path})}
    end
  end

  defp derive_url({:error, _error} = error, _suffix), do: error

  # [AGS §3.2](https://www.imsglobal.org/spec/lti-ags/v2p0/#line-item-service-scope-and-allowed-http-methods)
  defp check_coupled_guard(%AGSEndpoint{line_item: url}, url, false) do
    {:error, CoupledLineItem.exception(line_item_url: url, spec_ref: "AGS §3.2")}
  end

  defp check_coupled_guard(_endpoint, _url, _force), do: :ok

  defp auth_headers(%Client{access_token: token}, nil) do
    [{"authorization", "Bearer #{token}"}]
  end

  defp auth_headers(%Client{access_token: token}, accept) do
    [
      {"accept", accept},
      {"authorization", "Bearer #{token}"}
    ]
  end

  defp req_options(%Client{} = client) do
    Ltix.HTTP.req_options(client.req_options, __MODULE__)
  end

  defp fetch_pages(%Client{} = client, url, accept, params) do
    Pagination.stream_results(url, auth_headers(client, accept),
      params: params,
      req_options: req_options(client)
    )
  end

  defp send_request(%Client{} = client, method, url, opts \\ []) do
    headers = auth_headers(client, Keyword.get(opts, :accept))

    {headers, body_options} =
      case Keyword.get(opts, :body) do
        nil ->
          {headers, []}

        {content_type, body} ->
          {[{"content-type", content_type} | headers],
           [body: AppConfig.json_library!().encode!(body)]}
      end

    request_options =
      Keyword.merge(
        req_options(client),
        [method: method, url: url, headers: headers] ++ body_options
      )

    case Ltix.HTTP.request(request_options) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{} = response} ->
        {:error, Ltix.HTTP.status_error(response, url)}

      {:error, _exception} = error ->
        error
    end
  end

  defp list_line_items_params(opts) do
    params = %{}

    params
    |> maybe_put_param("resource_link_id", Keyword.get(opts, :resource_link_id))
    |> maybe_put_param("resource_id", Keyword.get(opts, :resource_id))
    |> maybe_put_param("tag", Keyword.get(opts, :tag))
    |> maybe_put_limit(Keyword.get(opts, :per_page))
  end

  defp list_results_params(opts) do
    params = %{}

    params
    |> maybe_put_param("user_id", Keyword.get(opts, :user_id))
    |> maybe_put_limit(Keyword.get(opts, :per_page))
  end

  defp maybe_put_limit(params, nil), do: params

  defp maybe_put_limit(params, per_page),
    do: Map.put(params, "limit", Integer.to_string(per_page))

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, key, value), do: Map.put(params, key, value)

  # [line-item-service-media-types-and-schemas]:
  # https://www.imsglobal.org/spec/lti-ags/v2p0/#line-item-service-media-types-and-schemas
  #
  # [AGS §3.2.1][line-item-service-media-types-and-schemas]
  defp parse_pages(pages, :line_items),
    do: parse_pages(pages, &LineItem.from_json/1, "AGS §3.2.1")

  # [AGS §3.3.4](https://www.imsglobal.org/spec/lti-ags/v2p0/#media-type-and-schema)
  defp parse_pages(pages, :results), do: parse_pages(pages, &Result.from_json/1, "AGS §3.3.4")

  # Emits `{:ok, item}` or `{:error, error}` for each entry, so consumers stop
  # at the first failure without fetching later pages.
  defp parse_pages(pages, parser, spec_ref) do
    Stream.flat_map(pages, fn
      {:ok, body} when is_list(body) ->
        Stream.map(body, &parse_collection_item(&1, parser, spec_ref))

      {:ok, _body} ->
        [{:error, malformed_response("expected JSON array", spec_ref)}]

      {:error, _error} = error ->
        [error]
    end)
  end

  # [AGS §3.2.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#line-item-service-media-types-and-schemas)
  defp parse_line_item(body) when is_map(body), do: LineItem.from_json(body)

  defp parse_line_item(_body) do
    {:error, malformed_response("expected JSON object", "AGS §3.2.1")}
  end

  defp parse_collection_item(json, parser, _spec_ref) when is_map(json), do: parser.(json)

  defp parse_collection_item(_json, _parser, spec_ref) do
    {:error, malformed_response("expected JSON object in collection", spec_ref)}
  end

  defp malformed_response(reason, spec_ref) do
    MalformedResponse.exception(service: __MODULE__, reason: reason, spec_ref: spec_ref)
  end

  defp collect(items, max, option, spec_ref) do
    collected =
      Enum.reduce_while(items, {:ok, [], 0}, fn
        {:ok, _item}, {:ok, _collected, count} when count == max ->
          error =
            CollectionTooLarge.exception(
              service: __MODULE__,
              option: option,
              count: count + 1,
              max: max,
              spec_ref: spec_ref
            )

          {:halt, {:error, error}}

        {:ok, item}, {:ok, collected, count} ->
          {:cont, {:ok, [item | collected], count + 1}}

        {:error, _error} = error, _accumulator ->
          {:halt, error}
      end)

    case collected do
      {:ok, items, _count} -> {:ok, Enum.reverse(items)}
      {:error, _error} = error -> error
    end
  end

  defp stream(items) do
    Stream.map(items, fn
      {:ok, item} -> item
      {:error, error} -> raise error
    end)
  end

  @doc false
  @spec classify_keys(map(), %{String.t() => atom()}) :: {map(), map()}
  def classify_keys(json, known_keys) do
    Enum.reduce(json, {%{}, %{}}, fn {key, value}, {fields, extensions} ->
      case Map.fetch(known_keys, key) do
        {:ok, field} -> {Map.put(fields, field, value), extensions}
        :error -> {fields, Map.put(extensions, key, value)}
      end
    end)
  end
end
