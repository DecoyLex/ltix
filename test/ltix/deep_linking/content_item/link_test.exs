defmodule Ltix.DeepLinking.ContentItem.LinkTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking.ContentItem.Link
  alias Ltix.Errors.Invalid.InvalidField

  doctest Link

  describe "new/1" do
    test "rejects unknown nested fields" do
      assert {:error, %InvalidField{field: [:window, :target], reason: :unknown}} =
               Link.new(url: "https://example.com", window: [target: "docs"])
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

      assert link.icon == %{url: "https://example.com/icon.png", width: 16, height: 16}
      assert link.embed == %{html: "<iframe></iframe>"}
      assert link.window == %{target_name: "example", width: 800}
      assert link.iframe == %{src: "https://example.com/embed", width: 640, height: 480}
    end

    test "describes the problem with a nested option that is not a map or keyword list" do
      assert {:error, %InvalidField{field: :icon} = error} =
               Link.new(url: "https://example.com", icon: "https://example.com/icon.png")

      assert Exception.message(error) ==
               ~s(Ltix.DeepLinking.ContentItem.Link field :icon must be a map or keyword list \(got "https://example.com/icon.png"\))
    end

    test "validates keyword list sub-structures (missing required field)" do
      assert {:error, %InvalidField{} = error} =
               Link.new(url: "https://example.com", icon: [width: 16])

      assert Exception.message(error) =~ "[:icon, :url]"
      assert Exception.message(error) =~ "is required"
    end

    test "requires a required nested field given nil" do
      assert {:error, %InvalidField{field: [:iframe, :src], reason: :required}} =
               Link.new(url: "https://example.com", iframe: [src: nil, width: 640])
    end
  end
end
