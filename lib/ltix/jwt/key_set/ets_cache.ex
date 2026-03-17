defmodule Ltix.JWT.KeySet.EtsCache do
  @moduledoc """
  Default ETS-backed cache for JWKS key sets.

  Uses a named ETS table (`:ltix_jwks_cache`) created lazily on first access.
  Entries expire based on the `max_age` value from the platform's
  `cache-control` header.
  """

  @behaviour Ltix.JWT.KeySet.Cache

  @table :ltix_jwks_cache

  @impl Ltix.JWT.KeySet.Cache
  def get(jwks_uri) do
    ensure_table()

    with {:ok, entry} <- lookup(jwks_uri),
         :ok <- ensure_valid(entry) do
      {:ok, entry.keys}
    end
  end

  @impl Ltix.JWT.KeySet.Cache
  def put(jwks_uri, keys, max_age) do
    ensure_table()
    :ets.insert(@table, {jwks_uri, keys, System.monotonic_time(:second), max_age})
    :ok
  end

  @impl Ltix.JWT.KeySet.Cache
  def delete(jwks_uri) do
    ensure_table()
    :ets.delete(@table, jwks_uri)
    :ok
  end

  defp ensure_table do
    :ets.new(@table, [:set, :public, :named_table])
  rescue
    ArgumentError -> :ok
  end

  defp lookup(jwks_uri) do
    case :ets.lookup(@table, jwks_uri) do
      [{^jwks_uri, keys, inserted_at, max_age}] ->
        elapsed = System.monotonic_time(:second) - inserted_at

        {:ok, %{keys: keys, max_age: max_age, elapsed: elapsed}}

      [] ->
        :miss
    end
  end

  defp ensure_valid(%{max_age: max_age, elapsed: elapsed}) when elapsed < max_age, do: :ok
  defp ensure_valid(_), do: :miss
end
