defmodule Ltix.DeepLinking.ContentItemTypeTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking.ContentItem.File
  alias Ltix.DeepLinking.ContentItem.HTMLFragment
  alias Ltix.DeepLinking.ContentItem.Image
  alias Ltix.DeepLinking.ContentItem.Link
  alias Ltix.DeepLinking.ContentItem.LTIResourceLink
  alias Ltix.DeepLinking.ContentItemType
  alias Ltix.Errors.Invalid.InvalidField

  doctest ContentItemType
  doctest ContentItemType.Fields
  doctest Ltix.Property

  @items [
    {File, [url: "https://example.com/syllabus.pdf"]},
    {HTMLFragment, [html: "<p>Hello</p>"]},
    {Image, [url: "https://example.com/diagram.png"]},
    {Link, [url: "https://example.com"]},
    {LTIResourceLink, [url: "https://tool.example.com/quizzes/7"]},
    {TestPlugins.Poll, [question: "Ready?"]}
  ]

  describe "new/1" do
    test "sets an optional field given nil to nil" do
      for {module, required} <- @items do
        assert {:ok, %{title: nil}} = module.new([{:title, nil} | required])
      end
    end

    test "rejects a missing required field" do
      for {module, field} <- [
            {File, :url},
            {HTMLFragment, :html},
            {Image, :url},
            {Link, :url},
            {TestPlugins.Poll, :question}
          ] do
        assert {:error, %InvalidField{struct: ^module, field: ^field, reason: :required}} =
                 module.new([])

        assert {:error, %InvalidField{struct: ^module, field: ^field, reason: :required}} =
                 module.new([{field, nil}])
      end
    end

    test "rejects an unknown field" do
      for {module, required} <- @items do
        assert {:error, %InvalidField{field: :titel, reason: :unknown}} =
                 module.new([{:titel, "Docs"} | required])
      end
    end

    test "rejects extensions" do
      for {module, required} <- @items do
        assert {:error, %InvalidField{field: :extensions, reason: :unknown}} =
                 module.new([{:extensions, %{"https://vendor.example.com/x" => 1}} | required])
      end
    end

    test "accepts a map with nested maps or keyword lists" do
      for window <- [%{target_name: "docs"}, [target_name: "docs"]] do
        assert {:ok, %Link{url: "https://example.com", window: %{target_name: "docs"}}} =
                 Link.new(%{url: "https://example.com", window: window})
      end
    end
  end

  describe "new!/1" do
    test "raises the error new/1 returns" do
      for {module, _required} <- @items, module != LTIResourceLink do
        assert_raise InvalidField, fn -> module.new!([]) end
      end
    end
  end

  describe "generated docs" do
    test "list the fields in order under a Fields heading, without internal fields" do
      for {module, _required} <- @items, module != TestPlugins.Poll do
        {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(module)
        [_intro, listed] = String.split(moduledoc, "## Fields")

        documented = Regex.scan(~r/^\* `:(\w+)`/m, listed, capture: :all_but_first)
        fields = Enum.map(ContentItemType.fields(module), fn {field, _schema} -> field end)

        assert Enum.map(documented, fn [field] -> String.to_existing_atom(field) end) == fields
        refute moduledoc =~ "## Options"
        refute listed =~ "extensions"
        refute listed =~ "unrecognized"
      end
    end

    test "respect a moduledoc of false" do
      assert {:docs_v1, _, _, _, :hidden, _, _} = Code.fetch_docs(TestPlugins.Poll)
    end
  end
end
