defmodule Ltix.Plugins.MessageTypesTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.Errors.Unknown.InvalidPluginSet
  alias Ltix.PluginSet
  alias Ltix.PluginSet.Conflict
  alias Ltix.Test.StorageAdapter
  alias Ltix.Validator
  alias TestPlugins.Modules

  @lti "https://purl.imsglobal.org/spec/lti/claim/"
  @context @lti <> "context"
  @ags_scope "https://purl.imsglobal.org/spec/lti-ags/scope/score"

  setup do
    platform = Ltix.Test.setup_platform!()
    StorageAdapter.set_pid(start_supervised!({StorageAdapter, platforms: [platform]}))
    %{platform: platform}
  end

  # Logs in, then handles the callback of a launch built with `opts`.
  defp launch(platform, opts, callback_opts \\ []) do
    {:ok, login} =
      Ltix.handle_login(Ltix.Test.login_params(platform), "https://tool.example.com/launch")

    nonce = Ltix.Test.extract_nonce(login.redirect_uri)
    params = Ltix.Test.launch_params(platform, [nonce: nonce, state: login.state] ++ opts)

    Ltix.handle_callback(
      params,
      login.state,
      [req_options: [plug: {Req.Test, Ltix.JWT.KeySet}]] ++ callback_opts
    )
  end

  doctest Ltix.Validator

  describe "message types" do
    test "a launch whose message type no plugin declares is rejected", %{platform: platform} do
      assert {:error, %InvalidClaim{claim: "message_type", value: "LtiTestRequest"}} =
               launch(platform, message_type: "LtiTestRequest")
    end

    test "a plugin declares a message type, and its launches are accepted", %{
      platform: platform
    } do
      plugins = [{Modules, add: [TestPlugins.TestRequest]}]

      assert {:ok, launch} =
               launch(platform, [message_type: "LtiTestRequest"], plugins: plugins)

      assert launch.claims.message_type == "LtiTestRequest"
      assert launch.claims.resource_link == nil
    end
  end

  describe "other plugins" do
    test "require a claim in one message type", %{platform: platform} do
      plugins = [{Modules, add: [TestPlugins.RequireContext]}]

      assert {:error, %MissingClaim{claim: "context"}} =
               launch(platform, [claims: %{@context => nil}], plugins: plugins)

      assert {:ok, _launch} =
               launch(
                 platform,
                 [message_type: :deep_linking, claims: %{@context => nil}],
                 plugins: plugins
               )
    end

    test "to a message type that isn't in the plugin set do nothing", %{platform: platform} do
      assert {:ok, _launch} =
               launch(platform, [], plugins: [{Modules, add: [TestPlugins.RequireContext]}])
    end

    test "require a claim when an includes condition holds", %{platform: platform} do
      plugins = [{Modules, add: [TestPlugins.RequireLisForFiles]}]

      assert {:error, %MissingClaim{claim: "lis"}} =
               launch(
                 platform,
                 [message_type: :deep_linking, deep_linking_settings: %{accept_types: ["file"]}],
                 plugins: plugins
               )

      assert {:ok, _launch} =
               launch(
                 platform,
                 [message_type: :deep_linking, deep_linking_settings: %{accept_types: ["link"]}],
                 plugins: plugins
               )
    end

    test "require a claim when a condition module holds", %{platform: platform} do
      plugins = [{Modules, add: [TestPlugins.RequireContextWhenGraded]}]
      ags_endpoint = %{line_item: "https://platform.example.com/items/1", scopes: [@ags_scope]}

      assert {:error, %MissingClaim{claim: "context"}} =
               launch(platform, [ags_endpoint: ags_endpoint, claims: %{@context => nil}],
                 plugins: plugins
               )

      assert {:ok, _launch} = launch(platform, [claims: %{@context => nil}], plugins: plugins)
    end

    test "set defaults in every message type that optional/3 can't undo", %{
      platform: platform
    } do
      plugins = [{Modules, add: [TestPlugins.Baseline]}]

      assert {:error, %MissingClaim{claim: "context"}} =
               launch(
                 platform,
                 [message_type: :deep_linking, claims: %{@context => nil}],
                 plugins: plugins
               )

      assert {:error, %MissingClaim{claim: "roles"}} =
               launch(
                 platform,
                 [message_type: :deep_linking, claims: %{(@lti <> "roles") => nil}],
                 plugins: plugins
               )

      assert {:ok, launch} =
               launch(platform, [message_type: :deep_linking, roles: []], plugins: plugins)

      assert launch.claims.roles == []
    end

    test "can't make a claim Core requires optional with optional/3", %{platform: platform} do
      assert {:error, %MissingClaim{claim: "deployment_id"}} =
               launch(platform, [claims: %{(@lti <> "deployment_id") => nil}],
                 plugins: [{Modules, add: [TestPlugins.OptionalDeploymentId]}]
               )
    end

    test "override deployment_id to optional, and a launch without one has no deployment", %{
      platform: platform
    } do
      :telemetry_test.attach_event_handlers(self(), [[:ltix, :callback, :stop]])

      assert {:ok, launch} =
               launch(platform, [claims: %{(@lti <> "deployment_id") => nil}],
                 plugins: [{Modules, add: [TestPlugins.WithoutDeploymentId]}]
               )

      assert launch.claims.deployment_id == nil
      assert launch.deployment == nil
      assert_received {[:ltix, :callback, :stop], _ref, _measurements, %{deployment_id: nil}}
    end

    test "can't make message_type optional", %{platform: platform} do
      assert {:error, %MissingClaim{claim: "message_type"}} =
               launch(platform, [claims: %{(@lti <> "message_type") => nil}],
                 plugins: [{Modules, add: [TestPlugins.WithoutMessageType]}]
               )
    end

    test "override a claim, and another plugin's required/3 doesn't undo it", %{
      platform: platform
    } do
      plugins = [{Modules, add: [TestPlugins.OptionalRoles, TestPlugins.RequireRoles]}]

      assert {:ok, launch} =
               launch(platform, [claims: %{(@lti <> "roles") => nil}], plugins: plugins)

      assert launch.claims.roles == []
    end
  end

  describe "message types conflict" do
    for {parties, reason} <- [
          {[TestPlugins.TestRequest, TestPlugins.OtherTestRequest],
           "both declare the message type LtiTestRequest"},
          {[TestPlugins.OptionalRoles, TestPlugins.OtherOptionalRoles],
           "both override :roles in LtiResourceLinkRequest"},
          {[TestPlugins.RequireUndeclared],
           "states the claim :proctoring_session, which no plugin declares"}
        ] do
      test "when #{inspect(parties)} #{reason}", %{platform: platform} do
        plugins = [{Modules, add: unquote(parties)}]

        assert {:error, %InvalidPluginSet{conflicts: [conflict]} = error} =
                 launch(platform, [], plugins: plugins)

        assert %Conflict{parties: entries, reason: unquote(reason)} = conflict
        assert Enum.map(entries, & &1.module) == unquote(parties)

        for party <- unquote(parties),
            do: assert(Exception.message(error) =~ "#{inspect(party)} (Modules 1.0.0)")
      end
    end
  end

  describe "message type docs" do
    test "show the module that stated each requirement in a launch's validators", %{
      platform: platform
    } do
      assert {:ok, launch} =
               launch(platform, [], plugins: [{Modules, add: [TestPlugins.RequireContext]}])

      %{message_types: validators} = PluginSet.data(launch.plugins, Ltix.Launch.MessageType)

      assert Validator.describe(validators["LtiResourceLinkRequest"]) == """
             | Claim | Requirement | Stated by |
             |---|---|---|
             | `resource_link` | Required | `Ltix.ResourceLinkRequest` |
             | `roles` | Required | `Ltix.ResourceLinkRequest` |
             | `subject` | Required unless the `:allow_anonymous` option is set | `Ltix.ResourceLinkRequest` |
             | `context` | Required | `TestPlugins.RequireContext` |
             | `version` | Required | `Ltix.Core.RequiredClaims` |
             | `deployment_id` | Required | `Ltix.Core.RequiredClaims` |
             | `target_link_uri` | Required | `Ltix.Core.RequiredClaims` |
             """
    end

    test "show the validators of Ltix's message types" do
      assert moduledoc(Ltix.ResourceLinkRequest) =~ """
             ## Claims

             | Claim | Requirement |
             |---|---|
             | `resource_link` | Required |
             | `roles` | Required |
             | `subject` | Required unless the `:allow_anonymous` option is set |
             """

      assert moduledoc(Ltix.DeepLinkingRequest) =~ """
             ## Claims

             | Claim | Requirement |
             |---|---|
             | `deep_linking_settings` | Required |
             | `roles` | Optional |
             """
    end
  end

  defp moduledoc(module) do
    {:docs_v1, _anno, _language, _format, %{"en" => moduledoc}, _metadata, _docs} =
      Code.fetch_docs(module)

    moduledoc
  end
end
