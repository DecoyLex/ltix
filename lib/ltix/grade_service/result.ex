defmodule Ltix.GradeService.Result do
  @moduledoc """
  A result record from the platform's gradebook.

  Results are read-only — the platform provides them via the result
  service. Each result represents the current grade for a specific
  line item and user.

  When `result_maximum` is `nil`, consumers should treat it as 1
  per the spec default.

  ## Examples

      {:ok, result} = Ltix.GradeService.Result.from_json(%{
        "userId" => "5323497",
        "resultScore" => 0.83,
        "resultMaximum" => 1
      })

      result.result_score
      #=> 0.83
  """

  defstruct [
    :id,
    :score_of,
    :user_id,
    :result_score,
    :result_maximum,
    :scoring_user_id,
    :comment,
    extensions: %{}
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          score_of: String.t() | nil,
          user_id: String.t() | nil,
          result_score: number() | nil,
          result_maximum: number() | nil,
          scoring_user_id: String.t() | nil,
          comment: String.t() | nil,
          extensions: %{optional(String.t()) => term()}
        }

  # [AGS §3.3.4](https://www.imsglobal.org/spec/lti-ags/v2p0/#media-type-and-schema-0)
  @known_keys %{
    "id" => :id,
    "scoreOf" => :score_of,
    "userId" => :user_id,
    "resultScore" => :result_score,
    "resultMaximum" => :result_maximum,
    "scoringUserId" => :scoring_user_id,
    "comment" => :comment
  }

  @doc """
  Parse a result from a decoded JSON map.

  Accepts any map and extracts known fields. Unrecognized keys are
  captured in `extensions`.

  ## Examples

      iex> {:ok, result} = Ltix.GradeService.Result.from_json(%{"userId" => "123", "resultScore" => 0.5})
      iex> {result.user_id, result.result_score}
      {"123", 0.5}
  """
  @spec from_json(map()) :: {:ok, t()}
  def from_json(json) when is_map(json) do
    {fields, extensions} = classify_keys(json)
    {:ok, struct!(__MODULE__, Map.put(fields, :extensions, extensions))}
  end

  defp classify_keys(json) do
    Ltix.GradeService.classify_keys(json, @known_keys)
  end
end
