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

  alias Ltix.Errors.Invalid.{
    CoupledLineItem,
    InvalidEndpoint,
    ServiceNotAvailable
  }

  alias Ltix.Errors.Security.AccessTokenExpired
  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.GradeService.{LineItem, Result, Score}
  alias Ltix.LaunchClaims
  alias Ltix.LaunchClaims.AgsEndpoint
  alias Ltix.LaunchContext
  alias Ltix.OAuth
  alias Ltix.OAuth.Client
  alias Ltix.Pagination
  alias Ltix.Registration

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

  @context_auth_schema NimbleOptions.new!(
                         req_options: [
                           type: :keyword_list,
                           default: [],
                           doc: "Options passed through to `Req.request/2`."
                         ]
                       )

  @registration_auth_schema NimbleOptions.new!(
                              endpoint: [
                                type: {:struct, AgsEndpoint},
                                required: true,
                                doc: "AGS endpoint struct."
                              ],
                              req_options: [
                                type: :keyword_list,
                                default: [],
                                doc: "Options passed through to `Req.request/2`."
                              ]
                            )

  @doc """
  Acquire an OAuth token for the grade service.

  Accepts a `%LaunchContext{}` or a `%Registration{}`. With a launch context,
  the endpoint and scopes are extracted from the AGS claim. With a
  registration, pass the endpoint via the `:endpoint` option.

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
        OAuth.authenticate(context.registration,
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

  @list_line_items_schema NimbleOptions.new!(
                            resource_link_id: [
                              type: :string,
                              doc: "Filter to line items bound to this resource link."
                            ],
                            resource_id: [
                              type: :string,
                              doc: "Filter by the tool's resource identifier."
                            ],
                            tag: [
                              type: :string,
                              doc: "Filter by tag."
                            ],
                            per_page: [
                              type: :pos_integer,
                              doc: "Page size hint."
                            ]
                          )

  @doc """
  Fetch all line items from the container endpoint.

  Follows all `rel="next"` pagination links and returns a flat list
  of `%LineItem{}` structs.

  ## Options

  #{NimbleOptions.docs(@list_line_items_schema)}
  """
  # [AGS §3.2.4](https://www.imsglobal.org/spec/lti-ags/v2p0/#getting-all-the-line-items-in-the-container-url)
  @spec list_line_items(Client.t(), keyword()) ::
          {:ok, [LineItem.t()]} | {:error, Exception.t()}
  def list_line_items(%Client{} = client, opts \\ []) do
    with {:ok, opts} <- NimbleOptions.validate(opts, @list_line_items_schema),
         :ok <- check_expiry(client),
         :ok <- Client.require_any_scope(client, [@scope_lineitem, @scope_lineitem_readonly]),
         {:ok, url} <- require_line_items_url(client) do
      params = list_line_items_params(opts)
      headers = auth_headers(client, @lineitem_container_media_type)

      with {:ok, pages} <-
             Pagination.stream(url, headers, params: params, req_options: client.req_options) do
        collect_line_items(pages)
      end
    end
  end

  @get_line_item_schema NimbleOptions.new!(
                          line_item: [
                            type: {:or, [:string, {:struct, LineItem}]},
                            doc: "Line item URL or struct. Defaults to the endpoint's `lineitem`."
                          ]
                        )

  @doc """
  Fetch a single line item.

  ## Options

  #{NimbleOptions.docs(@get_line_item_schema)}
  """
  @spec get_line_item(Client.t(), keyword()) ::
          {:ok, LineItem.t()} | {:error, Exception.t()}
  def get_line_item(%Client{} = client, opts \\ []) do
    with {:ok, opts} <- NimbleOptions.validate(opts, @get_line_item_schema),
         :ok <- check_expiry(client),
         :ok <- Client.require_any_scope(client, [@scope_lineitem, @scope_lineitem_readonly]),
         {:ok, url} <- resolve_line_item_url(client, opts) do
      headers = auth_headers(client, @lineitem_media_type)
      req_opts = build_req_opts(client, url, headers)

      case Req.get(req_opts) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          LineItem.from_json(body)

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, TransportError.exception(status: status, body: body, url: url)}

        {:error, exception} ->
          {:error, exception}
      end
    end
  end

  @create_line_item_schema NimbleOptions.new!(
                             label: [
                               type: :string,
                               required: true,
                               doc: "Human-readable label."
                             ],
                             score_maximum: [
                               type: {:custom, __MODULE__, :validate_positive_number, []},
                               required: true,
                               doc: "Maximum score (must be > 0)."
                             ],
                             resource_link_id: [type: :string, doc: "Bind to a resource link."],
                             resource_id: [type: :string, doc: "Tool's resource identifier."],
                             tag: [type: :string, doc: "Qualifier tag."],
                             start_date_time: [type: :string, doc: "ISO 8601 with timezone."],
                             end_date_time: [type: :string, doc: "ISO 8601 with timezone."],
                             grades_released: [
                               type: :boolean,
                               doc: "Hint about releasing grades."
                             ],
                             extensions: [
                               type: {:map, :string, :any},
                               default: %{},
                               doc: "Extension properties keyed by fully qualified URLs."
                             ]
                           )

  @doc """
  Create a new line item.

  ## Options

  #{NimbleOptions.docs(@create_line_item_schema)}
  """
  # [AGS §3.2.5](https://www.imsglobal.org/spec/lti-ags/v2p0/#creating-a-new-line-item)
  @spec create_line_item(Client.t(), keyword()) ::
          {:ok, LineItem.t()} | {:error, Exception.t()}
  def create_line_item(%Client{} = client, opts) do
    with {:ok, opts} <- NimbleOptions.validate(opts, @create_line_item_schema),
         :ok <- check_expiry(client),
         :ok <- Client.require_scope(client, @scope_lineitem),
         {:ok, url} <- require_line_items_url(client),
         {:ok, json} <- LineItem.to_json(struct!(LineItem, Enum.into(opts, %{}))) do
      headers = auth_headers(client, nil)
      req_opts = build_req_opts_with_body(client, url, headers, @lineitem_media_type, json)

      case Req.post(req_opts) do
        {:ok, %Req.Response{status: status, body: body}} when status in [200, 201] ->
          LineItem.from_json(body)

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, TransportError.exception(status: status, body: body, url: url)}

        {:error, exception} ->
          {:error, exception}
      end
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
  def update_line_item(%Client{} = _client, %LineItem{id: nil}) do
    {:error,
     ServiceNotAvailable.exception(
       service: __MODULE__,
       spec_ref: "AGS §3.2.6"
     )}
  end

  def update_line_item(%Client{} = client, %LineItem{} = item) do
    with :ok <- check_expiry(client),
         :ok <- Client.require_scope(client, @scope_lineitem),
         {:ok, json} <- LineItem.to_json(item) do
      url = item.id
      headers = auth_headers(client, nil)
      req_opts = build_req_opts_with_body(client, url, headers, @lineitem_media_type, json)

      case Req.put(req_opts) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          LineItem.from_json(body)

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, TransportError.exception(status: status, body: body, url: url)}

        {:error, exception} ->
          {:error, exception}
      end
    end
  end

  @delete_line_item_schema NimbleOptions.new!(
                             force: [
                               type: :boolean,
                               default: false,
                               doc:
                                 "Delete even if this is the coupled line item from the launch claim."
                             ]
                           )

  @doc """
  Delete a line item.

  Accepts a `%LineItem{}` struct or a URL string. Returns `:ok` on
  success.

  By default, refuses to delete the platform-coupled line item
  (the `lineitem` URL from the launch claim). Pass `force: true`
  to override.

  ## Options

  #{NimbleOptions.docs(@delete_line_item_schema)}
  """
  @spec delete_line_item(Client.t(), LineItem.t() | String.t(), keyword()) ::
          :ok | {:error, Exception.t()}
  def delete_line_item(%Client{} = client, line_item_or_url, opts \\ []) do
    url = extract_line_item_url(line_item_or_url)

    with {:ok, opts} <- NimbleOptions.validate(opts, @delete_line_item_schema),
         :ok <- check_expiry(client),
         :ok <- Client.require_scope(client, @scope_lineitem),
         :ok <- check_coupled_guard(client, url, Keyword.get(opts, :force, false)) do
      headers = auth_headers(client, nil)
      req_opts = build_req_opts(client, url, headers)

      case Req.delete(req_opts) do
        {:ok, %Req.Response{status: status}} when status in [200, 204] ->
          :ok

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, TransportError.exception(status: status, body: body, url: url)}

        {:error, exception} ->
          {:error, exception}
      end
    end
  end

  @post_score_schema NimbleOptions.new!(
                       line_item: [
                         type: {:or, [:string, {:struct, LineItem}]},
                         doc: "Line item URL or struct. Defaults to the endpoint's `lineitem`."
                       ]
                     )

  @doc """
  Post a score for a user.

  The score is POSTed to `{lineitem}/scores`. When no `:line_item` option
  is given, uses the endpoint's `lineitem` URL (coupled flow).

  ## Options

  #{NimbleOptions.docs(@post_score_schema)}
  """
  # [AGS §3.4](https://www.imsglobal.org/spec/lti-ags/v2p0/#score-publish-service)
  @spec post_score(Client.t(), Score.t(), keyword()) ::
          :ok | {:error, Exception.t()}
  def post_score(%Client{} = client, %Score{} = score, opts \\ []) do
    with {:ok, opts} <- NimbleOptions.validate(opts, @post_score_schema),
         :ok <- check_expiry(client),
         :ok <- Client.require_scope(client, @scope_score),
         {:ok, base_url} <- resolve_line_item_url(client, opts) do
      url = derive_url(base_url, "scores")
      json = Score.to_json(score)
      headers = auth_headers(client, nil)
      req_opts = build_req_opts_with_body(client, url, headers, @score_media_type, json)

      case Req.post(req_opts) do
        {:ok, %Req.Response{status: status}} when status in [200, 204] ->
          :ok

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, TransportError.exception(status: status, body: body, url: url)}

        {:error, exception} ->
          {:error, exception}
      end
    end
  end

  @get_results_schema NimbleOptions.new!(
                        line_item: [
                          type: {:or, [:string, {:struct, LineItem}]},
                          doc: "Line item URL or struct. Defaults to the endpoint's `lineitem`."
                        ],
                        user_id: [
                          type: :string,
                          doc: "Filter results to a single user."
                        ],
                        per_page: [
                          type: :pos_integer,
                          doc: "Page size hint."
                        ]
                      )

  @doc """
  Fetch results for a line item.

  GETs `{lineitem}/results`. Follows all `rel="next"` pagination links
  and returns a list of `%Result{}` structs.

  ## Options

  #{NimbleOptions.docs(@get_results_schema)}
  """
  # [AGS §3.3](https://www.imsglobal.org/spec/lti-ags/v2p0/#result-service)
  @spec get_results(Client.t(), keyword()) ::
          {:ok, [Result.t()]} | {:error, Exception.t()}
  def get_results(%Client{} = client, opts \\ []) do
    with {:ok, opts} <- NimbleOptions.validate(opts, @get_results_schema),
         :ok <- check_expiry(client),
         :ok <- Client.require_scope(client, @scope_result_readonly),
         {:ok, base_url} <- resolve_line_item_url(client, opts) do
      url = derive_url(base_url, "results")
      params = get_results_params(opts)
      headers = auth_headers(client, @result_container_media_type)

      with {:ok, pages} <-
             Pagination.stream(url, headers, params: params, req_options: client.req_options) do
        collect_results(pages)
      end
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

  defp build_req_opts(%Client{} = client, url, headers) do
    client.req_options
    |> Keyword.put(:url, url)
    |> Keyword.put(:headers, headers)
  end

  defp build_req_opts_with_body(%Client{} = client, url, headers, content_type, body) do
    client.req_options
    |> Keyword.put(:url, url)
    |> Keyword.put(:headers, [{"content-type", content_type} | headers])
    |> Keyword.put(:body, JSON.encode!(body))
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
      pages
      |> Enum.flat_map(fn body ->
        Enum.map(body, fn item_json ->
          {:ok, item} = LineItem.from_json(item_json)
          item
        end)
      end)

    {:ok, items}
  end

  defp collect_results(pages) do
    results =
      pages
      |> Enum.flat_map(fn body ->
        Enum.map(body, fn result_json ->
          {:ok, result} = Result.from_json(result_json)
          result
        end)
      end)

    {:ok, results}
  end

  @doc false
  def validate_positive_number(value) when is_number(value) and value > 0, do: {:ok, value}

  def validate_positive_number(value) do
    {:error, "expected a positive number (> 0), got: #{inspect(value)}"}
  end
end
