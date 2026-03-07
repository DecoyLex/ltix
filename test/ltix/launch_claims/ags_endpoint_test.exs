defmodule Ltix.LaunchClaims.AgsEndpointTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchClaims.AgsEndpoint

  doctest Ltix.LaunchClaims.AgsEndpoint

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

      assert {:ok, %AgsEndpoint{} = ags} = AgsEndpoint.from_json(json)

      assert ags.scope == [
               "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
               "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly"
             ]

      assert ags.lineitems == "https://platform.example.com/api/lineitems"
      assert ags.lineitem == "https://platform.example.com/api/lineitems/123"
    end

    test "parses empty map" do
      assert {:ok, %AgsEndpoint{scope: nil, lineitems: nil, lineitem: nil}} =
               AgsEndpoint.from_json(%{})
    end

    test "parses with only scope" do
      json = %{
        "scope" => ["https://purl.imsglobal.org/spec/lti-ags/scope/lineitem"]
      }

      assert {:ok, %AgsEndpoint{scope: [_], lineitems: nil}} = AgsEndpoint.from_json(json)
    end
  end
end
