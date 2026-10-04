defmodule Ltix.DeepLinking.ContentItem.LinkTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItem.Link

  doctest Link

  describe "new/1" do
    test "succeeds with required url field" do
      assert {:ok, %Link{url: "https://example.com"}} =
               Link.new(url: "https://example.com")
    end

    test "returns error without url field" do
      assert {:error,
              %Ltix.Errors.Invalid.InvalidField{struct: Link, field: :url, reason: :required}} =
               Link.new([])
    end

    test "accepts a map" do
      assert {:ok, %Link{url: "https://example.com", window: %{target_name: "docs"}}} =
               Link.new(%{url: "https://example.com", window: %{target_name: "docs"}})
    end

    test "rejects unknown fields" do
      assert {:error,
              %Ltix.Errors.Invalid{
                errors: [
                  %Ltix.Errors.Invalid.InvalidField{field: [:window, :target]},
                  %Ltix.Errors.Invalid.InvalidField{field: :titel, value: "Docs"}
                ]
              }} =
               Link.new(url: "https://example.com", titel: "Docs", window: [target: "docs"])
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

    test "accepts sub-structures as keyword lists" do
      assert {:ok, link} =
               Link.new(
                 url: "https://example.com",
                 icon: [url: "https://example.com/icon.png", width: 16, height: 16],
                 embed: [html: "<iframe></iframe>"],
                 window: [target_name: "example", width: 800],
                 iframe: [src: "https://example.com/embed", width: 640, height: 480]
               )

      assert link.icon.url == "https://example.com/icon.png"
      assert link.icon.width == 16
      assert link.embed.html == "<iframe></iframe>"
      assert link.window.target_name == "example"
      assert link.iframe.src == "https://example.com/embed"
    end

    test "rejects extensions that would replace standard fields" do
      assert {:error,
              %Ltix.Errors.Invalid{
                errors: [
                  %Ltix.Errors.Invalid.InvalidField{
                    field: [:extensions, "title"],
                    value: "Docs"
                  },
                  %Ltix.Errors.Invalid.InvalidField{
                    field: [:extensions, "type"],
                    value: "file"
                  }
                ]
              }} =
               Link.new(
                 url: "https://example.com",
                 extensions: %{
                   "type" => "file",
                   "title" => "Docs",
                   "https://vendor.example.com/x" => 1
                 }
               )
    end

    test "accepts extensions as a keyword list" do
      assert {:ok, %Link{extensions: %{"vendor_flag" => true}}} =
               Link.new(url: "https://example.com", extensions: [vendor_flag: true])
    end

    test "names the problem with a nested option that is not a map or keyword list" do
      assert {:error, %Ltix.Errors.Invalid.InvalidField{field: :icon} = error} =
               Link.new(url: "https://example.com", icon: "https://example.com/icon.png")

      assert Exception.message(error) =~ "expected a map or keyword list"
    end

    test "validates keyword list sub-structures (missing required field)" do
      assert {:error, %Ltix.Errors.Invalid.InvalidField{} = error} =
               Link.new(url: "https://example.com", icon: [width: 16])

      assert Exception.message(error) =~ "[:icon, :url]"
      assert Exception.message(error) =~ "is required"
    end
  end

  describe "new!/1" do
    test "raises the error new/1 returns" do
      assert_raise Ltix.Errors.Invalid.InvalidField, ~r/field :url /, fn -> Link.new!([]) end
    end
  end

  describe "to_map/1" do
    test "includes type and url" do
      {:ok, link} = Link.new(url: "https://example.com")
      json = ContentItem.to_map(link)

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

      json = ContentItem.to_map(link)

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

      json = ContentItem.to_map(link)

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

      json = ContentItem.to_map(link)

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

      json = ContentItem.to_map(link)

      assert json["iframe"] == %{
               "src" => "https://example.com/embed",
               "width" => 640,
               "height" => 480
             }
    end

    test "excludes nil optional fields" do
      {:ok, link} = Link.new(url: "https://example.com")
      json = ContentItem.to_map(link)

      refute Map.has_key?(json, "title")
      refute Map.has_key?(json, "icon")
      refute Map.has_key?(json, "embed")
      refute Map.has_key?(json, "window")
      refute Map.has_key?(json, "iframe")
    end

    test "keeps standard fields when extensions name the same keys" do
      link = %Link{
        url: "https://example.com",
        extensions: %{"type" => "file", "url" => "https://other.example.com"}
      }

      assert %{"type" => "link", "url" => "https://example.com"} = ContentItem.to_map(link)
    end

    test "merges extensions at top level" do
      {:ok, link} =
        Link.new(
          url: "https://example.com",
          extensions: %{"com.example" => "extra"}
        )

      json = ContentItem.to_map(link)

      assert json["com.example"] == "extra"
      refute Map.has_key?(json, "extensions")
    end
  end
end
