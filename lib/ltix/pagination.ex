defmodule Ltix.Pagination do
  @moduledoc """
  Lazy paginated fetching for LTI Advantage endpoints.

  LTI Advantage services use RFC 8288 `Link` headers with `rel="next"` for
  pagination. This module handles link parsing and builds a lazy stream that
  fetches pages on demand. A next link back to a page already fetched is a
  `Ltix.Errors.Unknown.TransportError`.
  """

  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.Options
  alias Req.Steps, as: RequestSteps

  @stream_schema Zoi.keyword(
                   [
                     params:
                       Zoi.map(Zoi.string(), Zoi.string(),
                         description: "Query parameters for the first page only."
                       )
                       |> Zoi.default(%{}),
                     req_options:
                       Zoi.keyword(Zoi.any(),
                         description:
                           "Options for `Req.request/2` on each page request. They're merged over the configured ones."
                       )
                       |> Zoi.default([]),
                     local_network_access: Ltix.HTTP.local_network_access_option()
                   ],
                   unrecognized_keys: :error
                 )

  @doc """
  Fetch a paginated endpoint as a lazy stream of response bodies.

  Fetches the first page eagerly. If it succeeds, returns `{:ok, stream}`
  where each element is a decoded JSON response body. Subsequent pages are
  fetched lazily as the stream is consumed. If the first page fails, returns
  `{:error, reason}` immediately. Later failures raise during enumeration.

  ## Options

  When you [configure](`m:Ltix#module-configuration`) an option, the configured
  value is its default.

  #{Zoi.describe(@stream_schema)}
  """
  @spec stream(String.t(), [{String.t(), String.t()}], keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def stream(url, headers, opts \\ []) do
    case stream_results(url, headers, opts) do
      {:ok, pages} ->
        {:ok,
         Stream.map(pages, fn
           {:ok, body} -> body
           {:error, error} -> raise error
         end)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Fetch a paginated endpoint as a lazy stream of result tuples.

  Fetches the first page eagerly. Returns `{:ok, stream}` with `{:ok, body}`
  for each page, or `{:error, error}` if the first page fails. A later failure
  emits one `{:error, error}` and ends the stream.

  ## Options

  When you [configure](`m:Ltix#module-configuration`) an option, the configured
  value is its default.

  #{Zoi.describe(@stream_schema)}
  """
  @spec stream_results(String.t(), [{String.t(), String.t()}], keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def stream_results(url, headers, opts \\ []) do
    opts = Options.parse!(opts, @stream_schema)
    {configured_params, req_options} = Keyword.pop(req_options(opts), :params, [])

    params =
      case Keyword.fetch!(opts, :params) do
        params when map_size(params) == 0 -> configured_params
        params -> params
      end

    req_options = Keyword.merge(req_options, method: :get, headers: headers)

    paginate(url, params, &Ltix.HTTP.request_success(Keyword.put(req_options, :url, &1)))
  end

  @doc false
  # Streams result tuples for the pages `fetch` returns, starting at `url`
  # with `params`. `fetch` takes a page URL and returns `{:ok, response}` for
  # a successful response.
  @spec paginate(term(), Enumerable.t(), (String.t() ->
                                            {:ok, Req.Response.t()} | {:error, Exception.t()})) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def paginate(url, params, fetch) do
    with {:ok, base_uri} <- Ltix.HTTP.validate_url(url),
         first_url = put_params(url, params),
         {:ok, first_body, next_url, fetched} <-
           fetch_page(first_url, fetch, base_uri, MapSet.new()) do
      {:ok,
       Stream.resource(
         fn -> {:first, first_body, next_url, fetched} end,
         &next_page(&1, fetch, base_uri),
         fn _ -> :ok end
       )}
    end
  end

  defp put_params(url, params) when map_size(params) == 0 or params == [], do: url

  defp put_params(url, params) do
    [url: url, params: params]
    |> Req.new()
    |> RequestSteps.put_params()
    |> then(&URI.to_string(&1.url))
  end

  defp next_page({:first, body, next_url, fetched}, _fetch, _base_uri) do
    {[{:ok, body}], {next_url, fetched}}
  end

  defp next_page(:done, _fetch, _base_uri), do: {:halt, :done}
  defp next_page({nil, _fetched}, _fetch, _base_uri), do: {:halt, :done}

  defp next_page({url, fetched}, fetch, base_uri) do
    case fetch_page(url, fetch, base_uri, fetched) do
      {:ok, body, next_url, fetched} -> {[{:ok, body}], {next_url, fetched}}
      {:error, reason} -> {[{:error, reason}], :done}
    end
  end

  # `fetched` holds the URLs of the pages fetched so far.
  defp fetch_page(url, fetch, base_uri, fetched) do
    with {:ok, %Req.Response{body: body, headers: headers} = response} <- fetch.(url),
         response_url = Req.Response.get_private(response, :ltix_response_url, url),
         fetched = MapSet.union(fetched, MapSet.new([url, response_url], &page_key/1)),
         {:ok, next_url} <- validate_next_url(parse_next_link(headers, response_url), base_uri),
         :ok <- validate_not_fetched(next_url, fetched) do
      {:ok, body, next_url, fetched}
    end
  end

  # Fragments are not sent, so URLs that differ only by fragment are one page.
  defp page_key(url), do: URI.to_string(%{URI.parse(url) | fragment: nil})

  defp validate_not_fetched(nil, _fetched), do: :ok

  defp validate_not_fetched(next_url, fetched) do
    if MapSet.member?(fetched, page_key(next_url)) do
      {:error,
       TransportError.exception(
         body: "Next page URL #{next_url} returns to a page already fetched",
         url: next_url
       )}
    else
      :ok
    end
  end

  defp validate_next_url(nil, _base_uri), do: {:ok, nil}

  # The application limits pagination to the initial endpoint origin.
  # [RFC 6454 §4 and §5](https://www.rfc-editor.org/rfc/rfc6454#section-4)
  defp validate_next_url(url, base_uri) do
    case Ltix.HTTP.validate_url(url) do
      {:ok, next_uri}
      when next_uri.scheme == base_uri.scheme and next_uri.host == base_uri.host and
             next_uri.port == base_uri.port ->
        {:ok, url}

      {:ok, _next_uri} ->
        {:error,
         TransportError.exception(
           body: "Next page URL origin mismatch. Pagination must stay on the initial HTTPS origin"
         )}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Extract the `rel="next"` target from response headers.

  Parses [RFC 8288](https://www.rfc-editor.org/rfc/rfc8288) `Link` headers
  and returns the target as supplied, or `nil` if not present. Ignores links
  with an `anchor` parameter. Use `parse_next_link/2` to resolve relative
  targets.

      iex> Ltix.Pagination.parse_next_link(%{"link" => ["<https://example.com/p2>; rel=\\"next\\""]})
      "https://example.com/p2"

      iex> Ltix.Pagination.parse_next_link(%{"link" => ["<?page=2>; rel=next"]})
      "?page=2"

      iex> Ltix.Pagination.parse_next_link(%{})
      nil
  """
  @spec parse_next_link(%{String.t() => [String.t()]}) :: String.t() | nil
  def parse_next_link(headers) do
    Enum.find_value(headers, fn {name, values} ->
      if String.downcase(name, :ascii) == "link" do
        Enum.find_value(values, &extract_next_url/1)
      end
    end)
  end

  @doc """
  Extract the `rel="next"` URL, resolving relative targets against
  `response_url`.

  Pass the URL of the response that has the headers. Returns `nil` if no
  next link is present. Ignores links with an `anchor` parameter.

      iex> Ltix.Pagination.parse_next_link(
      ...>   %{"link" => ["<../three>; rel=next"]},
      ...>   "https://example.com/pages/two"
      ...> )
      "https://example.com/three"
  """
  @spec parse_next_link(%{String.t() => [String.t()]}, String.t()) :: String.t() | nil
  def parse_next_link(headers, response_url) do
    case parse_next_link(headers) do
      nil ->
        nil

      target ->
        with {:ok, %URI{scheme: nil} = target_uri} <- URI.new(target),
             {:ok, %URI{scheme: scheme} = response_uri} when not is_nil(scheme) <-
               URI.new(response_url) do
          to_string(URI.merge(response_uri, target_uri))
        else
          _ -> target
        end
    end
  end

  defp extract_next_url(header_value) do
    # [RFC 7230 §7](https://www.rfc-editor.org/rfc/rfc7230#section-7)
    with "<" <> rest <- trim_whitespace(header_value),
         [target, rest] <- String.split(rest, ">", parts: 2),
         {:ok, parameters, rest} <- parse_parameters(rest, %{}) do
      relations = String.split(Map.get(parameters, "rel", ""), " ", trim: true)

      if !Map.has_key?(parameters, "anchor") &&
           Enum.any?(relations, &(String.downcase(&1, :ascii) == "next")) do
        target
      else
        extract_next_url(rest)
      end
    else
      "," <> rest -> extract_next_url(rest)
      _ -> nil
    end
  end

  defp parse_parameters(input, parameters) do
    case trim_whitespace(input) do
      ";" <> rest -> parse_parameter(rest, parameters)
      "," <> rest -> {:ok, parameters, rest}
      "" -> {:ok, parameters, ""}
      _ -> :error
    end
  end

  defp parse_parameter(input, parameters) do
    with {:ok, name, rest} <- take_token(trim_whitespace(input)),
         {:ok, value, rest} <- parse_parameter_value(trim_whitespace(rest)) do
      parse_parameters(rest, Map.put_new(parameters, String.downcase(name, :ascii), value))
    end
  end

  defp parse_parameter_value("=" <> rest), do: take_value(trim_whitespace(rest))
  defp parse_parameter_value(rest), do: {:ok, "", rest}

  defp take_value("\"" <> rest), do: take_quoted_value(rest, [])
  defp take_value(input), do: take_token(input)

  defp take_quoted_value("\\" <> <<character, rest::binary>>, characters),
    do: take_quoted_value(rest, [character | characters])

  defp take_quoted_value("\"" <> rest, characters),
    do: {:ok, :erlang.list_to_binary(Enum.reverse(characters)), rest}

  defp take_quoted_value(<<character, rest::binary>>, characters),
    do: take_quoted_value(rest, [character | characters])

  defp take_quoted_value("", _characters), do: :error

  defp take_token(input) do
    case Regex.run(~r/^[!#$%&'*+\-.^_`|~0-9A-Za-z]+/, input) do
      [token] ->
        size = byte_size(token)
        {:ok, token, binary_part(input, size, byte_size(input) - size)}

      nil ->
        :error
    end
  end

  defp trim_whitespace(<<character, rest::binary>>) when character in [32, 9],
    do: trim_whitespace(rest)

  defp trim_whitespace(input), do: input

  defp req_options(opts) do
    Keyword.put(
      Keyword.merge(Ltix.HTTP.req_options([], __MODULE__), Keyword.get(opts, :req_options, [])),
      :local_network_access,
      Keyword.get(opts, :local_network_access)
    )
  end
end
