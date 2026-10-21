defmodule Ltix.Launch.CallbackDeepLinkingTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking.Settings
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.Launch
  alias Ltix.Test.StorageAdapter

  @lti "https://purl.imsglobal.org/spec/lti/claim/"
  @dl_settings_key "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings"

  setup do
    platform = Ltix.Test.setup_platform!()
    StorageAdapter.set_pid(start_supervised!({StorageAdapter, platforms: [platform]}))
    login = LaunchFlow.login!(platform)

    settings = %{
      "deep_link_return_url" => "https://platform.example.com/deep_links",
      "accept_types" => ["ltiResourceLink", "link"],
      "accept_presentation_document_targets" => ["iframe", "window"],
      "accept_multiple" => true
    }

    claims =
      platform
      |> Ltix.Test.valid_lti_claims(%{
        "nonce" => LaunchFlow.nonce(login),
        (@lti <> "message_type") => "LtiDeepLinkingRequest",
        @dl_settings_key => settings
      })
      |> Map.delete(@lti <> "resource_link")

    %{platform: platform, state: login.state, claims: claims}
  end

  # Signs `claims` with the platform's key and handles the callback.
  defp callback(claims, ctx), do: LaunchFlow.callback_with_claims(ctx.platform, claims, ctx.state)

  defp delete_setting(ctx, key),
    do: Map.update!(ctx.claims, @dl_settings_key, &Map.delete(&1, key))

  # [DL §4.4](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-request-message)
  describe "valid deep linking launch" do
    test "deep linking launch returns Launch", ctx do
      assert {:ok, %Launch{} = launch} = callback(ctx.claims, ctx)

      assert launch.claims.message_type == "LtiDeepLinkingRequest"
      assert launch.claims.version == "1.3.0"
      assert launch.claims.deployment_id == "deployment-001"
      assert launch.claims.target_link_uri == "https://tool.example.com/launch"

      assert %Settings{
               deep_link_return_url: "https://platform.example.com/deep_links",
               accept_types: ["ltiResourceLink", "link"],
               accept_presentation_document_targets: ["iframe", "window"],
               accept_multiple: true
             } = launch.claims.deep_linking_settings

      assert launch.claims.resource_link == nil
    end

    # [DL §4.4.9](https://www.imsglobal.org/spec/lti-dl/v2p0/#role)
    test "succeeds without roles claim", ctx do
      assert {:ok, %Launch{}} = callback(Map.delete(ctx.claims, @lti <> "roles"), ctx)
    end

    # [DL §4.4.5](https://www.imsglobal.org/spec/lti-dl/v2p0/#user)
    test "succeeds without sub claim", ctx do
      assert {:ok, %Launch{} = launch} = callback(Map.delete(ctx.claims, "sub"), ctx)
      assert launch.claims.subject == nil
    end
  end

  # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
  describe "deep_linking_settings validation" do
    test "missing deep_linking_settings returns MissingClaim error", ctx do
      assert {:error, %MissingClaim{claim: "deep_linking_settings"}} =
               callback(Map.delete(ctx.claims, @dl_settings_key), ctx)
    end

    test "non-object deep_linking_settings returns InvalidClaim error", ctx do
      assert {:error, %InvalidClaim{claim: "deep_linking_settings", value: "settings"}} =
               callback(Map.put(ctx.claims, @dl_settings_key, "settings"), ctx)
    end

    for key <- ~w(deep_link_return_url accept_types accept_presentation_document_targets) do
      test "missing #{key} in settings returns MissingClaim for it", ctx do
        claim = "deep_linking_settings." <> unquote(key)

        assert {:error, %MissingClaim{claim: ^claim}} =
                 callback(delete_setting(ctx, unquote(key)), ctx)
      end
    end
  end
end
