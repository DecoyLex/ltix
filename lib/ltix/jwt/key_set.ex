defmodule Ltix.JWT.KeySet do
  @moduledoc """
  Fetches and caches platform public keys for JWT signature verification.

  Platforms publish their public keys at a JWKS (JSON Web Key Set) endpoint.
  This module fetches those keys, caches them, and looks up the correct key
  by `kid` (Key ID) when verifying an ID Token signature.

  You won't normally call this module directly — `Ltix.JWT.Token.verify/3`
  calls it internally. It is public so that cache configuration and custom
  cache backends can integrate with it.

  ## Examples

      {:ok, registration} = Ltix.Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-123",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri: "https://platform.example.com/.well-known/jwks.json"
      })

      #iex> {:ok, _jwk} = Ltix.JWT.KeySet.get_key(registration, "some-kid")

  ## Caching

  By default, keys are cached in an ETS table (`Ltix.JWT.KeySet.EtsCache`).
  The cache respects the platform's `cache-control: max-age` header. When a
  `kid` is not found in cached keys, the module re-fetches once to handle
  key rotation.

  You can swap the cache backend by implementing `Ltix.JWT.KeySet.Cache`:

      config :ltix, :jwks_cache, MyApp.JWKSCache

  Or per-call:

      Ltix.JWT.KeySet.get_key(registration, kid, cache: MyApp.JWKSCache)

  A `Ltix.JWT.KeySet.CachexCache` adapter is provided for projects that
  already use Cachex.

  ## Key Rotation

  When a `kid` is not found in the cached key set, the module deletes the
  cache entry and re-fetches from the platform. This handles the case where
  the platform has rotated its keys. To prevent abuse, only one re-fetch is
  attempted per `get_key/3` call.
  """

  alias Ltix.Errors.Security.KidNotFound
  alias Ltix.Errors.Unknown
  alias Ltix.JWT.KeySet.EtsCache
  alias Ltix.Registration

  @default_max_age 300

  @doc """
  Fetch the platform's public key matching `kid`.

  Checks the cache first. On a cache miss, fetches from the platform's JWKS
  endpoint. If the `kid` is not found in cached keys, re-fetches once to
  support key rotation.

  ## Options

    * `:cache` — cache module implementing `Ltix.JWT.KeySet.Cache`
      (default: `Ltix.JWT.KeySet.EtsCache`)
    * `:req_options` — extra options passed to `Req.get/2`
  """
  # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
  @spec get_key(Registration.t(), String.t(), keyword()) ::
          {:ok, JOSE.JWK.t()} | {:error, Exception.t()}
  def get_key(%Registration{} = registration, kid, opts \\ []) do
    cache = resolve_cache(opts)
    do_get_key(registration, kid, cache, opts, _refetched? = false)
  end

  defp do_get_key(registration, kid, cache, opts, refetched?) do
    with {:ok, {status, keys}} <- get_cached_or_fetch(registration.jwks_uri, cache, opts),
         {:ok, jwk} <- find_key(keys, kid) do
      :telemetry.execute([:ltix, :jwks, status], %{}, %{
        jwks_uri: registration.jwks_uri,
        kid: kid
      })

      {:ok, jwk}
    else
      :not_found when not refetched? ->
        # [Sec §6.4] Key rotation: re-fetch once on kid miss
        cache.delete(registration.jwks_uri)
        do_get_key(registration, kid, cache, opts, _refetched? = true)

      :not_found ->
        :telemetry.execute([:ltix, :jwks, :cache_miss], %{}, %{
          jwks_uri: registration.jwks_uri,
          kid: kid
        })

        {:error,
         KidNotFound.exception(
           kid: kid,
           spec_ref: "Sec §6.3"
         )}

      {:error, reason} ->
        {:error, Unknown.Unknown.exception(error: reason)}
    end
  end

  defp get_cached_or_fetch(jwks_uri, cache, opts) do
    case cache.get(jwks_uri) do
      {:ok, keys} ->
        {:ok, {:cache_hit, keys}}

      :miss ->
        fetch_and_cache(jwks_uri, cache, opts)
    end
  end

  defp fetch_and_cache(jwks_uri, cache, opts) do
    case fetch_jwks(jwks_uri, opts) do
      {:ok, keys, max_age} ->
        if max_age > 0, do: cache.put(jwks_uri, keys, max_age)
        {:ok, {:cache_miss, keys}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_jwks(jwks_uri, opts) do
    req_opts = Keyword.put(req_options(opts), :url, jwks_uri)

    case Req.get(req_opts) do
      {:ok, %Req.Response{status: 200, body: body, headers: headers}} ->
        max_age = parse_max_age(headers)
        keys = parse_jwks(body)
        {:ok, keys, max_age}

      {:ok, %Req.Response{status: status}} ->
        {:error, "JWKS fetch returned HTTP #{status}"}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp parse_jwks(%{"keys" => keys}) when is_list(keys) do
    Map.new(keys, fn key_map ->
      jwk = JOSE.JWK.from_map(key_map)
      kid = Map.get(key_map, "kid")
      {kid, jwk}
    end)
  end

  defp parse_jwks(_body), do: %{}

  defp find_key(keys, kid) do
    case Map.fetch(keys, kid) do
      {:ok, jwk} -> {:ok, jwk}
      :error -> :not_found
    end
  end

  defp parse_max_age(headers) do
    headers
    |> Map.get("cache-control", [])
    |> Enum.find_value(@default_max_age, fn value ->
      case Regex.run(~r/max-age=(\d+)/, value) do
        [_, seconds] -> String.to_integer(seconds)
        nil -> nil
      end
    end)
  end

  defp req_options(opts) do
    default = Application.get_env(:ltix, :req_options, [])
    Keyword.merge(default, Keyword.get(opts, :req_options, []))
  end

  defp resolve_cache(opts) do
    Keyword.get_lazy(opts, :cache, fn ->
      Application.get_env(:ltix, :jwks_cache, EtsCache)
    end)
  end
end
