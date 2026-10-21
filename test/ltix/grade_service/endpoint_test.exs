defmodule Ltix.GradeService.EndpointTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.GradeService.Endpoint

  doctest Ltix.GradeService.Endpoint

  describe "new/1" do
    @scopes ["https://purl.imsglobal.org/spec/lti-ags/scope/score"]
    @line_item "https://platform.example.com/lineitems/1"

    test "builds an endpoint from a keyword list or a map" do
      expected = %Endpoint{scopes: @scopes, line_items: nil, line_item: @line_item}

      assert {:ok, ^expected} = Endpoint.new(scopes: @scopes, line_item: @line_item)
      assert {:ok, ^expected} = Endpoint.new(%{scopes: @scopes, line_item: @line_item})
    end

    test "accepts nil for optional URLs" do
      assert {:ok, %Endpoint{scopes: @scopes, line_items: nil, line_item: nil}} =
               Endpoint.new(scopes: @scopes, line_items: nil, line_item: nil)
    end

    test "requires scopes" do
      assert {:error, %InvalidField{struct: Endpoint, field: :scopes, reason: :required}} =
               Endpoint.new(line_item: @line_item)

      assert {:error, %InvalidField{field: :scopes, reason: :required}} =
               Endpoint.new(scopes: nil, line_item: @line_item)

      assert {:error, %InvalidField{field: :scopes, value: []}} =
               Endpoint.new(scopes: [], line_item: @line_item)
    end

    test "requires absolute HTTPS URLs" do
      for field <- [:line_items, :line_item] do
        url = "http://platform.example.com/lineitems"

        assert {:error, %InvalidField{field: ^field, value: ^url}} =
                 Endpoint.new([{:scopes, @scopes}, {field, url}])
      end
    end

    test "rejects unknown keys" do
      assert {:error, %InvalidField{field: :lineitems, value: @line_item, reason: :unknown}} =
               Endpoint.new(scopes: @scopes, lineitems: @line_item)

      assert {:error, %InvalidField{field: :lineitems, reason: :unknown}} =
               Endpoint.new(scopes: @scopes, lineitems: nil)
    end

    test "new! returns the endpoint or raises the error" do
      assert %Endpoint{scopes: @scopes} = Endpoint.new!(scopes: @scopes)
      assert_raise InvalidField, fn -> Endpoint.new!(line_item: @line_item) end
    end
  end
end
