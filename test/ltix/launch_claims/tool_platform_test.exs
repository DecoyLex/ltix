defmodule Ltix.LaunchClaims.ToolPlatformTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchClaims.ToolPlatform

  doctest Ltix.LaunchClaims.ToolPlatform

  describe "from_json/1" do
    # [Core §5.4.2] guid is REQUIRED
    test "parses all fields" do
      json = %{
        "guid" => "platform-guid-001",
        "name" => "Example LMS",
        "contact_email" => "admin@example.com",
        "description" => "An example LMS platform",
        "url" => "https://platform.example.com",
        "product_family_code" => "example-lms",
        "version" => "2.1"
      }

      assert {:ok, %ToolPlatform{} = tp} = ToolPlatform.from_json(json)
      assert tp.guid == "platform-guid-001"
      assert tp.name == "Example LMS"
      assert tp.contact_email == "admin@example.com"
      assert tp.description == "An example LMS platform"
      assert tp.url == "https://platform.example.com"
      assert tp.product_family_code == "example-lms"
      assert tp.version == "2.1"
    end

    test "parses with only required guid" do
      assert {:ok, %ToolPlatform{guid: "guid-1", name: nil}} =
               ToolPlatform.from_json(%{"guid" => "guid-1"})
    end

    # [Core §5.4.2] guid is REQUIRED
    test "returns error when guid missing" do
      assert {:error, error} = ToolPlatform.from_json(%{"name" => "No GUID"})
      assert Exception.message(error) =~ "tool_platform.guid"
    end

    test "returns error for empty map" do
      assert {:error, _} = ToolPlatform.from_json(%{})
    end
  end
end
