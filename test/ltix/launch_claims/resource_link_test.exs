defmodule Ltix.LaunchClaims.ResourceLinkTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchClaims.ResourceLink

  doctest Ltix.LaunchClaims.ResourceLink

  describe "from_json/1" do
    # [Core §5.3.5] id is REQUIRED
    test "parses all fields" do
      json = %{
        "id" => "resource-link-001",
        "title" => "Example Assignment",
        "description" => "An assignment for testing"
      }

      assert {:ok, %ResourceLink{} = rl} = ResourceLink.from_json(json)
      assert rl.id == "resource-link-001"
      assert rl.title == "Example Assignment"
      assert rl.description == "An assignment for testing"
    end

    test "parses with only required id" do
      assert {:ok, %ResourceLink{id: "rl-1", title: nil, description: nil}} =
               ResourceLink.from_json(%{"id" => "rl-1"})
    end

    # [Core §5.3.5] id is REQUIRED
    test "returns error when id missing" do
      assert {:error, error} = ResourceLink.from_json(%{"title" => "No ID"})
      assert Exception.message(error) =~ "resource_link.id"
    end

    test "returns error for empty map" do
      assert {:error, _} = ResourceLink.from_json(%{})
    end
  end
end
