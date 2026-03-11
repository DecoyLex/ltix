defmodule Ltix.DeepLinking.ContentItem.HtmlFragmentTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItem.HtmlFragment

  describe "new/1" do
    test "succeeds with required html field" do
      assert {:ok, %HtmlFragment{html: "<p>Hello</p>"}} =
               HtmlFragment.new(html: "<p>Hello</p>")
    end

    test "returns error without html field" do
      assert {:error, %Ltix.Errors.Invalid{} = error} = HtmlFragment.new([])
      assert Exception.message(error) =~ "html_fragment.html"
      assert Exception.message(error) =~ "is required"
    end

    test "succeeds with all fields" do
      assert {:ok, fragment} =
               HtmlFragment.new(
                 html: "<p>Hello</p>",
                 title: "Greeting",
                 text: "A greeting fragment",
                 extensions: %{"com.example" => "extra"}
               )

      assert fragment.html == "<p>Hello</p>"
      assert fragment.title == "Greeting"
      assert fragment.text == "A greeting fragment"
      assert fragment.extensions == %{"com.example" => "extra"}
    end
  end

  describe "to_json/1" do
    test "includes type and html field" do
      {:ok, fragment} = HtmlFragment.new(html: "<p>Hello</p>")
      json = ContentItem.to_json(fragment)

      assert json["type"] == "html"
      assert json["html"] == "<p>Hello</p>"
    end

    test "excludes nil optional fields" do
      {:ok, fragment} = HtmlFragment.new(html: "<p>Hello</p>")
      json = ContentItem.to_json(fragment)

      refute Map.has_key?(json, "title")
      refute Map.has_key?(json, "text")
    end

    test "merges extensions at top level" do
      {:ok, fragment} =
        HtmlFragment.new(
          html: "<p>Hello</p>",
          extensions: %{"com.example.extra" => "value"}
        )

      json = ContentItem.to_json(fragment)

      assert json["com.example.extra"] == "value"
      refute Map.has_key?(json, "extensions")
    end
  end
end
