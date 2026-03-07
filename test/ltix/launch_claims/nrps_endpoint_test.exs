defmodule Ltix.LaunchClaims.NrpsEndpointTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchClaims.NrpsEndpoint

  doctest Ltix.LaunchClaims.NrpsEndpoint

  describe "from_json/1" do
    # [Core §6.1] NRPS service endpoint
    test "parses all fields" do
      json = %{
        "context_memberships_url" => "https://platform.example.com/api/memberships",
        "service_versions" => ["2.0"]
      }

      assert {:ok, %NrpsEndpoint{} = nrps} = NrpsEndpoint.from_json(json)
      assert nrps.context_memberships_url == "https://platform.example.com/api/memberships"
      assert nrps.service_versions == ["2.0"]
    end

    test "parses empty map" do
      assert {:ok, %NrpsEndpoint{context_memberships_url: nil, service_versions: nil}} =
               NrpsEndpoint.from_json(%{})
    end
  end
end
