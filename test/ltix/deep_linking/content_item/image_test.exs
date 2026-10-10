defmodule Ltix.DeepLinking.ContentItem.ImageTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItem.Image

  doctest Image

  describe "new!/1" do
    test "raises the error new/1 returns" do
      assert_raise Ltix.Errors.Invalid.InvalidField, ~r/field :url /, fn ->
        Image.new!([])
      end
    end
  end

  describe "to_map/1" do
    test "includes type and url" do
      {:ok, image} = Image.new(url: "https://example.com/image.png", width: 800, height: 600)
      json = ContentItem.to_map(image)

      assert json["type"] == "image"
      assert json["url"] == "https://example.com/image.png"
      assert json["width"] == 800
      assert json["height"] == 600
    end
  end
end
