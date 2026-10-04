defmodule Ltix.DeepLinking.ContentItem.LTIResourceLinkTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItem.LTIResourceLink

  describe "new/1" do
    test "returns error when custom contains non-string values" do
      assert {:error, %Ltix.Errors.Invalid{} = error} =
               LTIResourceLink.new(custom: %{"key" => 123})

      assert Exception.message(error) =~ "lti_resource_link.custom"
      assert Exception.message(error) =~ "invalid type: expected string"
    end

    test "returns error when line_item missing score_maximum" do
      assert {:error, %Ltix.Errors.Invalid{} = error} =
               LTIResourceLink.new(line_item: %{label: "Quiz"})

      assert Exception.message(error) =~ "lti_resource_link.line_item.score_maximum"
      assert Exception.message(error) =~ "is required"
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
            start_date_time: "2026-01-01T00:00:00Z",
            end_date_time: "2026-06-30T23:59:59Z"
          },
          submission: %{end_date_time: "2026-06-15T23:59:59Z"}
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
