defmodule Ltix.JWT.KeySet do
  @moduledoc """
  Platform public keys for verifying ID token signatures.

  Platforms publish their public keys at a key set URL. Ltix gets the keys
  it needs to verify a launch from a key set cache that your application
  starts.

  ## Setup

  Add a key set cache to your application's supervision tree.

      # lib/my_app/application.ex
      children = [
        Ltix.JWT.KeySet
      ]

  To run more than one, or to choose the name, pass `:name` and set the
  name in your config.

      children = [
        {Ltix.JWT.KeySet, name: MyApp.LtiKeys}
      ]

      config :ltix, key_set: MyApp.LtiKeys

  You can also choose the key set cache for one call.

      Ltix.handle_callback(params, state, key_set: MyApp.LtiKeys)

  ## Keys

  A platform's keys are kept for the number of seconds in its
  `cache-control: max-age`, or 5 minutes without one. A key the platform has
  rotated in is available on the first launch signed with it.

  ## Fetch limit

  Each key set URL is fetched at most once every 30 seconds, however many
  launches arrive and whatever key IDs they have. Change the 30 seconds with
  the `:refetch_interval` option of `start_link/1`. After a failed fetch,
  launches for that platform return its error until the interval has passed.

  A fetch retries a temporary failure up to three times. Pass `retry: false`
  in `:req_options` to disable retries.
  """

  use GenServer

  alias Ltix.AppConfig
  alias Ltix.Errors.Invalid.MalformedResponse
  alias Ltix.Errors.Security.KidNotFound
  alias Ltix.Errors.Security.LocalNetworkAccessDenied
  alias Ltix.Errors.Unknown.KeySetNotStarted
  alias Ltix.HTTP
  alias Ltix.Options
  alias Ltix.Registration

  @default_max_age 300

  @start_schema Zoi.keyword(
                  [
                    name:
                      Zoi.atom(description: "Name of the key set cache.")
                      |> Zoi.default(__MODULE__),
                    refetch_interval:
                      Zoi.integer(description: "Seconds between fetches of one key set URL.")
                      |> Zoi.non_negative()
                      |> Zoi.default(30)
                  ],
                  unrecognized_keys: :error
                )

  @options_schema Zoi.keyword(
                    [
                      key_set:
                        Zoi.atom(
                          description:
                            "The name of the `Ltix.JWT.KeySet` cache to get the platform's keys from. Defaults to `Ltix.JWT.KeySet`."
                        ),
                      req_options:
                        Zoi.keyword(Zoi.any(),
                          description:
                            "Options for `Req.request/2` on the key set fetch. They're merged over the configured ones."
                        ),
                      local_network_access: HTTP.local_network_access_option()
                    ],
                    unrecognized_keys: :error
                  )

  @doc """
  Start a key set cache.

  ## Options

  #{Zoi.describe(@start_schema)}
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    opts = Options.parse!(opts, @start_schema)
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    Supervisor.child_spec(super(opts), id: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Get the platform's public key with the key ID `kid`.

  Returns `Ltix.Errors.Security.KidNotFound` when the platform has no key
  with that ID.

  ## Options

  When you [configure](`m:Ltix#module-configuration`) an option, the configured
  value is its default.

  #{Zoi.describe(@options_schema)}
  """
  # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
  @spec get_key(Registration.t(), String.t(), keyword()) ::
          {:ok, Ltix.JWK.t()} | {:error, Exception.t()}
  def get_key(%Registration{} = registration, kid, opts \\ []) do
    opts = Options.parse!(opts, @options_schema)
    key_set = Keyword.get_lazy(opts, :key_set, &AppConfig.key_set/0)
    jwks_uri = registration.jwks_uri

    case find_key(key_set, jwks_uri, kid, opts) do
      {:ok, status, jwk} ->
        :telemetry.execute([:ltix, :jwks, status], %{}, %{jwks_uri: jwks_uri, kid: kid})
        {:ok, jwk}

      :not_found ->
        :telemetry.execute([:ltix, :jwks, :cache_miss], %{}, %{jwks_uri: jwks_uri, kid: kid})
        {:error, KidNotFound.exception(kid: kid)}

      {:error, _error} = error ->
        error
    end
  end

  # Removes the configured key set cache's keys for a key set URL, so the
  # next lookup fetches them again.
  @doc false
  @spec expire_keys(String.t()) :: :ok
  def expire_keys(jwks_uri) do
    key_set = AppConfig.key_set()
    if :ets.whereis(key_set) == :undefined, do: raise(KeySetNotStarted, key_set: key_set)
    GenServer.call(key_set, {:expire, jwks_uri})
  end

  # [Sec §6.4](https://www.imsglobal.org/spec/security/v1p0/#issuer-public-key-rotation)
  defp find_key(key_set, jwks_uri, kid, opts) do
    with :fetch <- cached_key(key_set, jwks_uri, kid),
         :fetch <- GenServer.call(key_set, {:claim, jwks_uri}, :infinity),
         {:ok, %{^kid => jwk}} <- fetch_claimed(key_set, jwks_uri, opts) do
      {:ok, :cache_miss, jwk}
    else
      # Another caller's fetch finished, so the cached keys are read again.
      :fetched -> find_key(key_set, jwks_uri, kid, opts)
      {:ok, _keys} -> :not_found
      result -> result
    end
  end

  # Returns `:fetch` when the key set is due for a fetch.
  defp cached_key(key_set, jwks_uri, kid) do
    now = System.monotonic_time(:second)

    case cached(key_set, jwks_uri) do
      [{_uri, %{keys: %{^kid => jwk}, expires_at: expires_at}}] when now < expires_at ->
        {:ok, :cache_hit, jwk}

      [{_uri, %{refetch_at: refetch_at, error: error}}] when now < refetch_at ->
        if error, do: {:error, error}, else: :not_found

      _due ->
        :fetch
    end
  end

  defp cached(key_set, jwks_uri) do
    :ets.lookup(key_set, jwks_uri)
  rescue
    ArgumentError ->
      reraise KeySetNotStarted.exception(key_set: key_set), __STACKTRACE__
  end

  # The fetch's outcome is reported to the key set cache even when it raises,
  # because callers waiting for it would otherwise wait forever.
  defp fetch_claimed(key_set, jwks_uri, opts) do
    result =
      try do
        fetch_jwks(jwks_uri, opts)
      catch
        kind, reason ->
          GenServer.call(key_set, {:finish, jwks_uri, :raised}, :infinity)
          :erlang.raise(kind, reason, __STACKTRACE__)
      end

    GenServer.call(key_set, {:finish, jwks_uri, result}, :infinity)
    with {:ok, keys, _max_age} <- result, do: {:ok, keys}
  end

  @impl GenServer
  def init(opts) do
    table = Keyword.fetch!(opts, :name)
    :ets.new(table, [:set, :protected, :named_table, read_concurrency: true])
    {:ok, %{table: table, interval: Keyword.fetch!(opts, :refetch_interval), fetches: %{}}}
  end

  # One caller fetches a key set URL at a time. The others are replied to
  # when that fetch finishes.
  @impl GenServer
  def handle_call({:claim, jwks_uri}, {pid, _tag} = from, state) do
    case state.fetches do
      %{^jwks_uri => fetch} ->
        fetch = %{fetch | waiting: [from | fetch.waiting]}
        {:noreply, put_in(state.fetches[jwks_uri], fetch)}

      _fetches ->
        # A fetch may have finished after the caller read the table.
        if fetch_due?(state.table, jwks_uri),
          do: {:reply, :fetch, put_in(state.fetches[jwks_uri], fetch_by(pid, []))},
          else: {:reply, :fetched, state}
    end
  end

  def handle_call({:finish, jwks_uri, result}, {pid, _tag}, state) do
    case state.fetches do
      %{^jwks_uri => %{fetcher: ^pid} = fetch} ->
        Process.demonitor(fetch.monitor)
        {:reply, :ok, finish(state, jwks_uri, fetch, result)}

      _fetches ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:expire, jwks_uri}, _from, state) do
    :ets.delete(state.table, jwks_uri)
    {:reply, :ok, state}
  end

  # The fetching caller died.
  @impl GenServer
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    case Enum.find(state.fetches, fn {_uri, fetch} -> fetch.monitor == monitor end) do
      {jwks_uri, fetch} -> {:noreply, hand_over(state, jwks_uri, fetch)}
      nil -> {:noreply, state}
    end
  end

  # A refused connection or a raised error is not a result from the
  # platform. It can depend on the caller's options, so the next caller
  # fetches.
  defp finish(state, jwks_uri, fetch, result)
       when result == :raised or
              (is_tuple(result) and is_struct(elem(result, 1), LocalNetworkAccessDenied)) do
    hand_over(state, jwks_uri, fetch)
  end

  defp finish(state, jwks_uri, fetch, result) do
    :ets.insert(state.table, {jwks_uri, entry(state, jwks_uri, result)})
    Enum.each(fetch.waiting, &GenServer.reply(&1, :fetched))
    %{state | fetches: Map.delete(state.fetches, jwks_uri)}
  end

  defp hand_over(state, jwks_uri, %{waiting: [{pid, _tag} = from | waiting]}) do
    GenServer.reply(from, :fetch)
    put_in(state.fetches[jwks_uri], fetch_by(pid, waiting))
  end

  defp hand_over(state, jwks_uri, %{waiting: []}) do
    %{state | fetches: Map.delete(state.fetches, jwks_uri)}
  end

  defp fetch_by(pid, waiting) do
    %{fetcher: pid, monitor: Process.monitor(pid), waiting: waiting}
  end

  defp fetch_due?(table, jwks_uri) do
    case :ets.lookup(table, jwks_uri) do
      [{_uri, %{refetch_at: refetch_at}}] -> System.monotonic_time(:second) >= refetch_at
      [] -> true
    end
  end

  defp entry(state, _jwks_uri, {:ok, keys, max_age}) do
    now = System.monotonic_time(:second)

    %{
      keys: keys,
      expires_at: now + max(max_age, state.interval),
      refetch_at: now + state.interval,
      error: nil
    }
  end

  # Keys cached before a failed fetch stay in use until they expire.
  defp entry(state, jwks_uri, {:error, error}) do
    now = System.monotonic_time(:second)

    cached =
      case :ets.lookup(state.table, jwks_uri) do
        [{_uri, %{expires_at: expires_at} = cached}] when now < expires_at -> cached
        _expired -> %{keys: %{}, expires_at: now}
      end

    Map.merge(cached, %{refetch_at: now + state.interval, error: error})
  end

  # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
  defp fetch_jwks(jwks_uri, opts) do
    req_opts = Keyword.put(req_options(opts), :url, jwks_uri)

    result =
      req_opts
      |> Keyword.merge(
        method: :get,
        decode_body: false,
        local_network_access: Keyword.get(opts, :local_network_access)
      )
      |> HTTP.request()

    case result do
      {:ok, %Req.Response{status: 200, body: body, headers: headers}} ->
        with {:ok, jwks} <- decode_jwks(body) do
          {:ok, parse_jwks(jwks), parse_max_age(headers)}
        end

      {:ok, %Req.Response{} = response} ->
        {:error, HTTP.status_error(response, jwks_uri)}

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
           reason: "key set is not a JSON object"
         )}
    end
  end

  # Keys that aren't valid JWKs with a key ID are left out, so one malformed
  # key doesn't stop the platform's other keys from being used.
  defp parse_jwks(%{"keys" => keys}) when is_list(keys) do
    for %{"kid" => kid} = key_map when is_binary(kid) <- keys,
        {:ok, jwk} <- [Ltix.JWK.new(public_jwk: key_map)],
        into: %{},
        do: {kid, jwk}
  end

  defp parse_jwks(_jwks), do: %{}

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
end
