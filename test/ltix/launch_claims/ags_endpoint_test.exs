defmodule Ltix.LaunchClaims.AGSEndpointTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.InvalidField
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

    test "names the claim by its key when the claim is not an object" do
      assert {:error,
              %InvalidClaim{claim: "https://purl.imsglobal.org/spec/lti-ags/claim/endpoint"}} =
               AGSEndpoint.from_json("https://platform.example.com/api/lineitems")
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

  describe "new/1" do
    @scopes ["https://purl.imsglobal.org/spec/lti-ags/scope/score"]
    @line_item "https://platform.example.com/lineitems/1"

    test "builds an endpoint from a keyword list or a map" do
      expected = %AGSEndpoint{scopes: @scopes, line_items: nil, line_item: @line_item}

      assert {:ok, ^expected} = AGSEndpoint.new(scopes: @scopes, line_item: @line_item)
      assert {:ok, ^expected} = AGSEndpoint.new(%{scopes: @scopes, line_item: @line_item})
    end

    test "accepts nil for optional URLs" do
      assert {:ok, %AGSEndpoint{scopes: @scopes, line_items: nil, line_item: nil}} =
               AGSEndpoint.new(scopes: @scopes, line_items: nil, line_item: nil)
    end

    test "requires scopes" do
      assert {:error, %InvalidField{struct: AGSEndpoint, field: :scopes, reason: :required}} =
               AGSEndpoint.new(line_item: @line_item)

      assert {:error, %InvalidField{field: :scopes, reason: :required}} =
               AGSEndpoint.new(scopes: nil, line_item: @line_item)

      assert {:error, %InvalidField{field: :scopes, value: []}} =
               AGSEndpoint.new(scopes: [], line_item: @line_item)
    end

    test "requires absolute HTTPS URLs" do
      for field <- [:line_items, :line_item] do
        url = "http://platform.example.com/lineitems"

        assert {:error, %InvalidField{field: ^field, value: ^url}} =
                 AGSEndpoint.new([{:scopes, @scopes}, {field, url}])
      end
    end

    test "rejects unknown keys" do
      assert {:error, %InvalidField{field: :lineitems, value: @line_item, reason: :unknown}} =
               AGSEndpoint.new(scopes: @scopes, lineitems: @line_item)

      assert {:error, %InvalidField{field: :lineitems, reason: :unknown}} =
               AGSEndpoint.new(scopes: @scopes, lineitems: nil)
    end
  end
end
