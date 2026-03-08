defmodule Ltix.LaunchClaims.MembershipsEndpointTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchClaims.MembershipsEndpoint

  doctest Ltix.LaunchClaims.MembershipsEndpoint

  describe "from_json/1" do
    # [Core §6.1] NRPS service endpoint
    test "parses all fields" do
      json = %{
        "context_memberships_url" => "https://platform.example.com/api/memberships",
        "service_versions" => ["2.0"]
      }

      assert {:ok, %MembershipsEndpoint{} = endpoint} = MembershipsEndpoint.from_json(json)
      assert endpoint.context_memberships_url == "https://platform.example.com/api/memberships"
      assert endpoint.service_versions == ["2.0"]
    end

    test "parses empty map" do
      assert {:ok, %MembershipsEndpoint{context_memberships_url: nil, service_versions: nil}} =
               MembershipsEndpoint.from_json(%{})
    end
  end

  describe "new/1" do
    test "creates endpoint from URL string" do
      endpoint = MembershipsEndpoint.new("https://lms.example.com/memberships")

      assert %MembershipsEndpoint{} = endpoint
      assert endpoint.context_memberships_url == "https://lms.example.com/memberships"
      assert endpoint.service_versions == nil
    end
  end
end
