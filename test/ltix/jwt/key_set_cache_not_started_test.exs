defmodule Ltix.JWT.KeySet.CacheNotStartedTest do
  # Hides the global ETS cache table, so no other test may run alongside.
  use ExUnit.Case, async: false

  alias Ltix.Errors.Unknown.KeySetCacheNotStarted
  alias Ltix.JWT.KeySet.CachexCache
  alias Ltix.Test.StorageAdapter

  @launch_url "https://tool.example.com/launch"

  setup do
    platform = Ltix.Test.setup_platform!()
    {:ok, pid} = StorageAdapter.start_link(platforms: [platform])
    StorageAdapter.set_pid(pid)

    {:ok, login} =
      Ltix.handle_login(Ltix.Test.login_params(platform), @launch_url,
        storage_adapter: StorageAdapter
      )

    params =
      Ltix.Test.launch_params(platform,
        nonce: Ltix.Test.extract_nonce(login.redirect_uri),
        state: login.state
      )

    %{params: params, state: login.state}
  end

  test "a launch raises when the ETS cache is not started", %{params: params, state: state} do
    :ets.rename(:ltix_jwks_cache, :ltix_jwks_cache_hidden)
    on_exit(fn -> :ets.rename(:ltix_jwks_cache_hidden, :ltix_jwks_cache) end)

    error =
      assert_raise KeySetCacheNotStarted,
                   "Key set cache Ltix.JWT.KeySet.ETSCache is not started. " <>
                     "Add Ltix.JWT.KeySet.ETSCache to your application's supervision tree.",
                   fn -> callback(params, state, []) end

    assert Ltix.Errors.status_code(error) == 500
  end

  test "a launch raises when the Cachex cache is not started", %{params: params, state: state} do
    assert_raise KeySetCacheNotStarted,
                 "Key set cache Ltix.JWT.KeySet.CachexCache is not started. " <>
                   "Add {Cachex, name: :ltix_jwks} to your application's supervision tree.",
                 fn -> callback(params, state, jwks_cache: CachexCache) end
  end

  defp callback(params, state, opts) do
    Ltix.handle_callback(
      params,
      state,
      [storage_adapter: StorageAdapter, req_options: [plug: {Req.Test, Ltix.JWT.KeySet}]] ++
        opts
    )
  end
end
