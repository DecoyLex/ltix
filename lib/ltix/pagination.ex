defmodule Ltix.Pagination do
  @moduledoc """
  Lazy paginated fetching for LTI Advantage endpoints.

  LTI Advantage services use RFC 8288 `Link` headers with `rel="next"` for
  pagination. This module handles link parsing and builds a lazy stream that
  fetches pages on demand.
  """

  alias Ltix.Errors.Invalid.MalformedResponse
  alias Ltix.Errors.Unknown.TransportError

  @max_empty_pages 5

  @stream_schema NimbleOptions.new!(
                   parse: [
                     type: {:fun, 1},
                     required: true,
                     doc:
                       "Callback that receives the decoded JSON response body and returns a list of parsed items."
                   ],
                   params: [
                     type: {:map, :string, :string},
                     default: %{},
                     doc: "Query parameters for the first page only."
                   ],
                   req_options: [
                     type: :keyword_list,
                     default: [],
                     doc: "Options passed through to `Req.get/1`."
                   ]
                 )

  @doc """
  Fetch a paginated endpoint as a lazy stream.

  Fetches the first page eagerly. If it succeeds, returns `{:ok, stream}`
  where subsequent pages are fetched lazily as the stream is consumed.
  If the first page fails, returns `{:error, reason}` immediately.

  The `parse` callback receives the decoded JSON response body and returns
  a list of parsed items for that page.

  ## Options

  #{NimbleOptions.docs(@stream_schema)}
  """
  @spec stream(String.t(), [{String.t(), String.t()}], keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def stream(url, headers, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @stream_schema)
    parse = Keyword.fetch!(opts, :parse)
    params = Keyword.fetch!(opts, :params)
    req_options = req_options(opts)

    case fetch_page(url, headers, params, parse, req_options) do
      {:ok, items, next_url} ->
        {:ok, build_stream(items, next_url, headers, parse, req_options)}

      {:error, _} = error ->
        error
    end
  end

  defp build_stream(first_items, next_url, headers, parse, req_options) do
    Stream.resource(
      fn -> {first_items, next_url, 0} end,
      &emit(&1, headers, parse, req_options),
      fn _ -> :ok end
    )
  end

  defp emit({[item | rest], next_url, _empties}, _headers, _parse, _req_options) do
    {[item], {rest, next_url, 0}}
  end

  defp emit({[], nil, _empties}, _headers, _parse, _req_options) do
    {:halt, :done}
  end

  defp emit({[], _next_url, empties}, _headers, _parse, _req_options)
       when empties >= @max_empty_pages do
    raise MalformedResponse.exception(
            reason: "#{empties} consecutive empty pages with rel=\"next\" links"
          )
  end

  defp emit({[], next_url, empties}, headers, parse, req_options) do
    case fetch_page(next_url, headers, %{}, parse, req_options) do
      {:ok, [item | rest], next_next} -> {[item], {rest, next_next, 0}}
      {:ok, [], nil} -> {:halt, :done}
      {:ok, [], next_next} -> {[], {[], next_next, empties + 1}}
      {:error, reason} -> raise reason
    end
  end

  defp fetch_page(url, headers, params, parse, req_options) do
    req_opts =
      req_options
      |> Keyword.put(:url, url)
      |> Keyword.put(:headers, headers)
      |> then(fn opts ->
        if params == %{}, do: opts, else: Keyword.put(opts, :params, params)
      end)

    case Req.get(req_opts) do
      {:ok, %Req.Response{status: 200, body: body, headers: resp_headers}} ->
        case parse.(body) do
          items when is_list(items) ->
            next_url = parse_next_link(resp_headers)
            {:ok, items, next_url}

          {:error, _} = error ->
            error
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, TransportError.exception(status: status, body: body, url: url)}

      {:error, exception} ->
        {:error, exception}
    end
  end

  @doc """
  Extract the `rel="next"` URL from response headers.

  Parses [RFC 8288](https://www.rfc-editor.org/rfc/rfc8288) `Link` headers
  and returns the URL with `rel="next"`, or `nil` if not present.

      iex> Ltix.Pagination.parse_next_link(%{"link" => ["<https://example.com/p2>; rel=\\"next\\""]})
      "https://example.com/p2"

      iex> Ltix.Pagination.parse_next_link(%{})
      nil
  """
  @spec parse_next_link(%{String.t() => [String.t()]}) :: String.t() | nil
  def parse_next_link(headers) do
    headers
    |> Map.get("link", [])
    |> Enum.find_value(&extract_next_url/1)
  end

  defp extract_next_url(header_value) do
    header_value
    |> String.split(",")
    |> Enum.find_value(fn part ->
      part = String.trim(part)

      with [_, url] <- Regex.run(~r/^<([^>]+)>/, part),
           true <- String.match?(part, ~r/rel\s*=\s*"next"/) do
        url
      else
        _ -> nil
      end
    end)
  end

  defp req_options(opts) do
    default = Application.get_env(:ltix, :req_options, [])
    Keyword.merge(default, Keyword.get(opts, :req_options, []))
  end
end
