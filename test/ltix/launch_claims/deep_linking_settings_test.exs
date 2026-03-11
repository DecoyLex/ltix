defmodule Ltix.LaunchClaims.DeepLinkingSettingsTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchClaims.DeepLinkingSettings

  doctest Ltix.LaunchClaims.DeepLinkingSettings

  describe "from_json/1" do
    # [Core §6.1] deep_link_return_url REQUIRED when claim present
    test "parses all fields" do
      json = %{
        "deep_link_return_url" => "https://platform.example.com/deep-link/return",
        "accept_types" => ["link", "ltiResourceLink"],
        "accept_presentation_document_targets" => ["iframe", "window"],
        "accept_media_types" => "application/pdf,image/*",
        "accept_multiple" => true,
        "accept_lineitem" => false,
        "auto_create" => true,
        "title" => "Select Content",
        "text" => "Please select content to link",
        "data" => "opaque-platform-data"
      }

      assert {:ok, %DeepLinkingSettings{} = dls} = DeepLinkingSettings.from_json(json)
      assert dls.deep_link_return_url == "https://platform.example.com/deep-link/return"
      assert dls.accept_types == ["link", "ltiResourceLink"]
      assert dls.accept_presentation_document_targets == ["iframe", "window"]
      assert dls.accept_media_types == "application/pdf,image/*"
      assert dls.accept_multiple == true
      assert dls.accept_lineitem == false
      assert dls.auto_create == true
      assert dls.title == "Select Content"
      assert dls.text == "Please select content to link"
      assert dls.data == "opaque-platform-data"
    end

    # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
    test "parses with only required fields" do
      json = %{
        "deep_link_return_url" => "https://platform.example.com/return",
        "accept_types" => ["link"],
        "accept_presentation_document_targets" => ["iframe"]
      }

      assert {:ok, %DeepLinkingSettings{} = dls} = DeepLinkingSettings.from_json(json)
      assert dls.deep_link_return_url == "https://platform.example.com/return"
      assert dls.accept_types == ["link"]
      assert dls.accept_presentation_document_targets == ["iframe"]
      assert dls.accept_multiple == nil
    end

    # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
    test "returns error when deep_link_return_url missing" do
      json = %{
        "accept_types" => ["link"],
        "accept_presentation_document_targets" => ["iframe"]
      }

      assert {:error, error} = DeepLinkingSettings.from_json(json)
      assert Exception.message(error) =~ "deep_link_return_url"
    end

    # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
    test "returns error when accept_types missing" do
      json = %{
        "deep_link_return_url" => "https://platform.example.com/return",
        "accept_presentation_document_targets" => ["iframe"]
      }

      assert {:error, error} = DeepLinkingSettings.from_json(json)
      assert Exception.message(error) =~ "accept_types"
    end

    # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
    test "returns error when accept_presentation_document_targets missing" do
      json = %{
        "deep_link_return_url" => "https://platform.example.com/return",
        "accept_types" => ["link"]
      }

      assert {:error, error} = DeepLinkingSettings.from_json(json)
      assert Exception.message(error) =~ "accept_presentation_document_targets"
    end

    test "returns error for empty map" do
      assert {:error, error} = DeepLinkingSettings.from_json(%{})
      assert Exception.message(error) =~ "deep_link_return_url"
    end
  end
end
