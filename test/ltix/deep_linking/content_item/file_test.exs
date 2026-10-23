defmodule Ltix.DeepLinking.ContentItem.FileTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking.ContentItem.File, as: ContentFile

  doctest ContentFile

  describe "new/1" do
    test "rejects expires_at given as a string" do
      assert {:error, %Ltix.Errors.Invalid.InvalidField{field: :expires_at} = error} =
               ContentFile.new(
                 url: "https://example.com/doc.pdf",
                 expires_at: "2026-12-31T23:59:59Z"
               )

      assert Exception.message(error) ==
               ~s(Ltix.DeepLinking.ContentItem.File field :expires_at must be a DateTime \(got "2026-12-31T23:59:59Z"\))
    end
  end
end
