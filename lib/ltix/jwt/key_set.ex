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

      {:ok, jwk} = Ltix.JWT.KeySet.get_key(registration, "some-kid")

  ## Caching

  By default, keys are cached in an ETS table (`Ltix.JWT.KeySet.ETSCache`).
  The cache respects the platform's `cache-control: max-age` header.

  You can swap the cache backend by implementing `Ltix.JWT.KeySet.Cache`:

      config :ltix, :jwks_cache, MyApp.JWKSCache

  Or per-call, including through `Ltix.handle_callback/3`:

      Ltix.JWT.KeySet.get_key(registration, kid, jwks_cache: MyApp.JWKSCache)

  A `Ltix.JWT.KeySet.CachexCache` adapter is provided for projects that
  already use Cachex.

  ## Key Rotation

  When a `kid` is not found in the cached keys, the module re-fetches the key
  set to pick up keys the platform has rotated in. It re-fetches at most once
  every 30 seconds for each key set URL, so unknown key IDs can't make it
  fetch on every launch. The cached keys stay in use until a re-fetch
  succeeds.
  """

  alias Ltix.AppConfig
  alias Ltix.Errors.Invalid.MalformedResponse
  alias Ltix.Errors.Security.KidNotFound
  alias Ltix.HTTP
  alias Ltix.JWT.KeySet.ETSCache
  alias Ltix.Options
  alias Ltix.Registration

  @default_max_age 300

  # [Sec §6.4](https://www.imsglobal.org/spec/security/v1p0/#issuer-public-key-rotation)
  @refetch_interval 30

  @options_schema Zoi.keyword([jwks_cache: Zoi.module(), req_options: Zoi.keyword(Zoi.any())],
                    unrecognized_keys: :error
                  )

  @doc """
  Fetch the platform's public key matching `kid`.

  Checks the cache first. On a cache miss, fetches from the platform's JWKS
  endpoint. If the `kid` is not found in cached keys fetched at least 30
  seconds ago, re-fetches to support key rotation.

  ## Options

    * `:jwks_cache` — cache module implementing `Ltix.JWT.KeySet.Cache`
      (default: the application configuration, then
      `Ltix.JWT.KeySet.ETSCache`)
    * `:req_options` — extra options passed to `Req.get/2`
  """
  # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
  @spec get_key(Registration.t(), String.t(), keyword()) ::
          {:ok, JOSE.JWK.t()} | {:error, Exception.t()}
  def get_key(%Registration{} = registration, kid, opts \\ []) do
    opts = Options.parse!(opts, @options_schema)
    cache = resolve_cache(opts)
    jwks_uri = registration.jwks_uri

    case find_key(jwks_uri, kid, cache, opts) do
      {:ok, status, jwk} ->
        :telemetry.execute([:ltix, :jwks, status], %{}, %{jwks_uri: jwks_uri, kid: kid})
        {:ok, jwk}

      :not_found ->
        :telemetry.execute([:ltix, :jwks, :cache_miss], %{}, %{jwks_uri: jwks_uri, kid: kid})
        {:error, KidNotFound.exception(kid: kid, spec_ref: "Sec §6.3")}

      {:error, _error} = error ->
        error
    end
  end

  # [Sec §6.4](https://www.imsglobal.org/spec/security/v1p0/#issuer-public-key-rotation)
  defp find_key(jwks_uri, kid, cache, opts) do
    case cache.get(jwks_uri) do
      {:ok, %{keys: %{^kid => jwk}}} ->
        {:ok, :cache_hit, jwk}

      {:ok, %{fetched_at: fetched_at}} ->
        if DateTime.diff(DateTime.utc_now(), fetched_at) >= @refetch_interval,
          do: fetch_key(jwks_uri, kid, cache, opts),
          else: :not_found

      :miss ->
        fetch_key(jwks_uri, kid, cache, opts)
    end
  end

  defp fetch_key(jwks_uri, kid, cache, opts) do
    with {:ok, keys, max_age} <- fetch_jwks(jwks_uri, opts) do
      if max_age > 0,
        do: cache.put(jwks_uri, %{keys: keys, fetched_at: DateTime.utc_now()}, max_age)

      case Map.fetch(keys, kid) do
        {:ok, jwk} -> {:ok, :cache_miss, jwk}
        :error -> :not_found
      end
    end
  end

  # Replaces the configured cache's keys for a key set URL with an empty set
  # that is due for a re-fetch, so the next lookup fetches the key set again.
  @doc false
  @spec expire_keys(String.t()) :: :ok
  def expire_keys(jwks_uri) do
    fetched_at = DateTime.add(DateTime.utc_now(), -@refetch_interval)
    resolve_cache([]).put(jwks_uri, %{keys: %{}, fetched_at: fetched_at}, @default_max_age)
  end

  defp fetch_jwks(jwks_uri, opts) do
    req_opts = Keyword.put(req_options(opts), :url, jwks_uri)

    result =
      req_opts
      |> Keyword.merge(method: :get, decode_body: false)
      |> HTTP.request()

    case result do
      {:ok, %Req.Response{status: 200, body: body, headers: headers}} ->
        with {:ok, jwks} <- decode_jwks(body) do
          {:ok, parse_jwks(jwks), parse_max_age(headers)}
        end

      {:ok, %Req.Response{} = response} ->
        {:error, HTTP.status_error(response, jwks_uri, "Sec §6.3")}

      {:error, _error} = error ->
        error
    end
  end

  # Platforms serve key sets with various content types, so the body is
  # decoded whatever its content type.
  defp decode_jwks(body) do
    case AppConfig.json_library!().decode(body) do
      {:ok, jwks} when is_map(jwks) ->
        {:ok, jwks}

      _not_an_object ->
        {:error,
         MalformedResponse.exception(
           service: __MODULE__,
           reason: "key set is not a JSON object",
           spec_ref: "Sec §6.3"
         )}
    end
  end

  # Keys that aren't valid JWKs with a key ID are left out, so one malformed
  # key doesn't stop the platform's other keys from being used.
  defp parse_jwks(%{"keys" => keys}) when is_list(keys) do
    for %{"kid" => kid} = key_map when is_binary(kid) <- keys,
        {:ok, jwk} <- [parse_key(key_map)],
        into: %{},
        do: {kid, jwk}
  end

  defp parse_jwks(_jwks), do: %{}

  defp parse_key(key_map) do
    {:ok, JOSE.JWK.from_map(key_map)}
  rescue
    _error -> :error
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
    HTTP.req_options(Keyword.get(opts, :req_options, []), __MODULE__)
  end

  defp resolve_cache(opts) do
    Keyword.get_lazy(opts, :jwks_cache, fn ->
      Application.get_env(:ltix, :jwks_cache, ETSCache)
    end)
  end
end
