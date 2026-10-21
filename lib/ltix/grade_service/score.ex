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

  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.Extensions
  alias Ltix.Options

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

  # [AGS §3.4.3](https://www.imsglobal.org/spec/lti-ags/v2p0/#score-service-media-type-and-schema)
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
                Zoi.datetime(
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
                Zoi.map(
                  %{
                    started_at: Zoi.datetime() |> Zoi.optional(),
                    submitted_at: Zoi.datetime() |> Zoi.optional()
                  },
                  unrecognized_keys: :error,
                  empty_values: [nil],
                  description:
                    "Keyword list or map with optional `:started_at` and `:submitted_at` " <>
                      "`DateTime` values. `submitted_at` must not precede `started_at`."
                )
                |> Zoi.optional(),
              extensions:
                Extensions.schema(
                  "Extension properties keyed by fully qualified URLs, given as strings or atoms."
                )
            },
            coerce: true,
            unrecognized_keys: :error,
            empty_values: [nil]
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  # The JSON key of each score field in `to_map/1`.
  @json_keys %{
    user_id: "userId",
    activity_progress: "activityProgress",
    grading_progress: "gradingProgress",
    timestamp: "timestamp",
    score_given: "scoreGiven",
    score_maximum: "scoreMaximum",
    scoring_user_id: "scoringUserId",
    comment: "comment",
    submission: "submission"
  }

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
  Build a validated score from a keyword list or a map.

  Auto-generates a `timestamp` with microsecond precision if not provided.

  ## Options

  #{Zoi.describe(@schema)}

  ## Examples

      iex> {:ok, score} = Ltix.GradeService.Score.new(user_id: "u1", activity_progress: :completed, grading_progress: :fully_graded)
      iex> score.user_id
      "u1"

  Strings are also accepted for `activity_progress` and `grading_progress`,
  which is convenient when values come from form params.

      iex> {:ok, score} = Ltix.GradeService.Score.new(%{user_id: "u1", activity_progress: "completed", grading_progress: "fully_graded"})
      iex> score.activity_progress
      :completed
  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(attributes) when is_list(attributes) or is_map(attributes) do
    attributes =
      attributes
      |> Map.new(fn {key, value} -> {key, Options.keyword_to_map(value)} end)
      |> Map.put_new_lazy(:timestamp, &DateTime.utc_now/0)

    # [AGS §3.1.2](https://www.imsglobal.org/spec/lti-ags/v2p0/#extensions)
    conflicts =
      Extensions.conflicts(__MODULE__, attributes[:extensions], Map.values(@json_keys))

    with {:ok, score} <-
           InvalidField.parse(__MODULE__, @schema, attributes, conflicts),
         :ok <- validate_timestamp(score),
         :ok <- validate_score_pair(score),
         :ok <- validate_submission_order(score.submission) do
      {:ok, score}
    end
  end

  @doc """
  Same as `new/1` but raises on error.
  """
  @spec new!(keyword() | map()) :: t()
  def new!(attributes) do
    case new(attributes) do
      {:ok, score} -> score
      {:error, error} -> raise error
    end
  end

  @doc """
  Validate a score the same way as `new/1`.

  Useful for a score built or changed as a struct.

  ## Examples

      iex> score = Ltix.GradeService.Score.new!(user_id: "u1", activity_progress: :completed, grading_progress: :fully_graded)
      iex> Ltix.GradeService.Score.validate(score)
      :ok
      iex> {:error, error} = Ltix.GradeService.Score.validate(%{score | user_id: nil})
      iex> error.field
      :user_id
  """
  @spec validate(t()) :: :ok | {:error, Exception.t()}
  def validate(%__MODULE__{} = score) do
    with {:ok, _score} <- new(Map.from_struct(score)), do: :ok
  end

  @doc """
  Serialize a score to a map with camelCase string keys.

  ## Examples

      iex> {:ok, score} = Ltix.GradeService.Score.new(user_id: "u1", activity_progress: :completed, grading_progress: :fully_graded, timestamp: ~U[2024-01-15 10:30:00.123456Z])
      iex> map = Ltix.GradeService.Score.to_map(score)
      iex> map["timestamp"]
      "2024-01-15T10:30:00.123456Z"
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = score) do
    json =
      for {field, key} <- @json_keys,
          value <- [Map.fetch!(score, field)],
          value != nil,
          into: %{},
          do: {key, to_json(field, value)}

    Extensions.merge(json, score.extensions)
  end

  # --- Private ---

  # [AGS §3.4.9](https://www.imsglobal.org/spec/lti-ags/v2p0/#timestamp)
  defp validate_timestamp(%__MODULE__{timestamp: nil}),
    do: {:error, InvalidField.required(__MODULE__, :timestamp)}

  defp validate_timestamp(%__MODULE__{}), do: :ok

  # [AGS §3.4.4](https://www.imsglobal.org/spec/lti-ags/v2p0/#scoregiven-and-scoremaximum)
  defp validate_score_pair(%__MODULE__{score_given: given, score_maximum: nil})
       when not is_nil(given) do
    {:error, invalid(:score_maximum, nil, "must be present when score_given is present")}
  end

  defp validate_score_pair(%__MODULE__{}), do: :ok

  # [AGS §3.4.10.2](https://www.imsglobal.org/spec/lti-ags/v2p0/#submittedat-optional)
  defp validate_submission_order(%{started_at: started_at, submitted_at: submitted_at}) do
    if DateTime.compare(submitted_at, started_at) == :lt do
      {:error,
       invalid([:submission, :submitted_at], submitted_at, "must not be earlier than started_at")}
    else
      :ok
    end
  end

  defp validate_submission_order(_submission), do: :ok

  defp invalid(field, value, reason), do: InvalidField.invalid(__MODULE__, field, value, reason)

  # [AGS §3.4.9](https://www.imsglobal.org/spec/lti-ags/v2p0/#timestamp)
  # [AGS §3.4.10](https://www.imsglobal.org/spec/lti-ags/v2p0/#submission-optional)
  defp format_timestamp(%DateTime{} = date_time) do
    microseconds = DateTime.to_unix(date_time, :microsecond)
    DateTime.to_iso8601(DateTime.from_unix!(microseconds, :microsecond))
  end

  defp to_json(:activity_progress, progress), do: Map.fetch!(@activity_progress_to_json, progress)
  defp to_json(:grading_progress, progress), do: Map.fetch!(@grading_progress_to_json, progress)
  defp to_json(:timestamp, timestamp), do: format_timestamp(timestamp)

  defp to_json(:submission, submission) do
    Map.new(submission, fn
      {:started_at, value} -> {"startedAt", format_timestamp(value)}
      {:submitted_at, value} -> {"submittedAt", format_timestamp(value)}
    end)
  end

  defp to_json(_field, value), do: value
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
