defmodule Ltix.Plugins.ConfiguredPluginsTest do
  # Changes the `:plugins` configuration, so it can't run with other tests.
  use ExUnit.Case, async: false

  alias Ltix.Test.StorageAdapter

  @launch_url "https://tool.example.com/launch"
  @tool_platform "https://purl.imsglobal.org/spec/lti/claim/tool_platform"
  @note "https://vendor.example.com/note"

  setup do
    previous = Application.fetch_env(:ltix, :plugins)
    Application.put_env(:ltix, :plugins, [TestPlugins.Configured])

    on_exit(fn ->
      case previous do
        {:ok, plugins} -> Application.put_env(:ltix, :plugins, plugins)
        :error -> Application.delete_env(:ltix, :plugins)
      end
    end)

    platform = Ltix.Test.setup_platform!()
    StorageAdapter.set_pid(start_supervised!({StorageAdapter, platforms: [platform]}))
    %{platform: platform, params: Ltix.Test.login_params(platform)}
  end

  defp login(params, opts \\ []) do
    Ltix.handle_login(params, @launch_url, Keyword.put(opts, :storage_adapter, StorageAdapter))
  end

  test "a configured plugin's step runs and writes to the login", %{params: params} do
    assert {:ok, _result} = login(params)

    assert_received {:login, %Ltix.Login{private: private}}
    assert private.test_plugins_tenant == "configured"
  end

  test "plugins: at the call replaces the configured plugins", %{params: params} do
    trace = {TestPlugins.Modules, add: [{TestPlugins.Trace, label: :enabled}]}
    assert {:ok, _login} = login(params, plugins: [trace])

    assert_received {:trace, :enabled}
    refute_received {:login, _login}
  end

  test "a launch with plugins: parses object claim properties with those plugins only",
       %{platform: platform} do
    tool_platform = %{"guid" => "platform-1", @note => "Room A"}

    assert {:ok, launch} =
             LaunchFlow.launch(platform, [claims: %{@tool_platform => tool_platform}],
               plugins: []
             )

    assert launch.claims.tool_platform.extensions == %{}
    assert launch.claims.tool_platform.unrecognized == %{@note => "Room A"}
  end
end
