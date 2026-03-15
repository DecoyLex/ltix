defmodule Ltix.JWT.KeySet.CachexCacheTest do
  @moduledoc """
  Tests that CachexCache correctly implements the Cache behaviour contract:
  - get/1 maps Cachex {:ok, nil} → :miss and {:ok, value} → {:ok, value}
  - put/3 returns :ok and makes data retrievable
  - delete/1 returns :ok and invalidates cached data
  - cache_name/0 reads from application config
  """
  use ExUnit.Case, async: false

  alias Ltix.JWT.KeySet.CachexCache

  @test_cache :ltix_cachex_cache_test
  @jwks_uri "https://platform.example.com/.well-known/jwks.json"

  # Start the cache once for the whole module — not per-test — so it isn't
  # linked to (and killed with) individual test processes.
  setup_all do
    pid =
      case Cachex.start(@test_cache) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    on_exit(fn -> Process.exit(pid, :normal) end)

    :ok
  end

  setup do
    Cachex.clear!(@test_cache)
    previous = Application.get_env(:ltix, :cachex_cache_name)
    Application.put_env(:ltix, :cachex_cache_name, @test_cache)

    on_exit(fn ->
      if previous do
        Application.put_env(:ltix, :cachex_cache_name, previous)
      else
        Application.delete_env(:ltix, :cachex_cache_name)
      end
    end)

    :ok
  end

  describe "get/1" do
    test "maps Cachex {:ok, nil} to :miss for uncached key" do
      assert :miss = CachexCache.get(@jwks_uri)
    end

    test "maps Cachex {:ok, value} to {:ok, value} for cached key" do
      keys = %{"kid-1" => :some_jwk}
      CachexCache.put(@jwks_uri, keys, 300)

      assert {:ok, ^keys} = CachexCache.get(@jwks_uri)
    end
  end

  describe "put/3" do
    test "returns :ok and makes data round-trippable via get/1" do
      keys = %{"kid-1" => :some_jwk}
      assert :ok = CachexCache.put(@jwks_uri, keys, 300)
      assert {:ok, ^keys} = CachexCache.get(@jwks_uri)
    end
  end

  describe "delete/1" do
    test "returns :ok and causes subsequent get/1 to return :miss" do
      keys = %{"kid-1" => :some_jwk}
      CachexCache.put(@jwks_uri, keys, 300)
      assert {:ok, _} = CachexCache.get(@jwks_uri)

      assert :ok = CachexCache.delete(@jwks_uri)
      assert :miss = CachexCache.get(@jwks_uri)
    end
  end
end
