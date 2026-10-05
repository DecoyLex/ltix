defmodule Ltix.JWT.KeySet.Cache do
  @moduledoc """
  Behaviour for caching JWKS (JSON Web Key Sets) fetched from platform endpoints.

  The default implementation is `Ltix.JWT.KeySet.ETSCache`, which uses an ETS
  table. A `Ltix.JWT.KeySet.CachexCache` adapter is also provided for projects
  that already use Cachex.

  ## Custom Implementations

  Implement this behaviour to use your own cache backend. Raise
  `Ltix.Errors.Unknown.KeySetCacheFailed` when the backend fails.

      defmodule MyApp.JWKSCache do
        use Ltix.JWT.KeySet.Cache

        @impl true
        def get(jwks_uri), do: ...

        @impl true
        def put(jwks_uri, entry, max_age), do: ...
      end

  Then configure it:

      config :ltix, :jwks_cache, MyApp.JWKSCache

  Or pass per-call:

      Ltix.JWT.KeySet.get_key(registration, kid, jwks_cache: MyApp.JWKSCache)
  """

  @doc """
  Look up the cached entry for a JWKS URI.

  Returns `{:ok, entry}` with the `entry` given to `c:put/3`, or `:miss` if
  the entry is absent or expired.
  """
  @callback get(jwks_uri :: String.t()) :: {:ok, entry :: term()} | :miss

  @doc """
  Store an entry for a JWKS URI with a TTL, replacing any existing entry.

  The `entry` holds the platform's keys. Store it as given. `max_age` is the
  number of seconds the entry should be considered fresh, derived from the
  `cache-control: max-age` HTTP header.
  """
  @callback put(jwks_uri :: String.t(), entry :: term(), max_age :: pos_integer()) :: :ok

  defmacro __using__(_opts) do
    quote do
      @behaviour Ltix.JWT.KeySet.Cache
    end
  end
end
