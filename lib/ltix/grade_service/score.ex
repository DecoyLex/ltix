defmodule Ltix.GradeService.Score do
  @moduledoc """
  A score to post to the platform's gradebook.

  Scores are write-only — the tool constructs them and POSTs to the
  platform. Use `new/1` to build a validated score, then pass it to
  `Ltix.GradeService.post_score/3`.

  The `grading_progress` must be `:fully_graded` for the platform to
  record the score as a final grade. Other values are considered
  partial and the platform may ignore them.

  ## Examples

      {:ok, score} = Ltix.GradeService.Score.new(
        user_id: "12345",
        score_given: 85,
        score_maximum: 100,
        activity_progress: :completed,
        grading_progress: :fully_graded
      )

      score.score_given
      #=> 85
  """

  # [AGS §3.4.7](https://www.imsglobal.org/spec/lti-ags/v2p0/#activityprogress)
  @activity_progress_values [:initialized, :started, :in_progress, :submitted, :completed]

  # [AGS §3.4.8](https://www.imsglobal.org/spec/lti-ags/v2p0/#gradingprogress)
  @grading_progress_values [:fully_graded, :pending, :pending_manual, :failed, :not_ready]

  @schema Zoi.struct(
            __MODULE__,
            %{
              user_id: Zoi.string(description: "LTI user ID of the score recipient."),
              activity_progress:
                Zoi.enum(@activity_progress_values,
                  description: "User's progress toward completing the activity."
                ),
              grading_progress:
                Zoi.enum(@grading_progress_values,
                  description:
                    "Status of the grading process. Must be `:fully_graded` for final scores."
                ),
              timestamp:
                Zoi.struct(DateTime,
                  description: "When the score was set. Auto-generated if not provided."
                )
                |> Zoi.optional(),
              score_given:
                Zoi.number(
                  description:
                    "Score value (must be >= 0). Requires `score_maximum` when present."
                )
                |> Zoi.non_negative()
                |> Zoi.optional(),
              score_maximum:
                Zoi.number(
                  description:
                    "Maximum possible score (must be > 0). Required when `score_given` is present."
                )
                |> Zoi.positive()
                |> Zoi.optional(),
              scoring_user_id:
                Zoi.string(description: "LTI user ID of the person who provided the score.")
                |> Zoi.optional(),
              comment:
                Zoi.string(
                  description: "Plain text comment visible to both student and instructor."
                )
                |> Zoi.optional(),
              submission:
                Zoi.map(Zoi.atom(), Zoi.string(),
                  description:
                    "Submission metadata with `:started_at` and `:submitted_at` ISO 8601 timestamps."
                )
                |> Zoi.optional(),
              extensions:
                Zoi.map(Zoi.string(), Zoi.any(),
                  description: "Extension properties keyed by fully qualified URLs."
                )
                |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @activity_progress_to_json %{
    initialized: "Initialized",
    started: "Started",
    in_progress: "InProgress",
    submitted: "Submitted",
    completed: "Completed"
  }

  @grading_progress_to_json %{
    fully_graded: "FullyGraded",
    pending: "Pending",
    pending_manual: "PendingManual",
    failed: "Failed",
    not_ready: "NotReady"
  }

  @doc """
  Build a validated score from keyword options.

  Auto-generates a `timestamp` with microsecond precision if not provided.

  ## Options

  #{Zoi.describe(@schema)}

  ## Examples

      iex> {:ok, score} = Ltix.GradeService.Score.new(user_id: "u1", activity_progress: :completed, grading_progress: :fully_graded)
      iex> score.user_id
      "u1"
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(opts) do
    case Zoi.parse(@schema, Map.new(opts)) do
      {:ok, %__MODULE__{} = score} ->
        score = %{score | timestamp: score.timestamp || DateTime.utc_now()}

        with :ok <- validate_score_pair(score.score_given, score.score_maximum) do
          {:ok, score}
        end

      {:error, errors} ->
        {:error, Zoi.ParseError.exception(errors: errors)}
    end
  end

  @doc """
  Serialize a score to a JSON-compatible map.

  ## Examples

      iex> {:ok, score} = Ltix.GradeService.Score.new(user_id: "u1", activity_progress: :completed, grading_progress: :fully_graded, timestamp: ~U[2024-01-15 10:30:00.123456Z])
      iex> json = Ltix.GradeService.Score.to_json(score)
      iex> json["userId"]
      "u1"
  """
  @spec to_json(t()) :: map()
  def to_json(%__MODULE__{} = score) do
    json = %{
      "userId" => score.user_id,
      "activityProgress" => Map.fetch!(@activity_progress_to_json, score.activity_progress),
      "gradingProgress" => Map.fetch!(@grading_progress_to_json, score.grading_progress),
      "timestamp" => DateTime.to_iso8601(score.timestamp)
    }

    json
    |> maybe_put("scoreGiven", score.score_given)
    |> maybe_put("scoreMaximum", score.score_maximum)
    |> maybe_put("scoringUserId", score.scoring_user_id)
    |> maybe_put("comment", score.comment)
    |> maybe_put_submission(score.submission)
    |> Map.merge(score.extensions)
  end

  # --- Private ---

  defp validate_score_pair(nil, _), do: :ok

  defp validate_score_pair(_score_given, nil) do
    {:error, ArgumentError.exception("score_maximum is required when score_given is present")}
  end

  defp validate_score_pair(_, _), do: :ok

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_submission(map, nil), do: map

  defp maybe_put_submission(map, submission) do
    json_submission =
      Enum.reduce(submission, %{}, fn
        {:started_at, value}, acc -> Map.put(acc, "startedAt", value)
        {:submitted_at, value}, acc -> Map.put(acc, "submittedAt", value)
        _, acc -> acc
      end)

    Map.put(map, "submission", json_submission)
  end
end
