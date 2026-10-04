defmodule Ltix.Test.ServiceStub do
  @moduledoc false

  # Routes the requests a service sends to its `Req.Test` stub by operation.
  # Each stubbing process has separate routes. The registered stub function
  # captures them, so they apply in every process allowed with
  # `Req.Test.allow/3`.

  alias Ltix.Errors.Invalid.InvalidOption
  alias Ltix.GradeService
  alias Ltix.HTTP
  alias Ltix.MembershipsService

  @compile {:no_warn_undefined,
            [
              {Plug.Conn, :put_resp_header, 3},
              {Plug.Conn, :request_url, 1}
            ]}

  @line_item GradeService.media_type(:line_item)
  @line_item_container GradeService.media_type(:line_item_container)
  @result_container GradeService.media_type(:result_container)
  @score GradeService.media_type(:score)
  @membership_container MembershipsService.media_type(:membership_container)

  # [AGS §3.3.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#result-service-endpoint)
  # [AGS §3.4.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#service-endpoint)
  @line_item_suffixes %{post_score: "/scores", list_results: "/results"}

  @doc """
  Respond to `operation` requests of `service` with `plug`. A line item URL
  limits the route to requests for that line item, and replaces only the
  route for it.
  """
  @spec put(module(), atom(), String.t() | nil, (Plug.Conn.t() -> Plug.Conn.t())) :: :ok
  def put(service, operation, line_item_url, plug) do
    key = {operation, target(line_item_url, Map.get(@line_item_suffixes, operation, ""))}
    routes = Map.put(Process.get({__MODULE__, service}, %{}), key, plug)
    Process.put({__MODULE__, service}, routes)
    Req.Test.stub(service, &dispatch(&1, service, routes))
  end

  @doc """
  Send `entries` as JSON, one page at a time when the request sets a
  page size with the `limit` query parameter. `wrap` builds the body of a
  page from its entries.
  """
  @spec json_pages(Plug.Conn.t(), list(), (list() -> term())) :: Plug.Conn.t()
  def json_pages(conn, entries, wrap \\ & &1) do
    params = URI.decode_query(conn.query_string)

    with limit when is_integer(limit) <- positive_integer(params["limit"]),
         page when is_integer(page) <- positive_integer(params["page"] || "1") do
      page_entries = Enum.slice(entries, (page - 1) * limit, limit)

      conn
      |> put_next_link(params, page, length(entries) > page * limit)
      |> Req.Test.json(wrap.(page_entries))
    else
      _no_page -> Req.Test.json(conn, wrap.(entries))
    end
  end

  # [RFC 8288](https://www.rfc-editor.org/rfc/rfc8288)
  defp put_next_link(conn, _params, _page, false), do: conn

  defp put_next_link(conn, params, page, true) do
    query = URI.encode_query(Map.put(params, "page", Integer.to_string(page + 1)))
    next = Plug.Conn.request_url(%{conn | query_string: query})
    Plug.Conn.put_resp_header(conn, "link", ~s(<#{next}>; rel="next"))
  end

  defp positive_integer(value) do
    case Integer.parse(value || "") do
      {integer, ""} when integer > 0 -> integer
      _other -> nil
    end
  end

  defp dispatch(conn, service, routes) do
    operation = operation(service, conn)
    target = {conn.host, conn.port, trim_path(conn.request_path)}

    case Map.get(routes, {operation, target}) || Map.get(routes, {operation, nil}) do
      nil -> raise unanswered(conn, service, operation)
      plug -> plug.(conn)
    end
  end

  # [AGS §3.2](https://www.imsglobal.org/spec/lti-ags/v2p0/#line-item-service-scope-and-allowed-http-methods)
  # [AGS §3.3](https://www.imsglobal.org/spec/lti-ags/v2p0/#result-service)
  # [AGS §3.4](https://www.imsglobal.org/spec/lti-ags/v2p0/#score-publish-service)
  defp operation(GradeService, conn) do
    case {conn.method, header(conn, "accept"), header(conn, "content-type")} do
      {"GET", @line_item_container, _} -> :list_line_items
      {"GET", @line_item, _} -> :get_line_item
      {"GET", @result_container, _} -> path_operation(conn, "/results", :list_results)
      {"POST", _, @line_item} -> :create_line_item
      {"POST", _, @score} -> path_operation(conn, "/scores", :post_score)
      {"PUT", _, @line_item} -> :update_line_item
      {"DELETE", _, _} -> :delete_line_item
      _other -> nil
    end
  end

  # [NRPS §2.4](https://www.imsglobal.org/spec/lti-nrps/v2p0/#membership-container-media-type)
  defp operation(MembershipsService, conn) do
    if {conn.method, header(conn, "accept")} == {"GET", @membership_container},
      do: :list_members
  end

  defp path_operation(conn, suffix, operation) do
    if String.ends_with?(trim_path(conn.request_path), suffix), do: operation
  end

  defp header(conn, name) do
    with {_name, value} <- List.keyfind(conn.req_headers, name, 0), do: value
  end

  defp target(nil, _suffix), do: nil

  defp target(url, suffix) do
    case HTTP.validate_url(url) do
      {:ok, uri} ->
        {uri.host, uri.port, trim_path(uri.path || "") <> suffix}

      {:error, _error} ->
        raise InvalidOption,
          key: :line_item,
          value: url,
          reason: "it must be an absolute HTTPS URL"
    end
  end

  defp trim_path(path), do: String.trim_trailing(path, "/")

  defp unanswered(conn, service, operation) do
    request = "#{conn.method} #{Plug.Conn.request_url(conn)}"

    if operation do
      "No Ltix.Test stub matches #{request}. Stub it with Ltix.Test.stub_#{operation}."
    else
      "No Ltix.Test stub matches #{request}, which #{inspect(service)} does not send. " <>
        "Stub it with Req.Test.stub/2."
    end
  end
end
