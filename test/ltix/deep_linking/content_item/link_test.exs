defmodule Ltix.DeepLinking.ContentItem.LinkTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItem.Link

  describe "new/1" do
    test "succeeds with required url field" do
      assert {:ok, %Link{url: "https://example.com"}} =
               Link.new(url: "https://example.com")
    end

    test "returns error without url field" do
      assert {:error, %Ltix.Errors.Invalid{} = error} = Link.new([])
      assert Exception.message(error) =~ "link.url"
      assert Exception.message(error) =~ "is required"
    end

    test "succeeds with all sub-structures" do
      assert {:ok, link} =
               Link.new(
                 url: "https://example.com",
                 title: "Example",
                 text: "An example link",
                 icon: %{url: "https://example.com/icon.png", width: 16, height: 16},
                 thumbnail: %{url: "https://example.com/thumb.png"},
                 embed: %{html: "<iframe src='https://example.com'></iframe>"},
                 window: %{
                   target_name: "example",
                   width: 800,
                   height: 600,
                   window_features: "menubar=no"
                 },
                 iframe: %{src: "https://example.com/embed", width: 640, height: 480}
               )

      assert link.window.target_name == "example"
      assert link.iframe.src == "https://example.com/embed"
      assert link.embed.html == "<iframe src='https://example.com'></iframe>"
    end
  end

  describe "to_json/1" do
    test "includes type and url" do
      {:ok, link} = Link.new(url: "https://example.com")
      json = ContentItem.to_json(link)

      assert json["type"] == "link"
      assert json["url"] == "https://example.com"
    end

    test "serializes icon and thumbnail" do
      {:ok, link} =
        Link.new(
          url: "https://example.com",
          icon: %{url: "https://example.com/icon.png"},
          thumbnail: %{url: "https://example.com/thumb.png", width: 100, height: 75}
        )

      json = ContentItem.to_json(link)

      assert json["icon"] == %{"url" => "https://example.com/icon.png"}

      assert json["thumbnail"] == %{
               "url" => "https://example.com/thumb.png",
               "width" => 100,
               "height" => 75
             }
    end

    test "serializes embed sub-structure" do
      {:ok, link} =
        Link.new(
          url: "https://example.com",
          embed: %{html: "<iframe></iframe>"}
        )

      json = ContentItem.to_json(link)

      assert json["embed"] == %{"html" => "<iframe></iframe>"}
    end

    test "serializes window with camelCase keys" do
      {:ok, link} =
        Link.new(
          url: "https://example.com",
          window: %{
            target_name: "example",
            width: 800,
            height: 600,
            window_features: "menubar=no"
          }
        )

      json = ContentItem.to_json(link)

      assert json["window"] == %{
               "targetName" => "example",
               "width" => 800,
               "height" => 600,
               "windowFeatures" => "menubar=no"
             }
    end

    test "serializes iframe with src" do
      {:ok, link} =
        Link.new(
          url: "https://example.com",
          iframe: %{src: "https://example.com/embed", width: 640, height: 480}
        )

      json = ContentItem.to_json(link)

      assert json["iframe"] == %{
               "src" => "https://example.com/embed",
               "width" => 640,
               "height" => 480
             }
    end

    test "excludes nil optional fields" do
      {:ok, link} = Link.new(url: "https://example.com")
      json = ContentItem.to_json(link)

      refute Map.has_key?(json, "title")
      refute Map.has_key?(json, "icon")
      refute Map.has_key?(json, "embed")
      refute Map.has_key?(json, "window")
      refute Map.has_key?(json, "iframe")
    end

    test "merges extensions at top level" do
      {:ok, link} =
        Link.new(
          url: "https://example.com",
          extensions: %{"com.example" => "extra"}
        )

      json = ContentItem.to_json(link)

      assert json["com.example"] == "extra"
      refute Map.has_key?(json, "extensions")
    end
  end
end
