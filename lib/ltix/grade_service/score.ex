defmodule Ltix.GradeService.Score do
  @moduledoc """
  A score to post to the platform's gradebook.

  Scores are write-only. The tool builds them and sends them to the
  platform. Use `new/1` to build a validated score, then pass it to
  `Ltix.GradeService.post_score/3`.

  The `grading_progress` must be `:fully_graded` for the platform to
  record the score as a final grade. Other values are considered
  partial and the platform may ignore them.

  ## Examples

  ```elixir
  {:ok, score} = Ltix.GradeService.Score.new(
    user_id: "12345",
    score_given: 85,
    score_maximum: 100,
    activity_progress: :completed,
    grading_progress: :fully_graded
  )

  score.score_given
  #=> 85
  ```

  ## Properties

  Plugins add properties to scores, such as a Canvas submission, with
  `Ltix.Property`. Pass a property to `new/1` by its name, and read it from
  `extensions`.

  ```elixir
  {:ok, score} =
    Ltix.GradeService.Score.new(
      user_id: "12345",
      activity_progress: :completed,
      grading_progress: :fully_graded,
      canvas_submission: %{new_submission: true, submission_type: "online_url"}
    )

  score.extensions.canvas_submission
  #=> %{new_submission: true, submission_type: "online_url"}
  ```
  """

  use Ltix.Provider, hook: [Ltix.Property]

  alias Ltix.Errors.Invalid.InvalidField

  # [AGS, activityProgress](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#activity-progress)
  @activity_progress_values [
    initialized: "initialized",
    started: "started",
    in_progress: "in_progress",
    submitted: "submitted",
    completed: "completed"
  ]

  # [AGS, gradingProgress](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#grading-progress)
  @grading_progress_values [
    fully_graded: "fully_graded",
    pending: "pending",
    pending_manual: "pending_manual",
    failed: "failed",
    not_ready: "not_ready"
  ]

  # [AGS, Score service Media type and schema](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#score-service-media-type-and-schema)
  use Ltix.Type,
    json_keys: :camel_case,
    fields: [
      user_id: Zoi.string(description: "LTI user ID of the score recipient."),
      activity_progress:
        Zoi.enum(@activity_progress_values,
          coerce: true,
          description: "User's progress toward completing the activity.",
          metadata: [to_json: &__MODULE__.activity_progress_to_json/1]
        ),
      grading_progress:
        Zoi.enum(@grading_progress_values,
          coerce: true,
          description: "Status of the grading process. Must be `:fully_graded` for final scores.",
          metadata: [to_json: &__MODULE__.grading_progress_to_json/1]
        ),
      timestamp:
        Zoi.datetime(
          description: "When the score was set. Auto-generated if not provided.",
          metadata: [to_json: &__MODULE__.timestamp_to_json/1]
        )
        |> Zoi.optional(),
      score_given:
        Zoi.number(
          description: "Score value (must be >= 0). Requires `score_maximum` when present."
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
        Zoi.string(description: "Plain text comment visible to both student and instructor.")
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
              "`DateTime` values. `submitted_at` must not precede `started_at`.",
          metadata: [to_json: &__MODULE__.submission_to_json/1]
        )
        |> Zoi.optional()
    ]

  @doc """
  Build a validated score from a keyword list or a map.

  Auto-generates a `timestamp` with microsecond precision if not provided.
  The fields can include plugin properties by name, and the score has their
  values in `extensions`.

  ## Options

  #{Zoi.describe(@ltix_type_schema)}
    * `:plugins` - the plugins that declare the properties, as a list of plugins or an
      `Ltix.PluginSet`. Defaults to the configured plugins.

  ## Examples

  ```elixir
  iex> {:ok, score} = Ltix.GradeService.Score.new(user_id: "u1", activity_progress: :completed, grading_progress: :fully_graded)
  iex> score.user_id
  "u1"
  ```

  Strings are also accepted for `activity_progress` and `grading_progress`,
  which is convenient when values come from form params.

  ```elixir
  iex> {:ok, score} = Ltix.GradeService.Score.new(%{user_id: "u1", activity_progress: "completed", grading_progress: "fully_graded"})
  iex> score.activity_progress
  :completed
  ```
  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(attributes) when is_list(attributes) or is_map(attributes) do
    attributes = Map.put_new_lazy(Map.new(attributes), :timestamp, &DateTime.utc_now/0)

    with {:ok, score} <- Ltix.Type.new(__MODULE__, attributes),
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

  ```elixir
  iex> score = Ltix.GradeService.Score.new!(user_id: "u1", activity_progress: :completed, grading_progress: :fully_graded)
  iex> Ltix.GradeService.Score.validate(score)
  :ok
  iex> {:error, error} = Ltix.GradeService.Score.validate(%{score | user_id: nil})
  iex> error.field
  :user_id
  ```
  """
  @spec validate(t()) :: :ok | {:error, Exception.t()}
  def validate(%__MODULE__{} = score) do
    with {:ok, _score} <- new(Ltix.Type.standard_fields(score)),
         do: :ok
  end

  # --- Private ---

  # [AGS, timestamp](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#timestamp)
  defp validate_timestamp(%__MODULE__{timestamp: nil}),
    do: {:error, InvalidField.required(__MODULE__, :timestamp)}

  defp validate_timestamp(%__MODULE__{}), do: :ok

  # [AGS, scoreGiven and scoreMaximum](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#score-given-and-score-maximum)
  defp validate_score_pair(%__MODULE__{score_given: given, score_maximum: nil})
       when not is_nil(given) do
    {:error, InvalidField.required(__MODULE__, :score_maximum)}
  end

  defp validate_score_pair(%__MODULE__{}), do: :ok

  # [AGS, submittedAt (Optional)](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#submitted-at-optional)
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

  # AGS sends progress values in PascalCase, such as `InProgress`.
  @doc false
  def activity_progress_to_json(progress), do: Recase.to_pascal(Atom.to_string(progress))

  @doc false
  def grading_progress_to_json(progress), do: Recase.to_pascal(Atom.to_string(progress))

  # [AGS, timestamp](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#timestamp)
  # [AGS, submission (Optional)](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#submission-optional)
  @doc false
  def timestamp_to_json(%DateTime{} = date_time) do
    microseconds = DateTime.to_unix(date_time, :microsecond)
    DateTime.to_iso8601(DateTime.from_unix!(microseconds, :microsecond))
  end

  @doc false
  def submission_to_json(submission) do
    for {key, %DateTime{} = value} <- submission,
        into: %{},
        do: {Recase.to_camel(Atom.to_string(key)), timestamp_to_json(value)}
  end

  @doc """
  Adds an anonymous property of scores to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)
end
