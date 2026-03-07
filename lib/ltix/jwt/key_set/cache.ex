defmodule Ltix.JWT.KeySet.Cache do
  @moduledoc """
  Behaviour for caching JWKS (JSON Web Key Sets) fetched from platform endpoints.

  The default implementation is `Ltix.JWT.KeySet.EtsCache`, which uses an ETS
  table. A `Ltix.JWT.KeySet.CachexCache` adapter is also provided for projects
  that already use Cachex.

  ## Custom Implementations

  Implement this behaviour to use your own cache backend:

      defmodule MyApp.JWKSCache do
        use Ltix.JWT.KeySet.Cache

        @impl true
        def get(jwks_uri), do: ...

        @impl true
        def put(jwks_uri, keys, max_age), do: ...

        @impl true
        def delete(jwks_uri), do: ...
      end

  Then configure it:

      config :ltix, :jwks_cache, MyApp.JWKSCache

  Or pass per-call:

      Ltix.JWT.KeySet.get_key(registration, kid, cache: MyApp.JWKSCache)
  """

  @doc """
  Look up cached keys for a JWKS URI.

  Returns `{:ok, keys}` where `keys` is `%{kid => JOSE.JWK.t()}`,
  or `:miss` if the entry is absent or expired.
  """
  @callback get(jwks_uri :: String.t()) :: {:ok, keys :: map()} | :miss

  @doc """
  Store keys for a JWKS URI with a TTL.

  `max_age` is the number of seconds the entry should be considered fresh,
  derived from the `cache-control: max-age` HTTP header. A value of `0`
  means no caching.
  """
  @callback put(jwks_uri :: String.t(), keys :: map(), max_age :: non_neg_integer()) :: :ok

  @doc """
  Remove a cached entry for a JWKS URI.

  Called before re-fetching on a key ID miss (key rotation).
  """
  @callback delete(jwks_uri :: String.t()) :: :ok

  defmacro __using__(_opts) do
    quote do
      @behaviour Ltix.JWT.KeySet.Cache
    end
  end
end
