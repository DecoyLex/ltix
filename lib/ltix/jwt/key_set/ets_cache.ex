defmodule Ltix.JWT.KeySet.EtsCache do
  @moduledoc """
  Default ETS-backed cache for JWKS key sets.

  Uses a named ETS table (`:ltix_jwks_cache`) created lazily on first access.
  Entries expire based on the `max_age` value from the platform's
  `cache-control` header.
  """

  @behaviour Ltix.JWT.KeySet.Cache

  @table :ltix_jwks_cache

  @impl true
  def get(jwks_uri) do
    ensure_table()

    case :ets.lookup(@table, jwks_uri) do
      [{^jwks_uri, keys, inserted_at, max_age}] ->
        elapsed = System.monotonic_time(:second) - inserted_at

        if elapsed < max_age do
          {:ok, keys}
        else
          :miss
        end

      [] ->
        :miss
    end
  end

  @impl true
  def put(jwks_uri, keys, max_age) do
    ensure_table()
    :ets.insert(@table, {jwks_uri, keys, System.monotonic_time(:second), max_age})
    :ok
  end

  @impl true
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
end
