defmodule Ltix.GradeService.ScoreTest do
  use ExUnit.Case, async: true

  alias Ltix.GradeService.Score

  doctest Score

  @valid_attrs [
    user_id: "12345",
    activity_progress: :completed,
    grading_progress: :fully_graded
  ]

  describe "new/1" do
    test "succeeds with all required fields" do
      assert {:ok, %Score{} = score} = Score.new(@valid_attrs)
      assert score.user_id == "12345"
      assert score.activity_progress == :completed
      assert score.grading_progress == :fully_graded
      assert %DateTime{} = score.timestamp
    end

    test "succeeds with score_given and score_maximum" do
      attrs = @valid_attrs ++ [score_given: 85, score_maximum: 100]

      assert {:ok, %Score{} = score} = Score.new(attrs)
      assert score.score_given == 85
      assert score.score_maximum == 100
    end

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
              started_at: "2024-01-15T09:00:00.000Z",
              submitted_at: "2024-01-15T10:00:00.000Z"
            },
            extensions: %{"https://example.com/extra" => "data"}
          ]

      assert {:ok, %Score{} = score} = Score.new(attrs)
      assert score.scoring_user_id == "instructor-1"
      assert score.comment == "Great work!"
      assert score.timestamp == ~U[2024-01-15 10:30:00.123456Z]

      assert score.submission == %{
               started_at: "2024-01-15T09:00:00.000Z",
               submitted_at: "2024-01-15T10:00:00.000Z"
             }

      assert score.extensions == %{"https://example.com/extra" => "data"}
    end

    test "auto-generates timestamp when not provided" do
      assert {:ok, %Score{} = score} = Score.new(@valid_attrs)
      assert %DateTime{} = score.timestamp
      assert score.timestamp.microsecond != {0, 0}
    end

    test "uses explicit timestamp when provided" do
      ts = ~U[2024-01-15 10:30:00.123456Z]
      attrs = @valid_attrs ++ [timestamp: ts]

      assert {:ok, %Score{timestamp: ^ts}} = Score.new(attrs)
    end

    test "rejects malformed submission timestamps, missing fractions, and missing time zones" do
      for field <- [:started_at, :submitted_at],
          value <- [
            "not a timestamp",
            "",
            "2024-01-15T09:00:00Z",
            "2024-01-15T09:00:00+05:30",
            "2024-01-15T09:00:00.123",
            "2024-02-30T09:00:00.123Z",
            "2024-01-15T25:00:00.123Z",
            "2024-01-15T09:00:00.123+24:00",
            "2024-01-15T09:00:00.Z",
            ~N[2024-01-15 09:00:00.123],
            123,
            nil
          ] do
        assert {:error, error} = Score.new(@valid_attrs ++ [submission: %{field => value}])
        assert Exception.message(error) =~ Atom.to_string(field)
      end
    end

    test "accepts each submission timestamp independently without changing its value" do
      for field <- [:started_at, :submitted_at],
          value <- [
            "2024-01-15T09:00:00.0Z",
            "2024-01-15T09:00:00.12+00",
            "2024-01-15T09:00:00.123+05:30",
            "2024-01-15T09:00:00.1234-04:00",
            "2024-01-15T09:00:00.12345+0530",
            "2024-01-15T09:00:00.123456Z",
            "2024-01-15T09:00:00.123456789Z",
            "2024-01-15T09:00:00,123Z",
            "20240115T090000.123Z"
          ] do
        submission = %{field => value}

        assert {:ok, %Score{submission: ^submission}} =
                 Score.new(@valid_attrs ++ [submission: submission])
      end

      assert {:ok, %Score{submission: submission}} = Score.new(@valid_attrs ++ [submission: %{}])
      assert submission == %{}
    end

    test "rejects submission completion before its start by instant" do
      for {started_at, submitted_at} <- [
            {"2024-01-15T09:00:00.000Z", "2024-01-15T08:59:59.999Z"},
            {"2024-01-15T09:00:00.000Z", "2024-01-15T10:00:00.000+02:00"},
            {"2024-01-15T09:00:00.123456789Z", "2024-01-15T09:00:00.123456788Z"}
          ] do
        assert {:error, error} =
                 Score.new(
                   @valid_attrs ++
                     [
                       submission: %{started_at: started_at, submitted_at: submitted_at}
                     ]
                 )

        assert Exception.message(error) =~
                 "submitted_at must be equal to or later than started_at"
      end
    end

    test "accepts equal and later submission instants across offsets and precisions" do
      for {started_at, submitted_at} <- [
            {"2024-01-15T09:00:00.0Z", "2024-01-15T09:00:00.000Z"},
            {"2024-01-15T09:00:00.123+02:00", "2024-01-15T07:00:00.123000Z"},
            {"2024-01-15T09:00:00.000+02:00", "2024-01-15T08:00:00.000Z"},
            {"2024-01-15T09:00:00.123456788Z", "2024-01-15T09:00:00.123456789Z"},
            {"2024-01-15T09:00:00.123456789Z", "2024-01-15T09:00:00.1234567890Z"}
          ] do
        submission = %{started_at: started_at, submitted_at: submitted_at}

        assert {:ok, %Score{submission: ^submission}} =
                 Score.new(@valid_attrs ++ [submission: submission])
      end
    end

    test "returns error without user_id" do
      attrs = Keyword.delete(@valid_attrs, :user_id)

      assert {:error, _} = Score.new(attrs)
    end

    test "returns error without activity_progress" do
      attrs = Keyword.delete(@valid_attrs, :activity_progress)

      assert {:error, _} = Score.new(attrs)
    end

    test "returns error without grading_progress" do
      attrs = Keyword.delete(@valid_attrs, :grading_progress)

      assert {:error, _} = Score.new(attrs)
    end

    test "returns error with score_given but no score_maximum" do
      attrs = @valid_attrs ++ [score_given: 85]

      assert {:error, error} = Score.new(attrs)
      assert Exception.message(error) =~ "required when score_given is present"
    end

    test "returns error with score_given < 0" do
      attrs = @valid_attrs ++ [score_given: -1, score_maximum: 100]

      assert {:error, error} = Score.new(attrs)
      assert Exception.message(error) =~ "score_given"
    end

    test "returns error with score_maximum <= 0" do
      attrs = @valid_attrs ++ [score_given: 50, score_maximum: 0]

      assert {:error, error} = Score.new(attrs)
      assert Exception.message(error) =~ "score_maximum"
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

      assert {:error, _} = Score.new(attrs)
    end

    test "returns error with unknown grading_progress" do
      attrs = Keyword.put(@valid_attrs, :grading_progress, :unknown_value)

      assert {:error, _} = Score.new(attrs)
    end

    test "accepts all valid activity_progress values" do
      for value <- [:initialized, :started, :in_progress, :submitted, :completed] do
        attrs = Keyword.put(@valid_attrs, :activity_progress, value)
        assert {:ok, %Score{activity_progress: ^value}} = Score.new(attrs)
      end
    end

    test "accepts all valid grading_progress values" do
      for value <- [:fully_graded, :pending, :pending_manual, :failed, :not_ready] do
        attrs = Keyword.put(@valid_attrs, :grading_progress, value)
        assert {:ok, %Score{grading_progress: ^value}} = Score.new(attrs)
      end
    end
  end

  describe "JSON encoding" do
    test "serializes enums to PascalCase strings" do
      {:ok, score} = Score.new(@valid_attrs)

      json = encode_decode!(score)
      assert json["activityProgress"] == "Completed"
      assert json["gradingProgress"] == "FullyGraded"
    end

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
        json = encode_decode!(score)
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
        json = encode_decode!(score)
        assert json["gradingProgress"] == string
      end
    end

    test "serializes timestamp with sub-second precision and Z" do
      {:ok, score} = Score.new(@valid_attrs ++ [timestamp: ~U[2024-01-15 10:30:00.123456Z]])

      json = encode_decode!(score)
      assert json["timestamp"] == "2024-01-15T10:30:00.123456Z"
    end

    test "serializes submission with camelCase keys" do
      attrs =
        @valid_attrs ++
          [
            submission: %{
              started_at: "2024-01-15T09:00:00.000Z",
              submitted_at: "2024-01-15T10:00:00.000Z"
            }
          ]

      {:ok, score} = Score.new(attrs)
      json = encode_decode!(score)

      assert json["submission"] == %{
               "startedAt" => "2024-01-15T09:00:00.000Z",
               "submittedAt" => "2024-01-15T10:00:00.000Z"
             }
    end

    test "excludes nil optional fields" do
      {:ok, score} = Score.new(@valid_attrs)

      json = encode_decode!(score)
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

    test "includes extensions" do
      attrs = @valid_attrs ++ [extensions: %{"https://example.com/extra" => %{"key" => "value"}}]
      {:ok, score} = Score.new(attrs)

      json = encode_decode!(score)
      assert json["https://example.com/extra"] == %{"key" => "value"}
    end
  end

  defp encode_decode!(score) do
    json_lib = Ltix.AppConfig.json_library!()

    score
    |> json_lib.encode!()
    |> IO.iodata_to_binary()
    |> json_lib.decode!()
  end
end
