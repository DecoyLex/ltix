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

    with {:ok, base_uri} <- Ltix.HTTP.validate_url(url),
         {:ok, first_body, next_url} <- fetch_page(url, headers, params, req_options, base_uri) do
      {:ok,
       Stream.resource(
         fn -> {:first, first_body, next_url} end,
         &next_page(&1, headers, req_options, base_uri),
         fn _ -> :ok end
       )}
    end
  end

  defp next_page({:first, body, next_url}, _headers, _req_options, _base_uri) do
    {[body], next_url}
  end

  defp next_page(nil, _headers, _req_options, _base_uri) do
    {:halt, :done}
  end

  defp next_page(url, headers, req_options, base_uri) do
    case fetch_page(url, headers, %{}, req_options, base_uri) do
      {:ok, body, next_url} -> {[body], next_url}
      {:error, reason} -> raise reason
    end
  end

  defp fetch_page(url, headers, params, req_options, base_uri) do
    req_opts =
      req_options
      |> Keyword.put(:url, url)
      |> Keyword.put(:headers, headers)
      |> then(fn opts ->
        if params == %{}, do: opts, else: Keyword.put(opts, :params, params)
      end)

    case Ltix.HTTP.request(Keyword.put(req_opts, :method, :get)) do
      {:ok, %Req.Response{status: 200, body: body, headers: resp_headers}} ->
        next_url =
          resp_headers
          |> parse_next_link(url)
          |> validate_next_url!(base_uri)

        {:ok, body, next_url}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, TransportError.exception(status: status, body: body, url: url)}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp validate_next_url!(nil, _base_uri), do: nil

  # The application limits pagination to the initial endpoint origin.
  # [RFC 6454 §4 and §5](https://www.rfc-editor.org/rfc/rfc6454#section-4)
  defp validate_next_url!(url, base_uri) do
    case Ltix.HTTP.validate_url(url) do
      {:ok, next_uri}
      when next_uri.scheme == base_uri.scheme and next_uri.host == base_uri.host and
             next_uri.port == base_uri.port ->
        url

      {:ok, _next_uri} ->
        raise TransportError,
          body: "Next page URL origin mismatch. Pagination must stay on the initial HTTPS origin"

      {:error, error} ->
        raise error
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

  Pass the URL of the response carrying the headers. Returns `nil` if no
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
        if URI.parse(target).scheme, do: target, else: to_string(URI.merge(response_url, target))
    end
  end

  defp extract_next_url(header_value) do
    # [RFC 7230 §7](https://www.rfc-editor.org/rfc/rfc7230#section-7)
    with "<" <> rest <- trim_whitespace(header_value),
         [target, rest] <- String.split(rest, ">", parts: 2),
         {:ok, parameters, rest} <- parse_parameters(rest, %{}) do
      relations = String.split(Map.get(parameters, "rel", ""), " ", trim: true)

      if not Map.has_key?(parameters, "anchor") and
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
    Keyword.get(opts, :req_options, [])
  end
end
