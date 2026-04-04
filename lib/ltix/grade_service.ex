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
  alias Ltix.LaunchClaims.AgsEndpoint
  alias Ltix.LaunchContext

  alias Ltix.OAuth
  alias Ltix.OAuth.Client
  alias Ltix.Pagination
  alias Ltix.Registerable

  alias Ltix.Errors.Invalid.CoupledLineItem
  alias Ltix.Errors.Invalid.InvalidEndpoint
  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.Errors.Security.AccessTokenExpired
  alias Ltix.Errors.Unknown.TransportError

  @scope_lineitem "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem"
  @scope_lineitem_readonly "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem.readonly"
  @scope_result_readonly "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly"
  @scope_score "https://purl.imsglobal.org/spec/lti-ags/scope/score"

  @lineitem_media_type "application/vnd.ims.lis.v2.lineitem+json"
  @lineitem_container_media_type "application/vnd.ims.lis.v2.lineitemcontainer+json"
  @result_container_media_type "application/vnd.ims.lis.v2.resultcontainer+json"
  @score_media_type "application/vnd.ims.lis.v1.score+json"

  @impl Ltix.AdvantageService
  # [AGS §3.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#assignment-and-grade-service-claim)
  def endpoint_from_claims(%LaunchClaims{ags_endpoint: %AgsEndpoint{} = ep}), do: {:ok, ep}
  def endpoint_from_claims(_), do: :error

  @impl Ltix.AdvantageService
  def validate_endpoint(%AgsEndpoint{}), do: :ok

  def validate_endpoint(_),
    do: {:error, InvalidEndpoint.exception(service: __MODULE__, spec_ref: "AGS §3.1")}

  @impl Ltix.AdvantageService
  # [AGS §3.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#assignment-and-grade-service-claim)
  def scopes(%AgsEndpoint{scope: scopes}) when is_list(scopes), do: scopes
  def scopes(%AgsEndpoint{scope: nil}), do: []

  @context_auth_schema Zoi.keyword(
                         req_options:
                           Zoi.keyword(Zoi.any(),
                             description: "Options passed through to `Req.request/2`."
                           )
                           |> Zoi.default([])
                       )

  @registration_auth_schema Zoi.keyword(
                              endpoint:
                                Zoi.struct(AgsEndpoint, description: "AGS endpoint struct.")
                                |> Zoi.required(),
                              req_options:
                                Zoi.keyword(Zoi.any(),
                                  description: "Options passed through to `Req.request/2`."
                                )
                                |> Zoi.default([])
                            )

  @doc """
  Acquire an OAuth token for the grade service.

  Accepts a `%LaunchContext{}` or any struct implementing `Ltix.Registerable`
  (including `Ltix.Registration`). With a launch context, the endpoint and
  scopes are extracted from the AGS claim. With a registration, pass the
  endpoint via the `:endpoint` option.

  ## From a launch context

      {:ok, client} = Ltix.GradeService.authenticate(launch_context)

  ## From a registration

      {:ok, client} = Ltix.GradeService.authenticate(registration,
        endpoint: %AgsEndpoint{
          lineitems: "https://lms.example.com/lineitems",
          scope: ["https://purl.imsglobal.org/spec/lti-ags/scope/lineitem"]
        }
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
    opts = Zoi.parse!(@context_auth_schema, opts)

    with {:ok, registration} <- Registerable.to_registration(context.registration) do
      case endpoint_from_claims(context.claims) do
        {:ok, endpoint} ->
          OAuth.authenticate(registration,
            endpoints: %{__MODULE__ => endpoint},
            req_options: Keyword.get(opts, :req_options, [])
          )

        :error ->
          {:error,
           ServiceNotAvailable.exception(
             service: __MODULE__,
             spec_ref: "AGS §3.1"
           )}
      end
    end
  end

  def authenticate(registerable, opts) do
    opts = Zoi.parse!(@registration_auth_schema, opts)
    endpoint = Keyword.fetch!(opts, :endpoint)

    OAuth.authenticate(registerable,
      endpoints: %{__MODULE__ => endpoint},
      req_options: Keyword.get(opts, :req_options, [])
    )
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

  @list_line_items_schema Zoi.keyword(
                            resource_link_id:
                              Zoi.string(
                                description: "Filter to line items bound to this resource link."
                              ),
                            resource_id:
                              Zoi.string(description: "Filter by the tool's resource identifier."),
                            tag: Zoi.string(description: "Filter by tag."),
                            per_page:
                              Zoi.integer(description: "Page size hint.") |> Zoi.positive()
                          )

  @doc """
  Fetch all line items from the container endpoint.

  Follows all `rel="next"` pagination links and returns a flat list
  of `%LineItem{}` structs.

  ## Options

  #{Zoi.describe(@list_line_items_schema)}
  """
  # [AGS §3.2.4](https://www.imsglobal.org/spec/lti-ags/v2p0/#getting-all-the-line-items-in-the-container-url)
  @spec list_line_items(Client.t(), keyword()) ::
          {:ok, [LineItem.t()]} | {:error, Exception.t()}
  def list_line_items(%Client{} = client, opts \\ []) do
    metadata = span_metadata(client)

    :telemetry.span([:ltix, :grade_service, :list_line_items], metadata, fn ->
      result =
        with {:ok, opts} <- parse_opts(@list_line_items_schema, opts),
             :ok <- check_expiry(client),
             :ok <-
               Client.require_any_scope(client, [@scope_lineitem, @scope_lineitem_readonly]),
             {:ok, url} <- require_line_items_url(client),
             params = list_line_items_params(opts),
             headers = auth_headers(client, @lineitem_container_media_type),
             {:ok, pages} <-
               Pagination.stream(url, headers,
                 params: params,
                 req_options: merged_req_options(client)
               ) do
          collect_line_items(pages)
        end

      {result, metadata}
    end)
  end

  @get_line_item_schema Zoi.keyword(
                          line_item:
                            Zoi.union([Zoi.string(), Zoi.struct(LineItem)],
                              description:
                                "Line item URL or struct. Defaults to the endpoint's `lineitem`."
                            )
                        )

  @doc """
  Fetch a single line item.

  ## Options

  #{Zoi.describe(@get_line_item_schema)}
  """
  @spec get_line_item(Client.t(), keyword()) ::
          {:ok, LineItem.t()} | {:error, Exception.t()}
  def get_line_item(%Client{} = client, opts \\ []) do
    metadata = span_metadata(client)

    :telemetry.span([:ltix, :grade_service, :get_line_item], metadata, fn ->
      result =
        with {:ok, opts} <- parse_opts(@get_line_item_schema, opts),
             :ok <- check_expiry(client),
             :ok <-
               Client.require_any_scope(client, [@scope_lineitem, @scope_lineitem_readonly]),
             {:ok, url} <- resolve_line_item_url(client, opts),
             headers = auth_headers(client, @lineitem_media_type),
             req_opts =
               build_request(
                 :get,
                 merged_req_options(client),
                 url,
                 headers,
                 @lineitem_media_type,
                 nil
               ),
             {:ok, body} <- request(req_opts) do
          LineItem.from_json(body)
        end

      {result, metadata}
    end)
  end

  @create_line_item_schema Zoi.keyword(
                             label:
                               Zoi.string(description: "Human-readable label.") |> Zoi.required(),
                             score_maximum:
                               Zoi.number(description: "Maximum score (must be > 0).")
                               |> Zoi.positive()
                               |> Zoi.required(),
                             resource_link_id:
                               Zoi.string(description: "Bind to a resource link."),
                             resource_id: Zoi.string(description: "Tool's resource identifier."),
                             tag: Zoi.string(description: "Qualifier tag."),
                             start_date_time: Zoi.string(description: "ISO 8601 with timezone."),
                             end_date_time: Zoi.string(description: "ISO 8601 with timezone."),
                             grades_released:
                               Zoi.boolean(description: "Hint about releasing grades."),
                             extensions:
                               Zoi.map(Zoi.string(), Zoi.any(),
                                 description:
                                   "Extension properties keyed by fully qualified URLs."
                               )
                               |> Zoi.default(%{})
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
    metadata = span_metadata(client)

    :telemetry.span([:ltix, :grade_service, :create_line_item], metadata, fn ->
      result =
        with {:ok, opts} <- parse_opts(@create_line_item_schema, opts),
             :ok <- check_expiry(client),
             :ok <- Client.require_scope(client, @scope_lineitem),
             {:ok, url} <- require_line_items_url(client),
             item = struct!(LineItem, Enum.into(opts, %{})),
             :ok <- LineItem.validate(item),
             headers = auth_headers(client, nil),
             req_opts =
               build_request(
                 :post,
                 merged_req_options(client),
                 url,
                 headers,
                 @lineitem_media_type,
                 item
               ),
             {:ok, body} <- request(req_opts) do
          LineItem.from_json(body)
        end

      {result, metadata}
    end)
  end

  @doc """
  Update a line item.

  PUTs the full line item to its `id` URL. Callers should GET first to
  avoid overwriting fields they did not intend to change.
  """
  # [AGS §3.2.6](https://www.imsglobal.org/spec/lti-ags/v2p0/#updating-a-line-item)
  @spec update_line_item(Client.t(), LineItem.t()) ::
          {:ok, LineItem.t()} | {:error, Exception.t()}
  def update_line_item(%Client{} = _client, %LineItem{id: nil}) do
    {:error,
     ServiceNotAvailable.exception(
       service: __MODULE__,
       spec_ref: "AGS §3.2.6"
     )}
  end

  def update_line_item(%Client{} = client, %LineItem{} = item) do
    metadata = span_metadata(client)

    :telemetry.span([:ltix, :grade_service, :update_line_item], metadata, fn ->
      result =
        with :ok <- check_expiry(client),
             :ok <- Client.require_scope(client, @scope_lineitem),
             :ok <- LineItem.validate(item),
             url = item.id,
             headers = auth_headers(client, nil),
             req_opts =
               build_request(
                 :put,
                 merged_req_options(client),
                 url,
                 headers,
                 @lineitem_media_type,
                 item
               ),
             {:ok, body} <- request(req_opts) do
          LineItem.from_json(body)
        end

      {result, metadata}
    end)
  end

  @delete_line_item_schema Zoi.keyword(
                             force:
                               Zoi.boolean(
                                 description:
                                   "Delete even if this is the coupled line item from the launch claim."
                               )
                               |> Zoi.default(false)
                           )

  @doc """
  Delete a line item.

  Accepts a `%LineItem{}` struct or a URL string. Returns `:ok` on
  success.

  By default, refuses to delete the platform-coupled line item
  (the `lineitem` URL from the launch claim). Pass `force: true`
  to override.

  ## Options

  #{Zoi.describe(@delete_line_item_schema)}
  """
  @spec delete_line_item(Client.t(), LineItem.t() | String.t(), keyword()) ::
          :ok | {:error, Exception.t()}
  def delete_line_item(%Client{} = client, line_item_or_url, opts \\ []) do
    metadata = span_metadata(client)

    :telemetry.span([:ltix, :grade_service, :delete_line_item], metadata, fn ->
      url = extract_line_item_url(line_item_or_url)

      result =
        with {:ok, opts} <- parse_opts(@delete_line_item_schema, opts),
             :ok <- check_expiry(client),
             :ok <- Client.require_scope(client, @scope_lineitem),
             :ok <- check_coupled_guard(client, url, Keyword.get(opts, :force, false)),
             headers = auth_headers(client, nil),
             req_opts = build_request(:delete, merged_req_options(client), url, headers),
             {:ok, _body} <- request(req_opts) do
          :ok
        end

      {result, metadata}
    end)
  end

  @post_score_schema Zoi.keyword(
                       line_item:
                         Zoi.union([Zoi.string(), Zoi.struct(LineItem)],
                           description:
                             "Line item URL or struct. Defaults to the endpoint's `lineitem`."
                         )
                     )

  @doc """
  Post a score for a user.

  The score is POSTed to `{lineitem}/scores`. When no `:line_item` option
  is given, uses the endpoint's `lineitem` URL (coupled flow).

  ## Options

  #{Zoi.describe(@post_score_schema)}
  """
  # [AGS §3.4](https://www.imsglobal.org/spec/lti-ags/v2p0/#score-publish-service)
  @spec post_score(Client.t(), Score.t(), keyword()) ::
          :ok | {:error, Exception.t()}
  def post_score(%Client{} = client, %Score{} = score, opts \\ []) do
    metadata = span_metadata(client)

    :telemetry.span([:ltix, :grade_service, :post_score], metadata, fn ->
      result =
        with {:ok, opts} <- parse_opts(@post_score_schema, opts),
             :ok <- check_expiry(client),
             :ok <- Client.require_scope(client, @scope_score),
             {:ok, base_url} <- resolve_line_item_url(client, opts),
             url = derive_url(base_url, "scores"),
             headers = auth_headers(client, nil),
             req_opts =
               build_request(
                 :post,
                 merged_req_options(client),
                 url,
                 headers,
                 @score_media_type,
                 score
               ),
             {:ok, _body} <- request(req_opts) do
          :ok
        end

      {result, metadata}
    end)
  end

  @get_results_schema Zoi.keyword(
                        line_item:
                          Zoi.union([Zoi.string(), Zoi.struct(LineItem)],
                            description:
                              "Line item URL or struct. Defaults to the endpoint's `lineitem`."
                          ),
                        user_id: Zoi.string(description: "Filter results to a single user."),
                        per_page: Zoi.integer(description: "Page size hint.") |> Zoi.positive()
                      )

  @doc """
  Fetch results for a line item.

  GETs `{lineitem}/results`. Follows all `rel="next"` pagination links
  and returns a list of `%Result{}` structs.

  ## Options

  #{Zoi.describe(@get_results_schema)}
  """
  # [AGS §3.3](https://www.imsglobal.org/spec/lti-ags/v2p0/#result-service)
  @spec get_results(Client.t(), keyword()) ::
          {:ok, [Result.t()]} | {:error, Exception.t()}
  def get_results(%Client{} = client, opts \\ []) do
    metadata = span_metadata(client)

    :telemetry.span([:ltix, :grade_service, :get_results], metadata, fn ->
      result =
        with {:ok, opts} <- parse_opts(@get_results_schema, opts),
             :ok <- check_expiry(client),
             :ok <- Client.require_scope(client, @scope_result_readonly),
             {:ok, base_url} <- resolve_line_item_url(client, opts),
             url = derive_url(base_url, "results"),
             params = get_results_params(opts),
             headers = auth_headers(client, @result_container_media_type),
             {:ok, pages} <-
               Pagination.stream(url, headers,
                 params: params,
                 req_options: merged_req_options(client)
               ) do
          collect_results(pages)
        end

      {result, metadata}
    end)
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

  defp get_endpoint(%Client{endpoints: endpoints}) do
    Map.fetch!(endpoints, __MODULE__)
  end

  defp span_metadata(%Client{} = client) do
    endpoint = get_endpoint(client)
    %{endpoint: endpoint.lineitems || endpoint.lineitem}
  end

  defp require_line_items_url(%Client{} = client) do
    endpoint = get_endpoint(client)

    case endpoint.lineitems do
      nil ->
        {:error,
         ServiceNotAvailable.exception(
           service: __MODULE__,
           spec_ref: "AGS §3.2"
         )}

      url ->
        {:ok, url}
    end
  end

  defp resolve_line_item_url(%Client{} = client, opts) do
    case Keyword.get(opts, :line_item) do
      nil ->
        endpoint = get_endpoint(client)

        case endpoint.lineitem do
          nil ->
            {:error,
             ServiceNotAvailable.exception(
               service: __MODULE__,
               spec_ref: "AGS §3.1"
             )}

          url ->
            {:ok, url}
        end

      %LineItem{id: id} when is_binary(id) ->
        {:ok, id}

      url when is_binary(url) ->
        {:ok, url}
    end
  end

  # [AGS §3.3.1, §3.4.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#result-service)
  defp derive_url(line_item_url, suffix) do
    uri = URI.parse(line_item_url)
    path = String.trim_trailing(uri.path, "/") <> "/" <> suffix
    URI.to_string(%{uri | path: path})
  end

  defp extract_line_item_url(%LineItem{id: id}) when is_binary(id), do: id
  defp extract_line_item_url(url) when is_binary(url), do: url

  defp check_coupled_guard(%Client{} = client, url, false) do
    endpoint = get_endpoint(client)

    if endpoint.lineitem != nil and endpoint.lineitem == url do
      {:error,
       CoupledLineItem.exception(
         line_item_url: url,
         spec_ref: "AGS §3.2"
       )}
    else
      :ok
    end
  end

  defp check_coupled_guard(_client, _url, true), do: :ok

  defp auth_headers(%Client{access_token: token}, nil) do
    [{"authorization", "Bearer #{token}"}]
  end

  defp auth_headers(%Client{access_token: token}, accept) do
    [
      {"accept", accept},
      {"authorization", "Bearer #{token}"}
    ]
  end

  defp merged_req_options(%Client{} = client) do
    Ltix.HTTP.req_options(client.req_options, __MODULE__)
  end

  defp build_request(method, req_options, url, headers) do
    req_options
    |> Keyword.put(:method, method)
    |> Keyword.put(:url, url)
    |> Keyword.put(:headers, headers)
  end

  defp build_request(method, req_options, url, headers, content_type, body) do
    req_options
    |> Keyword.put(:method, method)
    |> Keyword.put(:url, url)
    |> Keyword.put(:headers, [{"content-type", content_type} | headers])
    |> Keyword.put(:body, AppConfig.json_library!().encode!(body))
  end

  defp list_line_items_params(opts) do
    params = %{}

    params
    |> maybe_put_param("resource_link_id", Keyword.get(opts, :resource_link_id))
    |> maybe_put_param("resource_id", Keyword.get(opts, :resource_id))
    |> maybe_put_param("tag", Keyword.get(opts, :tag))
    |> maybe_put_param(
      "limit",
      case Keyword.get(opts, :per_page) do
        nil -> nil
        n -> Integer.to_string(n)
      end
    )
  end

  defp get_results_params(opts) do
    params = %{}

    params
    |> maybe_put_param("user_id", Keyword.get(opts, :user_id))
    |> maybe_put_param(
      "limit",
      case Keyword.get(opts, :per_page) do
        nil -> nil
        n -> Integer.to_string(n)
      end
    )
  end

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, key, value), do: Map.put(params, key, value)

  defp collect_line_items(pages) do
    items =
      Enum.flat_map(pages, fn body ->
        Enum.map(body, fn item_json ->
          {:ok, item} = LineItem.from_json(item_json)
          item
        end)
      end)

    {:ok, items}
  end

  defp collect_results(pages) do
    results =
      Enum.flat_map(pages, fn body ->
        Enum.map(body, fn result_json ->
          {:ok, result} = Result.from_json(result_json)
          result
        end)
      end)

    {:ok, results}
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

  defp request(req_opts) do
    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, TransportError.exception(status: status, body: body, url: req_opts[:url])}

      {:error, exception} ->
        {:error, exception}
    end
  end
end
