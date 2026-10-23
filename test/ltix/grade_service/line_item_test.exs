defmodule Ltix.GradeService.LineItemTest do
  use ExUnit.Case, async: true

  import GradeServiceFixtures

  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.GradeService
  alias Ltix.GradeService.LineItem

  doctest LineItem

  # Returns the line item `get_line_item/2` parses from `json`.
  defp read(json) do
    stub_requests(fn "GET", nil -> json end)
    {:ok, item} = GradeService.get_line_item(create_client())
    item
  end

  # Returns the JSON `update_line_item/3` sends for `item`.
  defp sent(item) do
    stub_requests(fn "PUT", body -> body end)
    {:ok, _item} = GradeService.update_line_item(create_client(), %{item | id: line_item_url()})
    assert_received {"PUT", json}
    json
  end

  describe "reading a line item" do
    test "parses every field" do
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

      assert read(json) == %LineItem{
               id: "https://lms.example.com/context/2923/lineitems/1",
               label: "Chapter 5 Test",
               score_maximum: 60,
               resource_link_id: "resource-link-123",
               resource_id: "quiz-231",
               tag: "grade",
               start_date_time: ~U[2018-03-06 20:05:02Z],
               end_date_time: ~U[2018-04-06 22:05:03Z],
               grades_released: true
             }
    end

    test "leaves missing fields nil" do
      assert read(%{"id" => line_item_url(), "label" => "Quiz 1", "scoreMaximum" => 100}) ==
               %LineItem{id: line_item_url(), label: "Quiz 1", score_maximum: 100}
    end

    test "parses date times into UTC DateTime structs" do
      item =
        read(%{
          "startDateTime" => "2018-03-06T20:05:02+05:30",
          "endDateTime" => "2018-04-06T22:05:03.250Z"
        })

      assert item.start_date_time == ~U[2018-03-06 14:35:02Z]
      assert item.end_date_time == ~U[2018-04-06 22:05:03.250Z]
    end

    test "treats blank date times as absent" do
      assert %LineItem{start_date_time: nil, end_date_time: nil} =
               read(%{"startDateTime" => "", "endDateTime" => nil})
    end
  end

  describe "sending a line item" do
    test "sends every field with camelCase keys" do
      item = %LineItem{
        label: "Chapter 5 Test",
        score_maximum: 60,
        resource_link_id: "resource-link-123",
        resource_id: "quiz-231",
        tag: "grade",
        start_date_time: ~U[2018-03-06 20:05:02Z],
        end_date_time: ~U[2018-04-06 22:05:03Z],
        grades_released: true
      }

      assert sent(item) == %{
               "id" => line_item_url(),
               "label" => "Chapter 5 Test",
               "scoreMaximum" => 60,
               "resourceLinkId" => "resource-link-123",
               "resourceId" => "quiz-231",
               "tag" => "grade",
               "startDateTime" => "2018-03-06T20:05:02Z",
               "endDateTime" => "2018-04-06T22:05:03Z",
               "gradesReleased" => true
             }
    end

    test "sends date times in UTC" do
      start = %{
        ~U[2018-03-06 20:05:02Z]
        | utc_offset: 19_800,
          time_zone: "Asia/Kolkata",
          zone_abbr: "IST"
      }

      json = sent(%LineItem{label: "Quiz", score_maximum: 1, start_date_time: start})

      assert json["startDateTime"] == "2018-03-06T14:35:02Z"
    end

    test "leaves out nil fields" do
      assert sent(%LineItem{label: "Quiz 1", score_maximum: 100}) ==
               %{"id" => line_item_url(), "label" => "Quiz 1", "scoreMaximum" => 100}
    end
  end

  describe "validate/1" do
    test "validates label is non-blank" do
      item = %LineItem{label: "   ", score_maximum: 100}

      assert {:error, %InvalidField{struct: LineItem, field: :label, reason: "must not be blank"}} =
               LineItem.validate(item)
    end

    test "validates score_maximum is present" do
      item = %LineItem{label: "Quiz 1", score_maximum: nil}

      assert {:error, %InvalidField{field: :score_maximum, reason: :required}} =
               LineItem.validate(item)
    end

    test "validates date times are DateTime structs" do
      item = %LineItem{label: "Quiz 1", score_maximum: 100, end_date_time: "2018-04-06T22:05:03Z"}

      assert {:error, %InvalidField{field: :end_date_time}} = LineItem.validate(item)
    end

    test "returns every invalid field at once" do
      item = %LineItem{label: nil, score_maximum: 0}

      assert {:error, %Ltix.Errors.Invalid{errors: errors}} = LineItem.validate(item)
      assert Enum.sort(Enum.map(errors, & &1.field)) == [:label, :score_maximum]
    end
  end
end
