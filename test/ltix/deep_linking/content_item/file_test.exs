defmodule Ltix.DeepLinking.ContentItem.FileTest do
  use ExUnit.Case, async: true

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
end
