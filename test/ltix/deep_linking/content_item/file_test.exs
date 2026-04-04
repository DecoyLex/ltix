defmodule Ltix.DeepLinking.ContentItem.FileTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItem.File, as: ContentFile

  describe "new/1" do
    test "succeeds with required url field" do
      assert {:ok, %ContentFile{url: "https://example.com/doc.pdf"}} =
               ContentFile.new(url: "https://example.com/doc.pdf")
    end

    test "returns error without url field" do
      assert {:error, %Ltix.Errors.Invalid{} = error} = ContentFile.new([])
      assert Exception.message(error) =~ "file.url"
      assert Exception.message(error) =~ "is required"
    end

    test "succeeds with all fields" do
      assert {:ok, file} =
               ContentFile.new(
                 url: "https://example.com/doc.pdf",
                 title: "Course Syllabus",
                 text: "The syllabus for CS101",
                 icon: %{url: "https://example.com/icon.png"},
                 thumbnail: %{url: "https://example.com/thumb.png"},
                 media_type: "application/pdf",
                 expires_at: "2026-12-31T23:59:59Z"
               )

      assert file.media_type == "application/pdf"
      assert file.expires_at == "2026-12-31T23:59:59Z"
    end
  end

  describe "to_map/1" do
    test "includes type and url" do
      {:ok, file} = ContentFile.new(url: "https://example.com/doc.pdf")
      json = ContentItem.to_map(file)

      assert json["type"] == "file"
      assert json["url"] == "https://example.com/doc.pdf"
    end

    test "serializes camelCase top-level fields" do
      {:ok, file} =
        ContentFile.new(
          url: "https://example.com/doc.pdf",
          media_type: "application/pdf",
          expires_at: "2026-12-31T23:59:59Z"
        )

      json = ContentItem.to_map(file)

      assert json["mediaType"] == "application/pdf"
      assert json["expiresAt"] == "2026-12-31T23:59:59Z"
      refute Map.has_key?(json, "media_type")
      refute Map.has_key?(json, "expires_at")
    end

    test "excludes nil optional fields" do
      {:ok, file} = ContentFile.new(url: "https://example.com/doc.pdf")
      json = ContentItem.to_map(file)

      refute Map.has_key?(json, "title")
      refute Map.has_key?(json, "mediaType")
      refute Map.has_key?(json, "icon")
    end

    test "merges extensions at top level" do
      {:ok, file} =
        ContentFile.new(
          url: "https://example.com/doc.pdf",
          extensions: %{"com.example" => "extra"}
        )

      json = ContentItem.to_map(file)

      assert json["com.example"] == "extra"
      refute Map.has_key?(json, "extensions")
    end
  end
end
