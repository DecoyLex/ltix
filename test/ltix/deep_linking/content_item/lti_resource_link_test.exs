defmodule Ltix.DeepLinking.ContentItem.LTIResourceLinkTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItem.LTIResourceLink
  alias Ltix.GradeService.LineItem

  doctest LTIResourceLink

  describe "new/1" do
    test "accepts a map" do
      assert {:ok, %LTIResourceLink{title: "Quiz", line_item: %{score_maximum: 10}}} =
               LTIResourceLink.new(%{title: "Quiz", line_item: %{score_maximum: 10}})
    end

    test "rejects an iframe src, which only links carry" do
      assert {:error,
              %Ltix.Errors.Invalid.InvalidField{
                field: [:iframe, :src],
                value: "https://tool.example.com/embed"
              }} =
               LTIResourceLink.new(iframe: [src: "https://tool.example.com/embed", width: 640])
    end

    test "accepts custom as a keyword list or a map with atom or string keys" do
      expected = %{"chapter" => "12", "page" => "42"}

      assert {:ok, %LTIResourceLink{custom: ^expected}} =
               LTIResourceLink.new(custom: [chapter: "12", page: "42"])

      assert {:ok, %LTIResourceLink{custom: ^expected}} =
               LTIResourceLink.new(custom: %{:chapter => "12", "page" => "42"})
    end

    test "names the problem with an invalid custom option" do
      assert {:error, %Ltix.Errors.Invalid.InvalidField{field: :custom} = error} =
               LTIResourceLink.new(custom: "chapter=12")

      assert Exception.message(error) =~ "expected a map or keyword list"

      assert {:error, %Ltix.Errors.Invalid.InvalidField{field: [:custom, 12]} = error} =
               LTIResourceLink.new(custom: %{12 => "chapter"})

      assert Exception.message(error) =~ "invalid key: expected a string or atom"
    end

    test "returns error when custom contains non-string values" do
      assert {:error,
              %Ltix.Errors.Invalid.InvalidField{
                field: [:custom, "key"],
                value: 123
              }} = LTIResourceLink.new(custom: %{"key" => 123})
    end

    test "returns every invalid field together" do
      assert {:error, %Ltix.Errors.Invalid{errors: errors}} =
               LTIResourceLink.new(custom: %{"key" => 123}, line_item: %{score_maximum: 0})

      assert Enum.sort(Enum.map(errors, & &1.field)) ==
               [[:custom, "key"], [:line_item, :score_maximum]]
    end

    test "returns error when line_item missing score_maximum" do
      assert {:error, %Ltix.Errors.Invalid.InvalidField{} = error} =
               LTIResourceLink.new(line_item: %{label: "Quiz"})

      assert Exception.message(error) =~ "[:line_item, :score_maximum]"
      assert Exception.message(error) =~ "is required"
    end

    test "accepts a grade service line item" do
      line_item = %LineItem{label: "Quiz 1", score_maximum: 10, tag: "grade"}

      assert {:ok, link} = LTIResourceLink.new(line_item: line_item)

      assert ContentItem.to_map(link)["lineItem"] == %{
               "label" => "Quiz 1",
               "scoreMaximum" => 10,
               "tag" => "grade"
             }
    end

    test "names the fields of a grade service line item that deep linking can't carry" do
      line_item = %LineItem{
        id: "https://lms.example.com/lineitems/1",
        label: "Quiz 1",
        score_maximum: 10,
        resource_link_id: "link-1",
        extensions: %{"https://vendor.example.com/weight" => 2}
      }

      assert {:error, %Ltix.Errors.Invalid{errors: errors}} =
               LTIResourceLink.new(line_item: line_item)

      assert Enum.sort(Enum.map(errors, & &1.field)) == [
               [:line_item, :extensions],
               [:line_item, :id],
               [:line_item, :resource_link_id]
             ]
    end

    test "rejects line item labels and maximum scores the grade service rejects" do
      assert {:error,
              %Ltix.Errors.Invalid.InvalidField{
                field: [:line_item, :label],
                value: " ",
                reason: "must not be blank"
              }} = LTIResourceLink.new(line_item: [label: " ", score_maximum: 10])

      assert {:error,
              %Ltix.Errors.Invalid.InvalidField{field: [:line_item, :score_maximum], value: 0}} =
               LTIResourceLink.new(line_item: [label: "Quiz", score_maximum: 0])
    end

    test "rejects time windows given as strings" do
      assert {:error,
              %Ltix.Errors.Invalid.InvalidField{
                field: [:submission, :end_date_time],
                value: "2026-06-15T23:59:59Z"
              }} =
               LTIResourceLink.new(submission: [end_date_time: "2026-06-15T23:59:59Z"])
    end
  end

  describe "new!/1" do
    test "raises the error new/1 returns" do
      assert_raise Ltix.Errors.Invalid.InvalidField, ~r/field :title /, fn ->
        LTIResourceLink.new!(title: 1)
      end
    end
  end

  describe "to_map/1" do
    test "serializes lineItem with camelCase keys" do
      {:ok, link} =
        LTIResourceLink.new(
          line_item: %{
            score_maximum: 100,
            label: "Quiz 1",
            resource_id: "res-1",
            tag: "quiz",
            grades_released: true
          }
        )

      json = ContentItem.to_map(link)

      assert json["lineItem"] == %{
               "scoreMaximum" => 100,
               "label" => "Quiz 1",
               "resourceId" => "res-1",
               "tag" => "quiz",
               "gradesReleased" => true
             }
    end

    test "serializes available and submission with camelCase keys" do
      {:ok, link} =
        LTIResourceLink.new(
          available: %{
            start_date_time: ~U[2026-01-01 00:00:00Z],
            end_date_time: ~U[2026-06-30 23:59:59Z]
          },
          submission: %{end_date_time: ~U[2026-06-15 23:59:59Z]}
        )

      json = ContentItem.to_map(link)

      assert json["available"] == %{
               "startDateTime" => "2026-01-01T00:00:00Z",
               "endDateTime" => "2026-06-30T23:59:59Z"
             }

      assert json["submission"] == %{"endDateTime" => "2026-06-15T23:59:59Z"}
    end

    test "serializes custom map as-is" do
      {:ok, link} = LTIResourceLink.new(custom: %{"course_id" => "12"})
      json = ContentItem.to_map(link)

      assert json["custom"] == %{"course_id" => "12"}
    end
  end
end
