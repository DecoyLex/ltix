defmodule Ltix.GradeService.ScoreTest do
  use ExUnit.Case, async: true

  import Ltix.Test.GradeServiceHelper

  alias Ltix.Errors.Invalid
  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.GradeService.Score

  doctest Score

  @valid_attrs [
    user_id: "12345",
    activity_progress: :completed,
    grading_progress: :fully_graded
  ]

  describe "new/1" do
    test "succeeds with all optional fields" do
      attrs =
        @valid_attrs ++
          [
            score_given: 85,
            score_maximum: 100,
            scoring_user_id: "instructor-1",
            comment: "Great work!",
            timestamp: ~U[2024-01-15 10:30:00.123456Z],
            submission: %{
              started_at: ~U[2024-01-15 09:00:00.000Z],
              submitted_at: ~U[2024-01-15 10:00:00.000Z]
            }
          ]

      assert {:ok, %Score{} = score} = Score.new(attrs)
      assert score.scoring_user_id == "instructor-1"
      assert score.comment == "Great work!"
      assert score.timestamp == ~U[2024-01-15 10:30:00.123456Z]

      assert score.submission == %{
               started_at: ~U[2024-01-15 09:00:00.000Z],
               submitted_at: ~U[2024-01-15 10:00:00.000Z]
             }
    end

    test "auto-generates timestamp when not provided" do
      assert {:ok, %Score{} = score} = Score.new(@valid_attrs)
      assert %DateTime{} = score.timestamp
      assert {_microsecond, 6} = score.timestamp.microsecond
    end

    test "accepts nil for optional fields" do
      attrs =
        @valid_attrs ++ [score_given: nil, score_maximum: nil, comment: nil, submission: nil]

      assert {:ok, %Score{score_given: nil, score_maximum: nil, comment: nil, submission: nil}} =
               Score.new(attrs)
    end

    test "rejects extensions" do
      assert {:error, %InvalidField{field: :extensions, reason: :unknown}} =
               Score.new(@valid_attrs ++ [extensions: %{"https://example.com/extra" => "data"}])
    end

    test "accepts nil for a submission time" do
      submitted_at = ~U[2024-01-15 10:00:00.000Z]

      assert {:ok, %Score{submission: submission} = score} =
               Score.new(
                 @valid_attrs ++ [submission: [started_at: nil, submitted_at: submitted_at]]
               )

      assert submission == %{submitted_at: submitted_at}

      assert posted_json(score)["submission"] == %{
               "submittedAt" => "2024-01-15T10:00:00.000000Z"
             }
    end

    test "requires a timestamp given nil" do
      assert {:error, %InvalidField{field: :timestamp, reason: :required}} =
               Score.new(@valid_attrs ++ [timestamp: nil])
    end

    test "requires a required field given nil" do
      for field <- Keyword.keys(@valid_attrs) do
        assert {:error, %InvalidField{field: ^field, reason: :required}} =
                 Score.new(Keyword.put(@valid_attrs, field, nil))
      end
    end

    test "rejects an unknown field given nil" do
      assert {:error, %InvalidField{field: :score, reason: :unknown}} =
               Score.new(@valid_attrs ++ [score: nil])
    end

    test "accepts submission as a keyword list or a map" do
      started_at = ~U[2024-01-15 09:00:00.000Z]
      submitted_at = ~U[2024-01-15 10:00:00.000Z]

      for submission <- [
            [started_at: started_at, submitted_at: submitted_at],
            %{started_at: started_at, submitted_at: submitted_at}
          ] do
        assert {:ok, %Score{submission: %{started_at: ^started_at, submitted_at: ^submitted_at}}} =
                 Score.new(@valid_attrs ++ [submission: submission])
      end

      assert {:ok, %Score{submission: %{}}} = Score.new(@valid_attrs ++ [submission: []])
    end

    test "rejects submission times that are not DateTime structs" do
      for field <- [:started_at, :submitted_at] do
        value = "2024-01-15T09:00:00.123Z"

        assert {:error, %InvalidField{field: [:submission, ^field], value: ^value}} =
                 Score.new(@valid_attrs ++ [submission: %{field => value}])
      end
    end

    test "rejects a timestamp that is not a DateTime struct" do
      assert {:error, %InvalidField{field: :timestamp}} =
               Score.new(@valid_attrs ++ [timestamp: "2024-01-15T10:30:00.123Z"])
    end

    test "rejects unknown fields" do
      assert {:error, %InvalidField{struct: Score, field: :score, reason: :unknown}} =
               Score.new(@valid_attrs ++ [score: 1])

      assert {:error, %InvalidField{field: [:submission, :ended_at], reason: :unknown}} =
               Score.new(@valid_attrs ++ [submission: [ended_at: ~U[2024-01-15 09:00:00Z]]])
    end

    test "returns every invalid field at once" do
      assert {:error, %Invalid{errors: errors}} =
               Score.new(user_id: 1, activity_progress: :done, grading_progress: :fully_graded)

      assert Enum.sort(Enum.map(errors, & &1.field)) == [:activity_progress, :user_id]
    end

    test "rejects submission completion before its start" do
      submission = %{
        started_at: ~U[2024-01-15 09:00:00.000Z],
        submitted_at: ~U[2024-01-15 08:59:59.999Z]
      }

      assert {:error,
              %InvalidField{
                field: [:submission, :submitted_at],
                value: ~U[2024-01-15 08:59:59.999Z]
              }} =
               Score.new(@valid_attrs ++ [submission: submission])
    end

    test "accepts equal submission instants in different offsets" do
      started_at = %{
        ~U[2024-01-15 09:00:00.000Z]
        | utc_offset: 7200,
          time_zone: "Europe/Athens",
          zone_abbr: "EET"
      }

      submission = %{started_at: started_at, submitted_at: ~U[2024-01-15 07:00:00.000Z]}
      assert {:ok, %Score{}} = Score.new(@valid_attrs ++ [submission: submission])
    end

    test "returns error with score_given but no score_maximum" do
      attrs = @valid_attrs ++ [score_given: 85]

      assert {:error, %InvalidField{field: :score_maximum, value: nil}} = Score.new(attrs)
    end

    test "returns error with score_given < 0" do
      attrs = @valid_attrs ++ [score_given: -1, score_maximum: 100]

      assert {:error, %InvalidField{field: :score_given, value: -1}} = Score.new(attrs)
    end

    test "returns error with score_maximum <= 0" do
      attrs = @valid_attrs ++ [score_given: 50, score_maximum: 0]

      assert {:error, %InvalidField{field: :score_maximum, value: 0}} = Score.new(attrs)
    end

    test "succeeds with score_given > score_maximum (extra credit)" do
      attrs = @valid_attrs ++ [score_given: 110, score_maximum: 100]

      assert {:ok, %Score{score_given: 110, score_maximum: 100}} = Score.new(attrs)
    end

    test "succeeds with score_given of 0" do
      attrs = @valid_attrs ++ [score_given: 0, score_maximum: 100]

      assert {:ok, %Score{score_given: 0}} = Score.new(attrs)
    end

    test "returns error with unknown activity_progress" do
      attrs = Keyword.put(@valid_attrs, :activity_progress, :unknown_value)

      assert {:error, %InvalidField{field: :activity_progress, value: :unknown_value}} =
               Score.new(attrs)
    end

    test "returns error with unknown grading_progress" do
      attrs = Keyword.put(@valid_attrs, :grading_progress, :unknown_value)

      assert {:error, %InvalidField{field: :grading_progress, value: :unknown_value}} =
               Score.new(attrs)
    end
  end

  describe "new!/1" do
    test "returns the score or raises the error" do
      assert %Score{user_id: "12345"} = Score.new!(@valid_attrs)
      assert_raise InvalidField, fn -> Score.new!(Keyword.delete(@valid_attrs, :user_id)) end
    end
  end

  describe "posting a score" do
    test "serializes all activity_progress values correctly" do
      expected = %{
        initialized: "Initialized",
        started: "Started",
        in_progress: "InProgress",
        submitted: "Submitted",
        completed: "Completed"
      }

      for {atom, string} <- expected do
        attrs = Keyword.put(@valid_attrs, :activity_progress, atom)
        {:ok, score} = Score.new(attrs)
        json = posted_json(score)
        assert json["activityProgress"] == string
      end
    end

    test "serializes all grading_progress values correctly" do
      expected = %{
        fully_graded: "FullyGraded",
        pending: "Pending",
        pending_manual: "PendingManual",
        failed: "Failed",
        not_ready: "NotReady"
      }

      for {atom, string} <- expected do
        attrs = Keyword.put(@valid_attrs, :grading_progress, atom)
        {:ok, score} = Score.new(attrs)
        json = posted_json(score)
        assert json["gradingProgress"] == string
      end
    end

    test "excludes nil optional fields" do
      {:ok, score} = Score.new(@valid_attrs)

      json = posted_json(score)
      assert Map.has_key?(json, "userId")
      assert Map.has_key?(json, "activityProgress")
      assert Map.has_key?(json, "gradingProgress")
      assert Map.has_key?(json, "timestamp")
      refute Map.has_key?(json, "scoreGiven")
      refute Map.has_key?(json, "scoreMaximum")
      refute Map.has_key?(json, "scoringUserId")
      refute Map.has_key?(json, "comment")
      refute Map.has_key?(json, "submission")
    end
  end

  # Returns the JSON `post_score/3` sends for `score`.
  defp posted_json(score) do
    stub_requests(fn "POST", _body -> nil end)
    :ok = Ltix.GradeService.post_score(create_client(), score)
    assert_received {"POST", json}
    json
  end
end
