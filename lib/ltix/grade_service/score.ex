defmodule Ltix.GradeService.Score do
  @moduledoc """
  A score to post to the platform's gradebook.

  Scores are write-only. The tool constructs them and POSTs to the
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
  @activity_progress_values [
    initialized: "initialized",
    started: "started",
    in_progress: "in_progress",
    submitted: "submitted",
    completed: "completed"
  ]

  # [AGS §3.4.8](https://www.imsglobal.org/spec/lti-ags/v2p0/#gradingprogress)
  @grading_progress_values [
    fully_graded: "fully_graded",
    pending: "pending",
    pending_manual: "pending_manual",
    failed: "failed",
    not_ready: "not_ready"
  ]

  @schema Zoi.struct(
            __MODULE__,
            %{
              user_id: Zoi.string(description: "LTI user ID of the score recipient."),
              activity_progress:
                Zoi.enum(@activity_progress_values,
                  coerce: true,
                  description: "User's progress toward completing the activity."
                ),
              grading_progress:
                Zoi.enum(@grading_progress_values,
                  coerce: true,
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
                    "Optional `:started_at` and `:submitted_at` timestamps " <>
                      "in ISO 8601 with fractional seconds and a time zone. " <>
                      "`submitted_at` must not precede `started_at`."
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

  Strings are also accepted for `activity_progress` and `grading_progress`,
  which is convenient when values come from form params:

      iex> {:ok, score} = Ltix.GradeService.Score.new(user_id: "u1", activity_progress: "completed", grading_progress: "fully_graded")
      iex> score.activity_progress
      :completed
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(opts) do
    case Zoi.parse(@schema, Map.new(opts)) do
      {:ok, %__MODULE__{} = score} ->
        score = %{score | timestamp: score.timestamp || DateTime.utc_now()}

        with :ok <- validate_score_pair(score.score_given, score.score_maximum),
             :ok <- validate_submission(score.submission) do
          {:ok, score}
        end

      {:error, errors} ->
        {:error, Zoi.ParseError.exception(errors: errors)}
    end
  end

  @doc """
  Serialize a score to a map with camelCase string keys.

  ## Examples

      iex> {:ok, score} = Ltix.GradeService.Score.new(user_id: "u1", activity_progress: :completed, grading_progress: :fully_graded, timestamp: ~U[2024-01-15 10:30:00.123456Z])
      iex> map = Ltix.GradeService.Score.to_map(score)
      iex> map["userId"]
      "u1"
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = score) do
    # [AGS §3.4.9](https://www.imsglobal.org/spec/lti-ags/v2p0/#timestamp)
    {microsecond, _precision} = score.timestamp.microsecond
    timestamp = %{score.timestamp | microsecond: {microsecond, 6}}

    json = %{
      "userId" => score.user_id,
      "activityProgress" => Map.fetch!(@activity_progress_to_json, score.activity_progress),
      "gradingProgress" => Map.fetch!(@grading_progress_to_json, score.grading_progress),
      "timestamp" => DateTime.to_iso8601(timestamp)
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

  defp validate_submission(nil), do: :ok

  defp validate_submission(submission) do
    with {:ok, started_at} <-
           parse_submission_timestamp(Map.get(submission, :started_at), :started_at),
         {:ok, submitted_at} <-
           parse_submission_timestamp(Map.get(submission, :submitted_at), :submitted_at) do
      validate_submission_order(started_at, submitted_at)
    end
  end

  # [startedat-optional]:
  # https://www.imsglobal.org/spec/lti-ags/v2p0/#startedat-optional
  # [submittedat-optional]:
  # https://www.imsglobal.org/spec/lti-ags/v2p0/#submittedat-optional
  #
  # [AGS §3.4.10.1][startedat-optional] and [AGS §3.4.10.2][submittedat-optional]
  defp parse_submission_timestamp(nil, _field), do: {:ok, nil}

  defp parse_submission_timestamp(timestamp, field) do
    with [_, fraction] <-
           Regex.run(~r/[.,](\d+)(?:Z|[+-]\d{2}(?::?\d{2})?)\z/, timestamp),
         {:ok, datetime, _offset} <- parse_iso8601(timestamp) do
      {:ok, {DateTime.to_unix(datetime), String.trim_trailing(fraction, "0")}}
    else
      _ ->
        {:error,
         ArgumentError.exception(
           "#{field} must use ISO 8601 with fractional seconds and a time zone designator"
         )}
    end
  end

  defp parse_iso8601(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, _, _} = result -> result
      {:error, _} -> DateTime.from_iso8601(timestamp, :basic)
    end
  end

  defp validate_submission_order(nil, _submitted_at), do: :ok
  defp validate_submission_order(_started_at, nil), do: :ok

  defp validate_submission_order(started_at, submitted_at) when submitted_at >= started_at,
    do: :ok

  defp validate_submission_order(_started_at, _submitted_at) do
    {:error, ArgumentError.exception("submitted_at must be equal to or later than started_at")}
  end

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

if Code.ensure_loaded?(JSON.Encoder) do
  defimpl JSON.Encoder, for: Ltix.GradeService.Score do
    def encode(score, encoder) do
      score
      |> Ltix.GradeService.Score.to_map()
      |> JSON.Encoder.Map.encode(encoder)
    end
  end
end

if Code.ensure_loaded?(Jason.Encoder) do
  defimpl Jason.Encoder, for: Ltix.GradeService.Score do
    def encode(score, opts) do
      score
      |> Ltix.GradeService.Score.to_map()
      |> Jason.Encode.map(opts)
    end
  end
end
