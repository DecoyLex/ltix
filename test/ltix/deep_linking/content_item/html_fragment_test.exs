defmodule Ltix.DeepLinking.ContentItem.HTMLFragmentTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItem.HTMLFragment

  doctest HTMLFragment

  describe "new!/1" do
    test "raises the error new/1 returns" do
      assert_raise Ltix.Errors.Invalid.InvalidField, ~r/field :html /, fn ->
        HTMLFragment.new!([])
      end
    end
  end

  describe "to_map/1" do
    test "merges extensions at top level" do
      {:ok, fragment} =
        HTMLFragment.new(
          html: "<p>Hello</p>",
          extensions: %{"com.example.extra" => "value"}
        )

      json = ContentItem.to_map(fragment)

      assert json["com.example.extra"] == "value"
      refute Map.has_key?(json, "extensions")
    end
  end
end
