if Code.ensure_loaded?(Cachex) do
  defmodule Ltix.JWT.KeySet.CachexCache do
    @moduledoc """
    Cachex-backed cache for JWKS key sets.

    Requires a Cachex cache to be started in your supervision tree:

        # In your application.ex
        children = [
          {Cachex, name: :ltix_jwks}
        ]

    The cache name defaults to `:ltix_jwks` and can be configured:

        config :ltix, :cachex_cache_name, :my_jwks_cache

    Then set this module as the JWKS cache:

        config :ltix, :jwks_cache, Ltix.JWT.KeySet.CachexCache
    """

    @behaviour Ltix.JWT.KeySet.Cache

    alias Ltix.Errors.Unknown.KeySetCacheFailed
    alias Ltix.Errors.Unknown.KeySetCacheNotStarted

    @impl Ltix.JWT.KeySet.Cache
    def get(jwks_uri) do
      case succeeded!(:get, Cachex.get(cache_name(), jwks_uri)) do
        nil -> :miss
        keys -> {:ok, keys}
      end
    end

    @impl Ltix.JWT.KeySet.Cache
    def put(jwks_uri, keys, max_age) do
      succeeded!(:put, Cachex.put(cache_name(), jwks_uri, keys, expire: :timer.seconds(max_age)))
      :ok
    end

    @impl Ltix.JWT.KeySet.Cache
    def delete(jwks_uri) do
      succeeded!(:delete, Cachex.del(cache_name(), jwks_uri))
      :ok
    end

    defp succeeded!(_operation, {:ok, value}), do: value

    defp succeeded!(_operation, {:error, :no_cache}) do
      raise KeySetCacheNotStarted, cache: __MODULE__, child_spec: {Cachex, name: cache_name()}
    end

    defp succeeded!(operation, {:error, reason}) do
      raise KeySetCacheFailed, cache: __MODULE__, operation: operation, reason: reason
    end

    defp cache_name do
      Application.get_env(:ltix, :cachex_cache_name, :ltix_jwks)
    end
  end
end
