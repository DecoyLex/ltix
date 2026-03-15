defmodule Ltix.DeepLinking.ContentItem.MapTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking.ContentItem

  describe "item_type/1" do
    test "returns the type field" do
      assert "link" = ContentItem.item_type(%{"type" => "link", "url" => "https://a.com"})
    end

    test "raises for map without type field" do
      assert_raise ArgumentError, ~r/missing 'type' field/, fn ->
        ContentItem.item_type(%{"url" => "https://a.com"})
      end
    end
  end

  describe "to_json/1" do
    test "returns the map as-is" do
      map = %{"type" => "link", "url" => "https://a.com"}
      assert map == ContentItem.to_json(map)
    end
  end
end
