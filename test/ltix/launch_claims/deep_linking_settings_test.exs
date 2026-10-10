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
      assert dls.accept_line_item == false
      assert dls.auto_create == true
      assert dls.title == "Select Content"
      assert dls.text == "Please select content to link"
      assert dls.data == "opaque-platform-data"
    end

    test "returns error mentioning all missing required fields" do
      assert {:error, error} = DeepLinkingSettings.from_json(%{})
      message = Exception.message(error)
      assert message =~ "deep_linking_settings.deep_link_return_url"
      assert message =~ "deep_linking_settings.accept_types"
      assert message =~ "deep_linking_settings.accept_presentation_document_targets"
    end
  end
end
