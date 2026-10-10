defmodule Ltix.DeepLinking.ContentItem.FileTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItem.File, as: ContentFile

  doctest ContentFile

  describe "new/1" do
    test "rejects expires_at given as a string" do
      assert {:error, %Ltix.Errors.Invalid.InvalidField{field: :expires_at}} =
               ContentFile.new(
                 url: "https://example.com/doc.pdf",
                 expires_at: "2026-12-31T23:59:59Z"
               )
    end
  end

  describe "new!/1" do
    test "raises the error new/1 returns" do
      assert_raise Ltix.Errors.Invalid.InvalidField, ~r/field :url /, fn ->
        ContentFile.new!([])
      end
    end
  end

  describe "to_map/1" do
    test "serializes camelCase top-level fields" do
      {:ok, file} =
        ContentFile.new(
          url: "https://example.com/doc.pdf",
          media_type: "application/pdf",
          expires_at: ~U[2026-12-31 23:59:59Z]
        )

      json = ContentItem.to_map(file)

      assert json["mediaType"] == "application/pdf"
      assert json["expiresAt"] == "2026-12-31T23:59:59Z"
      refute Map.has_key?(json, "media_type")
      refute Map.has_key?(json, "expires_at")
    end
  end
end
