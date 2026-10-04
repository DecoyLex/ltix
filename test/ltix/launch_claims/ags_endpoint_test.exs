defmodule Ltix.LaunchClaims.AGSEndpointTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchClaims.AGSEndpoint

  doctest Ltix.LaunchClaims.AGSEndpoint

  describe "from_json/1" do
    # [Core §6.1] Service endpoint claim
    test "parses all fields" do
      json = %{
        "scope" => [
          "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
          "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly"
        ],
        "lineitems" => "https://platform.example.com/api/lineitems",
        "lineitem" => "https://platform.example.com/api/lineitems/123"
      }

      assert {:ok, %AGSEndpoint{} = ags} = AGSEndpoint.from_json(json)

      assert ags.scopes == [
               "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
               "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly"
             ]

      assert ags.line_items == "https://platform.example.com/api/lineitems"
      assert ags.line_item == "https://platform.example.com/api/lineitems/123"
    end

    test "ignores claim names the specification does not define" do
      json = %{
        "scopes" => ["https://purl.imsglobal.org/spec/lti-ags/scope/lineitem"],
        "line_items" => "https://platform.example.com/api/lineitems",
        "line_item" => "https://platform.example.com/api/lineitems/123"
      }

      assert {:ok, %AGSEndpoint{scopes: nil, line_items: nil, line_item: nil}} =
               AGSEndpoint.from_json(json)
    end
  end
end
