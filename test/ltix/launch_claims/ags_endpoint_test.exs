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

      assert ags.scope == [
               "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
               "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly"
             ]

      assert ags.lineitems == "https://platform.example.com/api/lineitems"
      assert ags.lineitem == "https://platform.example.com/api/lineitems/123"
    end
  end
end
