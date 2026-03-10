defmodule Ltix.GradeService.LineItemTest do
  use ExUnit.Case, async: true

  alias Ltix.GradeService.LineItem

  describe "from_json/1" do
    test "parses line item with all fields" do
      json = %{
        "id" => "https://lms.example.com/context/2923/lineitems/1",
        "label" => "Chapter 5 Test",
        "scoreMaximum" => 60,
        "resourceLinkId" => "resource-link-123",
        "resourceId" => "quiz-231",
        "tag" => "grade",
        "startDateTime" => "2018-03-06T20:05:02Z",
        "endDateTime" => "2018-04-06T22:05:03Z",
        "gradesReleased" => true
      }

      assert {:ok, %LineItem{} = item} = LineItem.from_json(json)
      assert item.id == "https://lms.example.com/context/2923/lineitems/1"
      assert item.label == "Chapter 5 Test"
      assert item.score_maximum == 60
      assert item.resource_link_id == "resource-link-123"
      assert item.resource_id == "quiz-231"
      assert item.tag == "grade"
      assert item.start_date_time == "2018-03-06T20:05:02Z"
      assert item.end_date_time == "2018-04-06T22:05:03Z"
      assert item.grades_released == true
      assert item.extensions == %{}
    end

    test "parses with missing optional fields" do
      json = %{
        "id" => "https://lms.example.com/lineitems/1",
        "label" => "Quiz 1",
        "scoreMaximum" => 100
      }

      assert {:ok, %LineItem{} = item} = LineItem.from_json(json)
      assert item.id == "https://lms.example.com/lineitems/1"
      assert item.label == "Quiz 1"
      assert item.score_maximum == 100
      assert is_nil(item.resource_link_id)
      assert is_nil(item.resource_id)
      assert is_nil(item.tag)
      assert is_nil(item.start_date_time)
      assert is_nil(item.end_date_time)
      assert is_nil(item.grades_released)
    end

    test "parses with missing label (liberal acceptance)" do
      json = %{"scoreMaximum" => 100}

      assert {:ok, %LineItem{label: nil}} = LineItem.from_json(json)
    end

    test "parses with missing scoreMaximum (liberal acceptance)" do
      json = %{"label" => "Quiz 1"}

      assert {:ok, %LineItem{score_maximum: nil}} = LineItem.from_json(json)
    end

    test "captures URL-keyed extensions" do
      json = %{
        "label" => "Quiz 1",
        "scoreMaximum" => 100,
        "https://canvas.instructure.com/lti/submission_type" => %{
          "type" => "external_tool",
          "external_tool_url" => "https://my.tool.url/launch"
        }
      }

      assert {:ok, %LineItem{} = item} = LineItem.from_json(json)

      assert item.extensions == %{
               "https://canvas.instructure.com/lti/submission_type" => %{
                 "type" => "external_tool",
                 "external_tool_url" => "https://my.tool.url/launch"
               }
             }
    end

    test "captures non-URL unrecognized keys in extensions" do
      json = %{
        "label" => "Quiz 1",
        "scoreMaximum" => 100,
        "customPlatformField" => "some-value"
      }

      assert {:ok, %LineItem{} = item} = LineItem.from_json(json)
      assert item.extensions == %{"customPlatformField" => "some-value"}
    end

    test "datetime fields are kept as strings" do
      json = %{
        "startDateTime" => "2018-03-06T20:05:02+05:30",
        "endDateTime" => "2018-04-06T22:05:03Z"
      }

      assert {:ok, %LineItem{} = item} = LineItem.from_json(json)
      assert item.start_date_time == "2018-03-06T20:05:02+05:30"
      assert item.end_date_time == "2018-04-06T22:05:03Z"
    end
  end

  describe "to_json/1" do
    test "serializes to camelCase keys" do
      item = %LineItem{
        id: "https://lms.example.com/lineitems/1",
        label: "Chapter 5 Test",
        score_maximum: 60,
        resource_link_id: "resource-link-123",
        resource_id: "quiz-231",
        tag: "grade",
        start_date_time: "2018-03-06T20:05:02Z",
        end_date_time: "2018-04-06T22:05:03Z",
        grades_released: true
      }

      assert {:ok, json} = LineItem.to_json(item)
      assert json["id"] == "https://lms.example.com/lineitems/1"
      assert json["label"] == "Chapter 5 Test"
      assert json["scoreMaximum"] == 60
      assert json["resourceLinkId"] == "resource-link-123"
      assert json["resourceId"] == "quiz-231"
      assert json["tag"] == "grade"
      assert json["startDateTime"] == "2018-03-06T20:05:02Z"
      assert json["endDateTime"] == "2018-04-06T22:05:03Z"
      assert json["gradesReleased"] == true
    end

    test "excludes nil optional fields" do
      item = %LineItem{
        id: "https://lms.example.com/lineitems/1",
        label: "Quiz 1",
        score_maximum: 100
      }

      assert {:ok, json} = LineItem.to_json(item)
      assert Map.has_key?(json, "id")
      assert Map.has_key?(json, "label")
      assert Map.has_key?(json, "scoreMaximum")
      refute Map.has_key?(json, "resourceLinkId")
      refute Map.has_key?(json, "resourceId")
      refute Map.has_key?(json, "tag")
      refute Map.has_key?(json, "startDateTime")
      refute Map.has_key?(json, "endDateTime")
      refute Map.has_key?(json, "gradesReleased")
    end

    test "validates label is present" do
      item = %LineItem{label: nil, score_maximum: 100}

      assert {:error, error} = LineItem.to_json(item)
      assert Exception.message(error) =~ "label"
    end

    test "validates label is non-blank" do
      item = %LineItem{label: "   ", score_maximum: 100}

      assert {:error, error} = LineItem.to_json(item)
      assert Exception.message(error) =~ "label"
    end

    test "validates score_maximum is present" do
      item = %LineItem{label: "Quiz 1", score_maximum: nil}

      assert {:error, error} = LineItem.to_json(item)
      assert Exception.message(error) =~ "scoreMaximum"
    end

    test "validates score_maximum is greater than 0" do
      item = %LineItem{label: "Quiz 1", score_maximum: 0}

      assert {:error, error} = LineItem.to_json(item)
      assert Exception.message(error) =~ "scoreMaximum"
    end

    test "validates score_maximum rejects negative" do
      item = %LineItem{label: "Quiz 1", score_maximum: -5}

      assert {:error, error} = LineItem.to_json(item)
      assert Exception.message(error) =~ "scoreMaximum"
    end

    test "extensions round-trip through from_json → to_json" do
      json = %{
        "label" => "Quiz 1",
        "scoreMaximum" => 100,
        "https://canvas.instructure.com/lti/submission_type" => %{
          "type" => "external_tool"
        }
      }

      assert {:ok, item} = LineItem.from_json(json)
      assert {:ok, output} = LineItem.to_json(item)

      assert output["https://canvas.instructure.com/lti/submission_type"] == %{
               "type" => "external_tool"
             }
    end

    test "non-URL extensions round-trip through from_json → to_json" do
      json = %{
        "label" => "Quiz 1",
        "scoreMaximum" => 100,
        "customPlatformField" => 42
      }

      assert {:ok, item} = LineItem.from_json(json)
      assert {:ok, output} = LineItem.to_json(item)
      assert output["customPlatformField"] == 42
    end

    test "includes id in output" do
      item = %LineItem{
        id: "https://lms.example.com/lineitems/1",
        label: "Quiz 1",
        score_maximum: 100
      }

      assert {:ok, json} = LineItem.to_json(item)
      assert json["id"] == "https://lms.example.com/lineitems/1"
    end
  end
end
