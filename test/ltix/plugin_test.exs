defmodule Ltix.PluginTest do
  use ExUnit.Case, async: true

  import LaunchFlow

  alias Ltix.DeepLinking
  alias Ltix.Errors.Unknown.InvalidPluginSet
  alias Ltix.PluginSet.Conflict
  alias Ltix.Test.StorageAdapter
  alias TestPlugins.Modules
  alias TestPlugins.Poll

  @session "https://vendor.example.com/session"
  @poll "https://vendor.example.com/poll"

  doctest Ltix.Ordered
  doctest Ltix.Plugin
  doctest Ltix.PluginSet
  doctest Ltix.PluginSet.Conflict
  doctest Ltix.Step

  setup do
    platform = Ltix.Test.setup_platform!()
    StorageAdapter.set_pid(start_supervised!({StorageAdapter, platforms: [platform]}))
    %{platform: platform}
  end

  describe "add/2" do
    test "adds a claim, a message type, and a content item type", %{platform: platform} do
      plugins = [{Modules, add: [TestPlugins.Session, TestPlugins.TestRequest, Poll]}]

      assert {:ok, launch} =
               launch(
                 platform,
                 [message_type: "LtiTestRequest", claims: %{@session => %{"id" => "s-1"}}],
                 plugins: plugins
               )

      assert launch.claims.message_type == "LtiTestRequest"
      assert %TestPlugins.Session{id: "s-1"} = launch.claims.session

      assert {:ok, _response} = build_poll_response(platform, plugins)
    end

    test "counts a message type and a content item type that several plugins add once",
         %{platform: platform} do
      plugins =
        for name <- ["First", "Second"],
            do: {Modules, name: name, add: [TestPlugins.TestRequest, Poll]}

      assert {:ok, _launch} =
               launch(platform, [message_type: "LtiTestRequest"], plugins: plugins)

      assert {:ok, _response} = build_poll_response(platform, plugins)
    end

    test "keeps each entry of a module added twice, with its own options", %{platform: platform} do
      plugins = [
        {Modules, add: [{TestPlugins.Trace, label: :first}, {TestPlugins.Trace, label: :second}]}
      ]

      assert {:ok, _login} =
               Ltix.handle_login(
                 Ltix.Test.login_params(platform),
                 "https://tool.example.com/launch",
                 plugins: plugins,
                 storage_adapter: StorageAdapter
               )

      assert_received {:trace, :first}
      assert_received {:trace, :second}
    end

    test "raises for a module that doesn't extend a module or call use Ltix.Provider" do
      assert_raise ArgumentError,
                   "String doesn't extend a module or call `use Ltix.Provider`. Add `use` with the module it extends, such as `use Ltix.Login`, or `use Ltix.Provider` to it.",
                   fn -> Ltix.PluginSet.resolve([{Modules, add: [String]}]) end
    end

    test "takes a module that is only a provider with empty options" do
      assert {:ok, plugins} =
               Ltix.PluginSet.resolve([
                 {Modules, add: [{TestPlugins.Gadget, []}, TestPlugins.GadgetColor]}
               ])

      assert Enum.map(Ltix.PluginSet.entries(plugins, TestPlugins.Gadget), & &1.module) == [
               TestPlugins.GadgetColor
             ]
    end

    test "raises for options on a module that is only a provider" do
      assert_raise ArgumentError,
                   "TestPlugins.Gadget extends no module, so it takes no options. Add it as TestPlugins.Gadget.",
                   fn ->
                     Ltix.PluginSet.resolve([
                       {Modules, add: [{TestPlugins.Gadget, color: "red"}]}
                     ])
                   end
    end
  end

  test "two modules declaring one property on any provider that takes properties are a conflict" do
    parties = [TestPlugins.GadgetColor, TestPlugins.OtherGadgetColor]

    assert {:error, %InvalidPluginSet{conflicts: [conflict]}} =
             Ltix.PluginSet.resolve([{Modules, add: [TestPlugins.Gadget | parties]}])

    assert %Conflict{
             parties: entries,
             reason: ~s(both declare the property "color" on TestPlugins.Gadget)
           } = conflict

    assert Enum.map(entries, & &1.module) == parties
  end

  defp build_poll_response(platform, plugins) do
    launch =
      Ltix.Test.build_launch(platform,
        message_type: :deep_linking,
        deep_linking_settings: %{accept_types: [@poll]},
        plugins: plugins
      )

    DeepLinking.build_response(launch, [Poll.new!(question: "Ready?")])
  end
end
