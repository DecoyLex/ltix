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

    @impl true
    def get(jwks_uri) do
      case Cachex.get(cache_name(), jwks_uri) do
        {:ok, nil} -> :miss
        {:ok, keys} -> {:ok, keys}
      end
    end

    @impl true
    def put(jwks_uri, keys, max_age) do
      Cachex.put(cache_name(), jwks_uri, keys, expire: :timer.seconds(max_age))
      :ok
    end

    @impl true
    def delete(jwks_uri) do
      Cachex.del(cache_name(), jwks_uri)
      :ok
    end

    defp cache_name do
      Application.get_env(:ltix, :cachex_cache_name, :ltix_jwks)
    end
  end
end
