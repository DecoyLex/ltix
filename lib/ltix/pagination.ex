defmodule Ltix.Pagination do
  @moduledoc """
  Lazy paginated fetching for LTI Advantage endpoints.

  LTI Advantage services use RFC 8288 `Link` headers with `rel="next"` for
  pagination. This module handles link parsing and builds a lazy stream that
  fetches pages on demand.
  """

  alias Ltix.Errors.Unknown.TransportError

  @stream_schema Zoi.keyword(
                   params:
                     Zoi.map(Zoi.string(), Zoi.string(),
                       description: "Query parameters for the first page only."
                     )
                     |> Zoi.default(%{}),
                   req_options:
                     Zoi.keyword(Zoi.any(), description: "Options passed through to `Req.get/1`.")
                     |> Zoi.default([])
                 )

  @doc """
  Fetch a paginated endpoint as a lazy stream of response bodies.

  Fetches the first page eagerly. If it succeeds, returns `{:ok, stream}`
  where each element is a decoded JSON response body. Subsequent pages are
  fetched lazily as the stream is consumed. If the first page fails, returns
  `{:error, reason}` immediately.

  ## Options

  #{Zoi.describe(@stream_schema)}
  """
  @spec stream(String.t(), [{String.t(), String.t()}], keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def stream(url, headers, opts \\ []) do
    opts = Zoi.parse!(@stream_schema, opts)
    params = Keyword.fetch!(opts, :params)
    req_options = req_options(opts)

    with {:ok, first_body, next_url} <- fetch_page(url, headers, params, req_options) do
      {:ok,
       Stream.resource(
         fn -> {:first, first_body, next_url} end,
         &next_page(&1, headers, req_options),
         fn _ -> :ok end
       )}
    end
  end

  defp next_page({:first, body, next_url}, _headers, _req_options) do
    {[body], next_url}
  end

  defp next_page(nil, _headers, _req_options) do
    {:halt, :done}
  end

  defp next_page(url, headers, req_options) do
    case fetch_page(url, headers, %{}, req_options) do
      {:ok, body, next_url} -> {[body], next_url}
      {:error, reason} -> raise reason
    end
  end

  defp fetch_page(url, headers, params, req_options) do
    req_opts =
      req_options
      |> Keyword.put(:url, url)
      |> Keyword.put(:headers, headers)
      |> then(fn opts ->
        if params == %{}, do: opts, else: Keyword.put(opts, :params, params)
      end)

    case Req.get(req_opts) do
      {:ok, %Req.Response{status: 200, body: body, headers: resp_headers}} ->
        next_url = parse_next_link(resp_headers)
        {:ok, body, next_url}

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
    Keyword.get(opts, :req_options, [])
  end
end
