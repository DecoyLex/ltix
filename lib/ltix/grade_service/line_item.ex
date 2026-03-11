defmodule Ltix.GradeService.LineItem do
  @moduledoc """
  A line item (gradebook column) in the platform's gradebook.

  Line items hold results for a specific activity and set of users.
  Each has a label, maximum score, and optional bindings to resource
  links or tool resources.

  ## Examples

      {:ok, item} = Ltix.GradeService.LineItem.from_json(%{
        "id" => "https://lms.example.com/lineitems/1",
        "label" => "Chapter 5 Test",
        "scoreMaximum" => 60,
        "tag" => "grade"
      })

      item.label
      #=> "Chapter 5 Test"

      item.score_maximum
      #=> 60
  """

  alias Ltix.Errors.Invalid.InvalidClaim

  defstruct [
    :id,
    :label,
    :score_maximum,
    :resource_link_id,
    :resource_id,
    :tag,
    :start_date_time,
    :end_date_time,
    :grades_released,
    extensions: %{}
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          label: String.t() | nil,
          score_maximum: number() | nil,
          resource_link_id: String.t() | nil,
          resource_id: String.t() | nil,
          tag: String.t() | nil,
          start_date_time: String.t() | nil,
          end_date_time: String.t() | nil,
          grades_released: boolean() | nil,
          extensions: %{optional(String.t()) => term()}
        }

  # [AGS §3.2](https://www.imsglobal.org/spec/lti-ags/v2p0/#line-item-service-scope-and-allowed-http-methods)
  @known_keys %{
    "id" => :id,
    "label" => :label,
    "scoreMaximum" => :score_maximum,
    "resourceLinkId" => :resource_link_id,
    "resourceId" => :resource_id,
    "tag" => :tag,
    "startDateTime" => :start_date_time,
    "endDateTime" => :end_date_time,
    "gradesReleased" => :grades_released
  }

  @reverse_keys Map.new(@known_keys, fn {json_key, field} -> {field, json_key} end)

  @doc """
  Parse a line item from a decoded JSON map.

  Accepts any map and extracts known fields. Unrecognized keys are
  captured in `extensions` for lossless round-trips.

  ## Examples

      iex> {:ok, item} = Ltix.GradeService.LineItem.from_json(%{"label" => "Quiz 1", "scoreMaximum" => 100})
      iex> {item.label, item.score_maximum}
      {"Quiz 1", 100}
  """
  @spec from_json(map()) :: {:ok, t()}
  def from_json(json) when is_map(json) do
    {fields, extensions} = classify_keys(json)
    {:ok, struct!(__MODULE__, Map.put(fields, :extensions, extensions))}
  end

  @doc """
  Serialize a line item to a JSON-compatible map.

  Validates that `label` is present and non-blank, and that
  `score_maximum` is a positive number. Returns `{:ok, map}` or
  `{:error, exception}`.

  ## Examples

      iex> item = %Ltix.GradeService.LineItem{label: "Quiz 1", score_maximum: 100}
      iex> {:ok, json} = Ltix.GradeService.LineItem.to_json(item)
      iex> {json["label"], json["scoreMaximum"]}
      {"Quiz 1", 100}
  """
  @spec to_json(t()) :: {:ok, map()} | {:error, Exception.t()}
  def to_json(%__MODULE__{} = item) do
    with :ok <- validate_label(item.label),
         :ok <- validate_score_maximum(item.score_maximum) do
      {:ok, serialize(item)}
    end
  end

  defp serialize(item) do
    @reverse_keys
    |> Enum.reduce(%{}, fn {field, json_key}, acc ->
      case Map.fetch!(item, field) do
        nil -> acc
        value -> Map.put(acc, json_key, value)
      end
    end)
    |> Map.merge(item.extensions)
  end

  defp classify_keys(json) do
    Ltix.GradeService.classify_keys(json, @known_keys)
  end

  # [AGS §3.2.7](https://www.imsglobal.org/spec/lti-ags/v2p0/#label)
  defp validate_label(nil) do
    {:error,
     InvalidClaim.exception(
       claim: "label",
       value: nil,
       message: "must be present and non-blank",
       spec_ref: "AGS §3.2.7"
     )}
  end

  defp validate_label(label) when is_binary(label) do
    if String.trim(label) == "" do
      {:error,
       InvalidClaim.exception(
         claim: "label",
         value: label,
         message: "must be present and non-blank",
         spec_ref: "AGS §3.2.7"
       )}
    else
      :ok
    end
  end

  # [AGS §3.2.8](https://www.imsglobal.org/spec/lti-ags/v2p0/#scoremaximum)
  defp validate_score_maximum(nil) do
    {:error,
     InvalidClaim.exception(
       claim: "scoreMaximum",
       value: nil,
       message: "must be a positive number",
       spec_ref: "AGS §3.2.8"
     )}
  end

  defp validate_score_maximum(value) when is_number(value) and value > 0, do: :ok

  defp validate_score_maximum(value) do
    {:error,
     InvalidClaim.exception(
       claim: "scoreMaximum",
       value: value,
       message: "must be a positive number",
       spec_ref: "AGS §3.2.8"
     )}
  end
end
