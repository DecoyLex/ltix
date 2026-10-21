defmodule Ltix.GradeService.Result do
  @moduledoc """
  A result record from the platform's gradebook.

  Results are read-only. The platform provides them via the result
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

  alias Ltix.Extensions

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
          extensions: %{optional(String.t()) => term()} | nil
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

  @field_schemas %{
    id: Zoi.string(),
    score_of: Zoi.string(),
    user_id: Zoi.string(),
    result_score: Zoi.number(),
    result_maximum: Zoi.number(),
    scoring_user_id: Zoi.string(),
    comment: Zoi.string()
  }

  @json_fields for {key, field} <- @known_keys, do: {field, key, @field_schemas[field], false}

  @doc """
  Parse a result from a decoded JSON map.

  Accepts any map and extracts known fields. Fields with the wrong type are
  `nil`. Unrecognized keys are kept in `extensions`.

  ## Examples

      iex> {:ok, result} = Ltix.GradeService.Result.from_json(%{"userId" => "123", "resultScore" => 0.5})
      iex> {result.user_id, result.result_score}
      {"123", 0.5}
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(json) when is_map(json) do
    # Every field is optional, so parsing never fails.
    {:ok, fields, unrecognized} = Ltix.Type.parse_fields(@json_fields, json, [])
    {:ok, struct!(__MODULE__, [{:extensions, unrecognized} | fields])}
  end

  @doc """
  Serialize a result to a map with camelCase string keys.

  ## Examples

      iex> result = %Ltix.GradeService.Result{user_id: "123", result_score: 0.5}
      iex> Ltix.GradeService.Result.to_map(result)
      %{"userId" => "123", "resultScore" => 0.5}
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    fields =
      Map.new(@known_keys, fn {json_key, field} -> {json_key, Map.fetch!(result, field)} end)

    fields
    |> Map.reject(fn {_json_key, value} -> is_nil(value) end)
    |> Extensions.merge(result.extensions)
  end
end
