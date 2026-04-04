defmodule Ltix.DeepLinking.ContentItem.ImageTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItem.Image

  describe "new/1" do
    test "succeeds with required url field" do
      assert {:ok, %Image{url: "https://example.com/image.png"}} =
               Image.new(url: "https://example.com/image.png")
    end

    test "returns error without url field" do
      assert {:error, %Ltix.Errors.Invalid{} = error} = Image.new([])
      assert Exception.message(error) =~ "image.url"
      assert Exception.message(error) =~ "is required"
    end

    test "succeeds with all fields" do
      assert {:ok, image} =
               Image.new(
                 url: "https://example.com/image.png",
                 title: "A photo",
                 text: "Description",
                 icon: %{url: "https://example.com/icon.png", width: 50, height: 50},
                 thumbnail: %{url: "https://example.com/thumb.png"},
                 width: 800,
                 height: 600
               )

      assert image.url == "https://example.com/image.png"
      assert image.icon.url == "https://example.com/icon.png"
      assert image.icon.width == 50
      assert image.thumbnail.url == "https://example.com/thumb.png"
      assert image.width == 800
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

    test "serializes icon sub-structure" do
      {:ok, image} =
        Image.new(
          url: "https://example.com/image.png",
          icon: %{url: "https://example.com/icon.png", width: 16, height: 16}
        )

      json = ContentItem.to_map(image)

      assert json["icon"] == %{
               "url" => "https://example.com/icon.png",
               "width" => 16,
               "height" => 16
             }
    end

    test "excludes nil optional fields" do
      {:ok, image} = Image.new(url: "https://example.com/image.png")
      json = ContentItem.to_map(image)

      refute Map.has_key?(json, "title")
      refute Map.has_key?(json, "icon")
      refute Map.has_key?(json, "width")
    end

    test "merges extensions at top level" do
      {:ok, image} =
        Image.new(
          url: "https://example.com/image.png",
          extensions: %{"com.example" => "extra"}
        )

      json = ContentItem.to_map(image)

      assert json["com.example"] == "extra"
      refute Map.has_key?(json, "extensions")
    end
  end
end
