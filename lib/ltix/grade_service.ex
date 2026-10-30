defmodule Ltix.GradeService do
  @moduledoc """
  Manage line items, post scores, and read results from a platform's
  gradebook using the
  [Assignment and Grade Services (AGS) v2.0](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec).

  AGS has two workflows depending on the launch claim.

  **Coupled.** The platform creates a single line item for the resource
  link. The tool posts scores against that line item directly.

  ```elixir
  {:ok, client} = Ltix.GradeService.authenticate(launch)
  :ok = Ltix.GradeService.post_score(client, score)
  ```

  **Programmatic.** The tool manages its own line items and can create,
  update, or delete them.

  ```elixir
  {:ok, client} = Ltix.GradeService.authenticate(launch)
  {:ok, items} = Ltix.GradeService.list_line_items(client)
  {:ok, item} = Ltix.GradeService.create_line_item(client,
    label: "Quiz 1", score_maximum: 100
  )
  :ok = Ltix.GradeService.post_score(client, score, line_item: item)
  ```
  """

  @behaviour Ltix.Plugin

  use Ltix.Provider

  alias Ltix.AppConfig
  alias Ltix.Errors.Invalid.CollectionTooLarge
  alias Ltix.Errors.Invalid.CoupledLineItem
  alias Ltix.Errors.Invalid.MalformedResponse
  alias Ltix.Errors.Invalid.MissingLineItemId
  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.GradeService.AddScopes
  alias Ltix.GradeService.Endpoint
  alias Ltix.GradeService.LineItem
  alias Ltix.GradeService.Result
  alias Ltix.GradeService.Score
  alias Ltix.HTTP
  alias Ltix.Launch
  alias Ltix.OAuth
  alias Ltix.OAuth.Client
  alias Ltix.Options
  alias Ltix.Plugin
  alias Ltix.PluginSet
  alias Ltix.Registerable

  @version Mix.Project.config()[:version]

  @scope_lineitem "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem"
  @scope_lineitem_readonly "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem.readonly"
  @scope_result_readonly "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly"
  @scope_score "https://purl.imsglobal.org/spec/lti-ags/scope/score"

  @line_item_media_type "application/vnd.ims.lis.v2.lineitem+json"
  @line_item_container_media_type "application/vnd.ims.lis.v2.lineitemcontainer+json"
  @result_container_media_type "application/vnd.ims.lis.v2.resultcontainer+json"
  @score_media_type "application/vnd.ims.lis.v1.score+json"

  @no_endpoint "The client has no grade service endpoint. Authenticate with one or pass the endpoint option"

  @endpoint_option Zoi.struct(Endpoint,
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

  @plugins_option Zoi.list(Zoi.any(),
                    description:
                      "Plugins for this call, each as `MyPlugin` or `{MyPlugin, opts}`. " <>
                        "Defaults to the client's plugins."
                  )

  @impl Ltix.Plugin
  def plugin(_opts) do
    Plugin.new(name: "LTI Assignment and Grade Services 2.0", version: @version)
    |> Plugin.add(__MODULE__)
    |> Plugin.add(LineItem)
    |> Plugin.add(Score)
    |> Plugin.add(Result)
    |> Plugin.add(Endpoint)
    |> Plugin.add(AddScopes)
  end

  @auth_fields Client.option_fields()

  @launch_auth_schema Zoi.keyword(@auth_fields, unrecognized_keys: :error)

  @registration_auth_schema Zoi.keyword(
                              [
                                endpoint:
                                  Zoi.struct(Endpoint, description: "AGS endpoint struct.")
                                  |> Zoi.required()
                              ] ++ Client.registration_option_fields(),
                              unrecognized_keys: :error
                            )

  @doc """
  Acquire an OAuth token for the grade service.

  Accepts a `%Ltix.Launch{}` or any struct implementing `Ltix.Registerable`
  (including `Ltix.Registration`). With a launch, the endpoint and
  scopes are extracted from the AGS claim. With a registration, pass the
  endpoint via the `:endpoint` option, built with
  `Ltix.GradeService.Endpoint.new/1`.

  ## From a launch

  ```elixir
  {:ok, client} = Ltix.GradeService.authenticate(launch)
  ```

  ## From a registration

  ```elixir
  {:ok, client} = Ltix.GradeService.authenticate(registration,
    endpoint:
      Ltix.GradeService.Endpoint.new!(
        line_items: "https://lms.example.com/lineitems",
        scopes: ["https://purl.imsglobal.org/spec/lti-ags/scope/lineitem"]
      )
  )
  ```

  ## Options

  When you [configure](`m:Ltix#module-configuration`) an option, the configured
  value is its default.

  ### From a launch

  #{Zoi.describe(@launch_auth_schema)}

  ### From a registration

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

  @line_items_query_fields [
    endpoint: @endpoint_option,
    plugins: @plugins_option,
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
  # [AGS, Container Request Filters](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#container-request-filters)
  @spec list_line_items(Client.t(), keyword()) ::
          {:ok, [LineItem.t()]} | {:error, Exception.t()}
  def list_line_items(%Client{} = client, opts \\ []) do
    opts = Options.parse!(opts, @list_line_items_schema)
    {max, opts} = Keyword.pop(opts, :max_line_items)

    with_line_items(:list_line_items, client, opts, fn items ->
      collect(items, max,
        service: __MODULE__,
        option: :max_line_items
      )
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
  for large gradebooks where you want to process line items incrementally
  or stop early. `list_line_items/2` returns the whole list. Later page
  failures and parsing errors raise during enumeration.

  ## Options

  #{Zoi.describe(@stream_line_items_schema)}
  """
  # [AGS, Container Request Filters](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#container-request-filters)
  @spec stream_line_items(Client.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def stream_line_items(%Client{} = client, opts \\ []) do
    opts = Options.parse!(opts, @stream_line_items_schema)
    with_line_items(:stream_line_items, client, opts, &{:ok, raise_errors(&1)})
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

    run_with_plugins(
      operation,
      client,
      opts,
      [@scope_lineitem, @scope_lineitem_readonly],
      url,
      fn url, plugins ->
        params = list_line_items_params(opts)

        with {:ok, pages} <- fetch_pages(client, url, @line_item_container_media_type, params) do
          consume.(parse_pages(pages, LineItem, plugins))
        end
      end
    )
  end

  @get_line_item_schema Zoi.keyword(
                          [
                            endpoint: @endpoint_option,
                            line_item: @line_item_option,
                            plugins: @plugins_option
                          ],
                          unrecognized_keys: :error
                        )

  @doc """
  Fetch a single line item.

  ## Options

  #{Zoi.describe(@get_line_item_schema)}
  """
  # [AGS, Line Item id REST Endpoint](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#line-item-id-rest-endpoint)
  @spec get_line_item(Client.t(), keyword()) ::
          {:ok, LineItem.t()} | {:error, Exception.t()}
  def get_line_item(%Client{} = client, opts \\ []) do
    opts = Options.parse!(opts, @get_line_item_schema)
    url = resolve_line_item_url(endpoint(client, opts), opts)

    run_with_plugins(
      :get_line_item,
      client,
      opts,
      [@scope_lineitem, @scope_lineitem_readonly],
      url,
      fn url, plugins ->
        with {:ok, body} <-
               send_request(client, :get, url, headers: [{"accept", @line_item_media_type}]) do
          parse_line_item(body, plugins)
        end
      end
    )
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
                             [endpoint: @endpoint_option, plugins: @plugins_option],
                             unrecognized_keys: :error
                           )

  @line_item_fields_schema Zoi.keyword(
                             [
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
                                 Zoi.boolean(description: "Hint about releasing grades.")
                             ],
                             unrecognized_keys: :error
                           )

  @doc """
  Creates a line item and returns it with the `id` the platform assigned.

  Takes an `Ltix.GradeService.LineItem`, or its fields and property names as a
  keyword list with `:label` and `:score_maximum` required. Pass options in the
  same keyword list. Pass a plugin's property by its name.
  `Ltix.GradeService.LineItem` has an example.

  Each call creates a new line item. To reuse one, find it first with
  `list_line_items/2` and its `:resource_id` or `:tag` filter.

  Returns the error of `Ltix.GradeService.LineItem.validate/1` without
  sending anything. A keyword list with a missing, unknown, or mistyped
  field raises `ArgumentError`.

  ## Examples

  ```elixir
  {:ok, item} = Ltix.GradeService.create_line_item(client, label: "Quiz 1", score_maximum: 100)
  ```

  ## Options

  #{Zoi.describe(@create_line_item_schema)}
  """
  # [AGS, Creating a new line item](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#creating-a-new-line-item)
  @spec create_line_item(Client.t(), LineItem.t() | keyword(), keyword()) ::
          {:ok, LineItem.t()} | {:error, Exception.t()}
  def create_line_item(client, line_item_or_fields, opts \\ [])

  def create_line_item(%Client{} = client, %LineItem{} = item, opts) do
    opts = Options.parse!(opts, @create_line_item_schema)
    url = line_items_url(endpoint(client, opts))

    run_with_plugins(:create_line_item, client, opts, [@scope_lineitem], url, fn url, plugins ->
      with :ok <- LineItem.validate(item),
           {:ok, body} <-
             send_request(
               client,
               :post,
               url,
               json_body(@line_item_media_type, item, plugins, :create)
             ) do
        parse_line_item(body, plugins)
      end
    end)
  end

  def create_line_item(%Client{} = client, fields, opts) when is_list(fields) do
    {opts, fields} = Keyword.split(fields ++ opts, [:endpoint, :plugins])

    with {:ok, plugins} <- PluginSet.resolve(opts[:plugins] || client.plugins) do
      {extensions, fields} = Ltix.Type.split_properties(LineItem, Map.new(fields), plugins)
      fields = Options.parse!(Map.to_list(fields), @line_item_fields_schema)
      create_line_item(client, struct!(LineItem, [extensions: extensions] ++ fields), opts)
    end
  end

  @doc """
  Same as `create_line_item/3` but raises on error.
  """
  @spec create_line_item!(Client.t(), LineItem.t() | keyword(), keyword()) :: LineItem.t()
  def create_line_item!(%Client{} = client, line_item_or_fields, opts \\ []) do
    case create_line_item(client, line_item_or_fields, opts) do
      {:ok, item} -> item
      {:error, error} -> raise error
    end
  end

  @update_line_item_schema Zoi.keyword([plugins: @plugins_option], unrecognized_keys: :error)

  @doc """
  Update a line item.

  PUTs the full line item to its `id` URL. Callers should GET first to
  avoid overwriting fields they did not intend to change.

  ## Options

  #{Zoi.describe(@update_line_item_schema)}
  """
  # [AGS, Updating a line item](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#updating-a-line-item)
  @spec update_line_item(Client.t(), LineItem.t(), keyword()) ::
          {:ok, LineItem.t()} | {:error, Exception.t()}
  def update_line_item(%Client{} = client, %LineItem{} = item, opts \\ []) do
    opts = Options.parse!(opts, @update_line_item_schema)

    run_with_plugins(
      :update_line_item,
      client,
      opts,
      [@scope_lineitem],
      line_item_url(item, nil),
      fn url, plugins ->
        with :ok <- LineItem.validate(item),
             {:ok, body} <-
               send_request(
                 client,
                 :put,
                 url,
                 json_body(@line_item_media_type, item, plugins, :update)
               ) do
          parse_line_item(body, plugins)
        end
      end
    )
  end

  @doc """
  Same as `update_line_item/3` but raises on error.
  """
  @spec update_line_item!(Client.t(), LineItem.t(), keyword()) :: LineItem.t()
  def update_line_item!(%Client{} = client, %LineItem{} = item, opts \\ []) do
    case update_line_item(client, item, opts) do
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

  By default, returns an error for the platform-coupled line item
  (the `line_item` URL from the launch claim). Pass `force: true`
  to override.

  ## Options

  #{Zoi.describe(@delete_line_item_schema)}
  """
  # [AGS, Line Item id REST Endpoint](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#line-item-id-rest-endpoint)
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
                       [
                         endpoint: @endpoint_option,
                         line_item: @line_item_option,
                         plugins: @plugins_option
                       ],
                       unrecognized_keys: :error
                     )

  @doc """
  Post a score for a user.

  The score is POSTed to `{line_item}/scores`. When no `:line_item` option
  is given, uses the endpoint's `line_item` URL (coupled flow).

  ## Options

  #{Zoi.describe(@post_score_schema)}
  """
  # [AGS, Score publish service](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#score-publish-service)
  @spec post_score(Client.t(), Score.t(), keyword()) ::
          :ok | {:error, Exception.t()}
  def post_score(%Client{} = client, %Score{} = score, opts \\ []) do
    opts = Options.parse!(opts, @post_score_schema)
    url = derive_url(resolve_line_item_url(endpoint(client, opts), opts), "scores")

    run_with_plugins(:post_score, client, opts, [@scope_score], url, fn url, plugins ->
      with :ok <- Score.validate(score),
           {:ok, _body} <-
             send_request(
               client,
               :post,
               url,
               json_body(@score_media_type, score, plugins, :create)
             ) do
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
    plugins: @plugins_option,
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
  # [AGS, Result Service](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#result-service)
  @spec list_results(Client.t(), keyword()) ::
          {:ok, [Result.t()]} | {:error, Exception.t()}
  def list_results(%Client{} = client, opts \\ []) do
    opts = Options.parse!(opts, @list_results_schema)
    {max, opts} = Keyword.pop(opts, :max_results)

    with_results(:list_results, client, opts, fn results ->
      collect(results, max,
        service: __MODULE__,
        option: :max_results
      )
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
  for large courses where you want to process results incrementally or
  stop early. `list_results/2` returns the whole list. Later page failures
  and parsing errors raise during enumeration.

  ## Options

  #{Zoi.describe(@stream_results_schema)}
  """
  # [AGS, Result Service](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#result-service)
  @spec stream_results(Client.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def stream_results(%Client{} = client, opts \\ []) do
    opts = Options.parse!(opts, @stream_results_schema)
    with_results(:stream_results, client, opts, &{:ok, raise_errors(&1)})
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

    run_with_plugins(operation, client, opts, [@scope_result_readonly], url, fn url, plugins ->
      params = list_results_params(opts)

      with {:ok, pages} <- fetch_pages(client, url, @result_container_media_type, params) do
        consume.(parse_pages(pages, Result, plugins))
      end
    end)
  end

  # Runs `request` with the URL and the plugin set. The plugin set is the
  # `:plugins` option's, or the client's.
  defp run_with_plugins(operation, client, opts, scopes, url, request) do
    run(operation, client, scopes, url, fn url ->
      with {:ok, plugins} <- PluginSet.resolve(opts[:plugins] || client.plugins),
           do: request.(url, plugins)
    end)
  end

  # Runs `request` with the URL inside a `[:ltix, :grade_service, operation]`
  # telemetry span, whose `endpoint` metadata is the URL, or `nil` when `url`
  # is an error. Returns `AccessTokenExpired` when the client's token has
  # expired, and `ScopeMismatch` when it was granted none of `scopes`.
  defp run(operation, client, scopes, url, request) do
    metadata = %{endpoint: requested_url(url)}

    :telemetry.span([:ltix, :grade_service, operation], metadata, fn ->
      result =
        with :ok <- Client.require_unexpired(client),
             :ok <- Client.require_any_scope(client, scopes),
             {:ok, url} <- url do
          request.(url)
        end

      {result, metadata}
    end)
  end

  defp requested_url({:ok, url}), do: url
  defp requested_url({:error, _error}), do: nil

  # Collects the items of `{:ok, item}` and `{:error, error}` results. Returns
  # the first error, or `CollectionTooLarge` when there are more than `max`.
  defp collect(results, max, limit_error) do
    collected =
      Enum.reduce_while(results, {:ok, [], 0}, fn
        {:ok, item}, {:ok, items, total} ->
          total = total + 1

          if max != :infinity && total > max do
            {:halt,
             {:error, CollectionTooLarge.exception([count: total, max: max] ++ limit_error)}}
          else
            {:cont, {:ok, [item | items], total}}
          end

        {:error, _error} = error, _collected ->
          {:halt, error}
      end)

    with {:ok, items, _total} <- collected, do: {:ok, Enum.reverse(items)}
  end

  defp raise_errors(results) do
    Stream.map(results, fn
      {:ok, item} -> item
      {:error, error} -> raise error
    end)
  end

  defp endpoint(%Client{} = client, opts) do
    Keyword.get_lazy(opts, :endpoint, fn -> Client.get_endpoint(client, __MODULE__) end)
  end

  # [AGS, Assignment and Grade Service claim](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#assignment-and-grade-service-claim)
  defp line_items_url(%Endpoint{line_items: url}) when is_binary(url), do: {:ok, url}

  defp line_items_url(%Endpoint{}), do: not_available("The endpoint has no line items URL")
  defp line_items_url(nil), do: not_available(@no_endpoint)

  defp resolve_line_item_url(endpoint, opts) do
    line_item_url(Keyword.get(opts, :line_item), endpoint)
  end

  # [AGS, Assignment and Grade Service claim](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#assignment-and-grade-service-claim)
  defp line_item_url(nil, %Endpoint{line_item: url}) when is_binary(url), do: {:ok, url}

  defp line_item_url(nil, %Endpoint{}) do
    not_available("The endpoint has no coupled line item URL. Pass the line_item option")
  end

  defp line_item_url(nil, nil), do: not_available(@no_endpoint)

  # [AGS, Line Item id REST Endpoint](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#line-item-id-rest-endpoint)
  defp line_item_url(%LineItem{id: nil} = item, _endpoint) do
    {:error, MissingLineItemId.exception(line_item: item)}
  end

  defp line_item_url(%LineItem{id: id}, _endpoint), do: {:ok, id}
  defp line_item_url(url, _endpoint) when is_binary(url), do: {:ok, url}

  defp not_available(reason) do
    {:error, ServiceNotAvailable.exception(service: __MODULE__, reason: reason)}
  end

  # [AGS, Result service endpoint](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#result-service-endpoint)
  # [AGS, Service endpoint](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#service-endpoint)
  defp derive_url({:ok, url}, suffix) do
    with {:ok, uri} <- HTTP.validate_url(url) do
      path = String.trim_trailing(uri.path || "", "/") <> "/" <> suffix
      {:ok, URI.to_string(%{uri | path: path})}
    end
  end

  defp derive_url({:error, _error} = error, _suffix), do: error

  # [AGS, Coupled vs decoupled line items](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#coupled-vs-decoupled-line-items)
  defp check_coupled_guard(%Endpoint{line_item: url}, url, false) do
    {:error, CoupledLineItem.exception(line_item_url: url)}
  end

  defp check_coupled_guard(_endpoint, _url, _force), do: :ok

  defp fetch_pages(%Client{} = client, url, accept, params) do
    Client.request_pages(client, __MODULE__,
      url: url,
      headers: [{"accept", accept}],
      params: params
    )
  end

  defp send_request(%Client{} = client, method, url, opts \\ []) do
    with {:ok, %Req.Response{body: body}} <-
           Client.request(client, __MODULE__, [method: method, url: url] ++ opts) do
      {:ok, body}
    end
  end

  defp json_body(media_type, value, plugins, operation) do
    json = Ltix.Type.to_json(value, plugins, operation)
    [headers: [{"content-type", media_type}], body: AppConfig.json_library!().encode!(json)]
  end

  defp list_line_items_params(opts) do
    %{}
    |> maybe_put_param("resource_link_id", Keyword.get(opts, :resource_link_id))
    |> maybe_put_param("resource_id", Keyword.get(opts, :resource_id))
    |> maybe_put_param("tag", Keyword.get(opts, :tag))
    |> maybe_put_limit(Keyword.get(opts, :per_page))
  end

  defp list_results_params(opts) do
    %{}
    |> maybe_put_param("user_id", Keyword.get(opts, :user_id))
    |> maybe_put_limit(Keyword.get(opts, :per_page))
  end

  defp maybe_put_limit(params, nil), do: params

  defp maybe_put_limit(params, per_page),
    do: Map.put(params, "limit", Integer.to_string(per_page))

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, key, value), do: Map.put(params, key, value)

  # Emits `{:ok, item}` or `{:error, error}` for each entry, so consumers stop
  # at the first failure without fetching later pages.
  defp parse_pages(pages, type, plugins) do
    Stream.flat_map(pages, fn
      {:ok, body} when is_list(body) ->
        Stream.map(body, &parse_collection_item(&1, type, plugins))

      {:ok, _body} ->
        [{:error, malformed_response("expected JSON array")}]

      {:error, _error} = error ->
        [error]
    end)
  end

  defp parse_line_item(body, plugins) when is_map(body), do: parse(LineItem, body, plugins)

  defp parse_line_item(_body, _plugins) do
    {:error, malformed_response("expected JSON object")}
  end

  defp parse_collection_item(json, type, plugins) when is_map(json),
    do: parse(type, json, plugins)

  defp parse_collection_item(_json, _type, _plugins) do
    {:error, malformed_response("expected JSON object in collection")}
  end

  # [AGS, Line item service Media types and schemas](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#line-item-service-media-types-and-schemas)
  # [AGS, Media type and schema](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#media-type-and-schema)
  defp parse(type, json, plugins) do
    Ltix.Type.from_json(type, json, plugins: plugins, name: name(type))
  end

  defp name(LineItem), do: "line_item"
  defp name(Result), do: "result"

  defp malformed_response(reason) do
    MalformedResponse.exception(service: __MODULE__, reason: reason)
  end

  @doc false
  @spec media_type(:line_item | :line_item_container | :result_container | :score) :: String.t()
  def media_type(:line_item), do: @line_item_media_type
  def media_type(:line_item_container), do: @line_item_container_media_type
  def media_type(:result_container), do: @result_container_media_type
  def media_type(:score), do: @score_media_type
end
