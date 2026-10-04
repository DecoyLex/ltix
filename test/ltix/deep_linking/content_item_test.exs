defmodule Ltix.DeepLinking.ContentItemTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItem.File
  alias Ltix.DeepLinking.ContentItem.HTMLFragment
  alias Ltix.DeepLinking.ContentItem.Image
  alias Ltix.DeepLinking.ContentItem.Link
  alias Ltix.DeepLinking.ContentItem.LTIResourceLink
  alias Ltix.Errors.Invalid.InvalidField

  doctest Ltix.DeepLinking.ContentItem

  @items [
    {File, [url: "https://example.com/syllabus.pdf"]},
    {HTMLFragment, [html: "<p>Hello</p>"]},
    {Image, [url: "https://example.com/diagram.png"]},
    {Link, [url: "https://example.com"]},
    {LTIResourceLink, [url: "https://tool.example.com/quizzes/7"]}
  ]

  describe "new/1 with nil fields" do
    test "sets an optional field given nil to nil and leaves it out of the map" do
      for {module, required} <- @items do
        assert {:ok, %{title: nil} = item} = module.new([{:title, nil} | required])
        refute Map.has_key?(ContentItem.to_map(item), "title")
      end
    end

    test "sets extensions given nil to nil" do
      for {module, required} <- @items do
        assert {:ok, %{extensions: nil} = item} = module.new([{:extensions, nil} | required])
        assert ContentItem.to_map(item) == ContentItem.to_map(module.new!(required))
      end
    end

    test "requires a required field given nil" do
      for {module, field} <- [{File, :url}, {HTMLFragment, :html}, {Image, :url}, {Link, :url}] do
        assert {:error, %InvalidField{struct: ^module, field: ^field, reason: :required}} =
                 module.new([{field, nil}])
      end
    end

    test "rejects an unknown field given nil" do
      for {module, required} <- @items do
        assert {:error, %InvalidField{field: :titel, reason: :unknown}} =
                 module.new([{:titel, nil} | required])
      end
    end
  end
end
