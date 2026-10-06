defmodule Ltix.AdvantageService.Operation do
  @moduledoc false

  alias Ltix.Errors.Invalid.CollectionTooLarge
  alias Ltix.OAuth.Client

  @type url :: {:ok, String.t()} | {:error, Exception.t()}
  @type counter :: (term() -> non_neg_integer())

  @doc """
  Run `request` with the URL inside a telemetry span named `event`, whose
  `endpoint` metadata is the URL, or `nil` when `url` is an error.

  Returns `Ltix.Errors.Security.AccessTokenExpired` when the client's token has
  expired, `Ltix.Errors.Invalid.ScopeMismatch` when it grants none of `scopes`,
  and the error when `url` is one.
  """
  @spec run([atom()], Client.t(), [String.t()], url(), (String.t() -> term())) :: term()
  def run(event, %Client{} = client, scopes, url, request) do
    metadata = %{endpoint: requested_url(url)}

    :telemetry.span(event, metadata, fn ->
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

  @doc """
  Collect the items of a stream of `{:ok, item}` and `{:error, error}` results.

  Returns the first error, or `Ltix.Errors.Invalid.CollectionTooLarge` with the
  fields in `limit_error` when the sum of `count` over the items exceeds `max`.
  """
  @spec collect(Enumerable.t(), pos_integer() | :infinity, keyword(), counter()) ::
          {:ok, list()} | {:error, Exception.t()}
  def collect(results, max, limit_error, count \\ fn _item -> 1 end) do
    collected =
      Enum.reduce_while(results, {:ok, [], 0}, fn
        {:ok, item}, {:ok, items, total} ->
          total = total + count.(item)

          if max != :infinity and total > max do
            {:halt,
             {:error, CollectionTooLarge.exception([count: total, max: max] ++ limit_error)}}
          else
            {:cont, {:ok, [item | items], total}}
          end

        {:error, _error} = error, _accumulator ->
          {:halt, error}
      end)

    with {:ok, items, _count} <- collected, do: {:ok, Enum.reverse(items)}
  end

  @doc """
  Stream the items of a stream of results, raising the first error.
  """
  @spec stream(Enumerable.t()) :: Enumerable.t()
  def stream(results) do
    Stream.map(results, fn
      {:ok, item} -> item
      {:error, error} -> raise error
    end)
  end
end
