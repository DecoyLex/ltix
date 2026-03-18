defmodule Ltix.JWT.KeySet.EtsCache do
  @moduledoc """
  Default ETS-backed cache for JWKS key sets.

  Stores keys in a named ETS table (`:ltix_jwks_cache`) owned by a
  GenServer process. Entries expire based on the `max_age` value from
  the platform's `cache-control` header.

  ## Setup

  Add this module to your application's supervision tree:

      # lib/my_app/application.ex
      children = [
        Ltix.JWT.KeySet.EtsCache
      ]

  This is the default cache backend. If you prefer Cachex, see
  `Ltix.JWT.KeySet.CachexCache`.
  """
  use GenServer

  use Ltix.JWT.KeySet.Cache

  @table :ltix_jwks_cache

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl GenServer
  def init(:ok) do
    :ets.new(@table, [:set, :public, :named_table])

    {:ok, %{}}
  end

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
    # Raise if the table doesn't exist, which should only happen if the GenServer isn't running
    if :ets.whereis(@table) == :undefined do
      raise Ltix.Errors.Unknown,
            "JWKS cache table not found. Ensure #{inspect(__MODULE__)} GenServer is running."
    end
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
