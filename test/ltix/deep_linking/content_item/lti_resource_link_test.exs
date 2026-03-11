defmodule Ltix.DeepLinking.ContentItem.LtiResourceLinkTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItem.LtiResourceLink

  describe "new/1" do
    test "succeeds with no args (all optional)" do
      assert {:ok, %LtiResourceLink{}} = LtiResourceLink.new([])
    end

    test "succeeds with url, title, and custom" do
      assert {:ok, link} =
               LtiResourceLink.new(
                 url: "https://tool.example.com/activity/1",
                 title: "Activity 1",
                 custom: %{"chapter" => "12", "page" => "42"}
               )

      assert link.url == "https://tool.example.com/activity/1"
      assert link.title == "Activity 1"
      assert link.custom == %{"chapter" => "12", "page" => "42"}
    end

    test "returns error when custom contains non-string values" do
      assert {:error, %Ltix.Errors.Invalid{} = error} =
               LtiResourceLink.new(custom: %{"key" => 123})

      assert Exception.message(error) =~ "lti_resource_link.custom"
      assert Exception.message(error) =~ "invalid type: expected string"
    end

    test "validates line_item score_maximum is positive" do
      assert {:error, %Ltix.Errors.Invalid{} = error} =
               LtiResourceLink.new(line_item: %{score_maximum: 0})

      assert Exception.message(error) =~ "lti_resource_link.line_item.score_maximum"
      assert Exception.message(error) =~ "must be greater than 0"

      assert {:error, %Ltix.Errors.Invalid{}} =
               LtiResourceLink.new(line_item: %{score_maximum: -1})
    end

    test "returns error when line_item missing score_maximum" do
      assert {:error, %Ltix.Errors.Invalid{} = error} =
               LtiResourceLink.new(line_item: %{label: "Quiz"})

      assert Exception.message(error) =~ "lti_resource_link.line_item.score_maximum"
      assert Exception.message(error) =~ "is required"
    end

    test "succeeds with valid line_item" do
      assert {:ok, link} =
               LtiResourceLink.new(
                 line_item: %{
                   score_maximum: 100,
                   label: "Final Exam",
                   resource_id: "res-1",
                   tag: "exam",
                   grades_released: true
                 }
               )

      assert link.line_item.score_maximum == 100
      assert link.line_item.label == "Final Exam"
      assert link.line_item.grades_released == true
    end

    test "succeeds with available and submission time windows" do
      assert {:ok, link} =
               LtiResourceLink.new(
                 available: %{
                   start_date_time: "2026-01-01T00:00:00Z",
                   end_date_time: "2026-06-30T23:59:59Z"
                 },
                 submission: %{end_date_time: "2026-06-15T23:59:59Z"}
               )

      assert link.available.start_date_time == "2026-01-01T00:00:00Z"
      assert link.submission.end_date_time == "2026-06-15T23:59:59Z"
    end
  end

  describe "to_json/1" do
    test "includes type" do
      {:ok, link} = LtiResourceLink.new([])
      json = ContentItem.to_json(link)

      assert json["type"] == "ltiResourceLink"
    end

    test "serializes lineItem with camelCase keys" do
      {:ok, link} =
        LtiResourceLink.new(
          line_item: %{
            score_maximum: 100,
            label: "Quiz 1",
            resource_id: "res-1",
            tag: "quiz",
            grades_released: true
          }
        )

      json = ContentItem.to_json(link)

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
        LtiResourceLink.new(
          available: %{
            start_date_time: "2026-01-01T00:00:00Z",
            end_date_time: "2026-06-30T23:59:59Z"
          },
          submission: %{end_date_time: "2026-06-15T23:59:59Z"}
        )

      json = ContentItem.to_json(link)

      assert json["available"] == %{
               "startDateTime" => "2026-01-01T00:00:00Z",
               "endDateTime" => "2026-06-30T23:59:59Z"
             }

      assert json["submission"] == %{"endDateTime" => "2026-06-15T23:59:59Z"}
    end

    test "serializes custom map as-is" do
      {:ok, link} = LtiResourceLink.new(custom: %{"chapter" => "12"})
      json = ContentItem.to_json(link)

      assert json["custom"] == %{"chapter" => "12"}
    end

    test "excludes nil optional fields" do
      {:ok, link} = LtiResourceLink.new([])
      json = ContentItem.to_json(link)

      refute Map.has_key?(json, "url")
      refute Map.has_key?(json, "title")
      refute Map.has_key?(json, "lineItem")
      refute Map.has_key?(json, "custom")
      refute Map.has_key?(json, "available")
    end

    test "with only line_item (no url) produces valid output" do
      {:ok, link} = LtiResourceLink.new(line_item: %{score_maximum: 50})
      json = ContentItem.to_json(link)

      assert json["type"] == "ltiResourceLink"
      assert json["lineItem"] == %{"scoreMaximum" => 50}
      refute Map.has_key?(json, "url")
    end

    test "merges extensions at top level" do
      {:ok, link} =
        LtiResourceLink.new(extensions: %{"com.example" => "extra"})

      json = ContentItem.to_json(link)

      assert json["com.example"] == "extra"
      refute Map.has_key?(json, "extensions")
    end
  end
end
