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

  defstruct [
    :user_id,
    :activity_progress,
    :grading_progress,
    :timestamp,
    :score_given,
    :score_maximum,
    :scoring_user_id,
    :comment,
    :submission,
    extensions: %{}
  ]

  @type t :: %__MODULE__{
          user_id: String.t(),
          activity_progress: activity_progress(),
          grading_progress: grading_progress(),
          timestamp: DateTime.t(),
          score_given: number() | nil,
          score_maximum: number() | nil,
          scoring_user_id: String.t() | nil,
          comment: String.t() | nil,
          submission: %{started_at: String.t(), submitted_at: String.t()} | nil,
          extensions: %{optional(String.t()) => term()}
        }

  @type activity_progress :: :initialized | :started | :in_progress | :submitted | :completed
  @type grading_progress :: :fully_graded | :pending | :pending_manual | :failed | :not_ready

  # [AGS §3.4.7](https://www.imsglobal.org/spec/lti-ags/v2p0/#activityprogress)
  @activity_progress_values [:initialized, :started, :in_progress, :submitted, :completed]

  @activity_progress_to_json %{
    initialized: "Initialized",
    started: "Started",
    in_progress: "InProgress",
    submitted: "Submitted",
    completed: "Completed"
  }

  # [AGS §3.4.8](https://www.imsglobal.org/spec/lti-ags/v2p0/#gradingprogress)
  @grading_progress_values [:fully_graded, :pending, :pending_manual, :failed, :not_ready]

  @grading_progress_to_json %{
    fully_graded: "FullyGraded",
    pending: "Pending",
    pending_manual: "PendingManual",
    failed: "Failed",
    not_ready: "NotReady"
  }

  @schema NimbleOptions.new!(
            user_id: [
              type: :string,
              required: true,
              doc: "LTI user ID of the score recipient."
            ],
            activity_progress: [
              type: {:in, @activity_progress_values},
              required: true,
              doc: "User's progress toward completing the activity."
            ],
            grading_progress: [
              type: {:in, @grading_progress_values},
              required: true,
              doc: "Status of the grading process. Must be `:fully_graded` for final scores."
            ],
            timestamp: [
              type: {:struct, DateTime},
              doc: "When the score was set. Auto-generated if not provided."
            ],
            score_given: [
              type: {:custom, __MODULE__, :validate_non_negative_number, []},
              doc: "Score value (must be >= 0). Requires `score_maximum` when present."
            ],
            score_maximum: [
              type: {:custom, __MODULE__, :validate_positive_number, []},
              doc: "Maximum possible score (must be > 0). Required when `score_given` is present."
            ],
            scoring_user_id: [
              type: :string,
              doc: "LTI user ID of the person who provided the score."
            ],
            comment: [
              type: :string,
              doc: "Plain text comment visible to both student and instructor."
            ],
            submission: [
              type: {:map, :atom, :string},
              doc:
                "Submission metadata with `:started_at` and `:submitted_at` ISO 8601 timestamps."
            ],
            extensions: [
              type: {:map, :string, :any},
              default: %{},
              doc: "Extension properties keyed by fully qualified URLs."
            ]
          )

  @doc """
  Build a validated score from keyword options.

  Auto-generates a `timestamp` with microsecond precision if not provided.

  ## Options

  #{NimbleOptions.docs(@schema)}

  ## Examples

      iex> {:ok, score} = Ltix.GradeService.Score.new(user_id: "u1", activity_progress: :completed, grading_progress: :fully_graded)
      iex> score.user_id
      "u1"
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(opts) do
    case NimbleOptions.validate(opts, @schema) do
      {:ok, validated} ->
        validated = Keyword.put_new_lazy(validated, :timestamp, &DateTime.utc_now/0)

        with :ok <- validate_score_pair(validated[:score_given], validated[:score_maximum]) do
          {:ok, struct!(__MODULE__, validated)}
        end

      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error, error}
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
    {:error,
     NimbleOptions.ValidationError.exception(
       key: :score_maximum,
       message: "is required when score_given is present"
     )}
  end

  defp validate_score_pair(_, _), do: :ok

  @doc false
  def validate_non_negative_number(value) when is_number(value) and value >= 0, do: {:ok, value}

  def validate_non_negative_number(value) do
    {:error, "expected score_given to be a non-negative number, got: #{inspect(value)}"}
  end

  @doc false
  def validate_positive_number(value) when is_number(value) and value > 0, do: {:ok, value}

  def validate_positive_number(value) do
    {:error, "expected score_maximum to be a positive number (> 0), got: #{inspect(value)}"}
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
