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

  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.Errors.Invalid.MalformedResponse

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
          start_date_time: DateTime.t() | nil,
          end_date_time: DateTime.t() | nil,
          grades_released: boolean() | nil,
          extensions: %{optional(String.t()) => term()}
        }

  # [AGS §3.2.7](https://www.imsglobal.org/spec/lti-ags/v2p0/#label)
  @label_schema Zoi.string(description: "Label for the gradebook column.")
                |> Zoi.refine({__MODULE__, :validate_label, []})

  # [AGS §3.2.8](https://www.imsglobal.org/spec/lti-ags/v2p0/#scoremaximum)
  @score_maximum_schema Zoi.number(description: "Maximum score, greater than 0.")
                        |> Zoi.positive()

  # [AGS §3.2.12](https://www.imsglobal.org/spec/lti-ags/v2p0/#startdatetime)
  # [AGS §3.2.13](https://www.imsglobal.org/spec/lti-ags/v2p0/#enddatetime)
  @validation_schema Zoi.map(%{
                       label: @label_schema,
                       score_maximum: @score_maximum_schema,
                       start_date_time: Zoi.optional(Zoi.datetime()),
                       end_date_time: Zoi.optional(Zoi.datetime())
                     })

  @spec_refs %{
    label: "AGS §3.2.7",
    score_maximum: "AGS §3.2.8",
    start_date_time: "AGS §3.2.12",
    end_date_time: "AGS §3.2.13"
  }

  @validated_fields Map.keys(@spec_refs)

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

  @doc """
  Parse a line item from a decoded JSON map.

  Accepts any map and extracts known fields. Unrecognized keys are
  captured in `extensions` for lossless round-trips. `startDateTime` and
  `endDateTime` become `DateTime` structs in UTC.

  ## Examples

      iex> {:ok, item} = Ltix.GradeService.LineItem.from_json(%{"label" => "Quiz 1", "scoreMaximum" => 100})
      iex> {item.label, item.score_maximum}
      {"Quiz 1", 100}
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(json) when is_map(json) do
    {fields, extensions} = classify_keys(json)

    # [AGS §3.2.12](https://www.imsglobal.org/spec/lti-ags/v2p0/#startdatetime)
    # [AGS §3.2.13](https://www.imsglobal.org/spec/lti-ags/v2p0/#enddatetime)
    with {:ok, start_date_time} <-
           parse_date_time(fields[:start_date_time], "startDateTime", "AGS §3.2.12"),
         {:ok, end_date_time} <-
           parse_date_time(fields[:end_date_time], "endDateTime", "AGS §3.2.13") do
      fields =
        Map.merge(fields, %{
          start_date_time: start_date_time,
          end_date_time: end_date_time,
          extensions: extensions
        })

      {:ok, struct!(__MODULE__, fields)}
    end
  end

  @doc """
  Validate that a line item has the required fields for publishing.

  Checks that `label` is present and non-blank, that `score_maximum` is
  a positive number, and that date times are `DateTime` structs.

  ## Examples

      iex> item = %Ltix.GradeService.LineItem{label: "Quiz 1", score_maximum: 100}
      iex> Ltix.GradeService.LineItem.validate(item)
      :ok

      iex> item = %Ltix.GradeService.LineItem{label: nil, score_maximum: 100}
      iex> {:error, error} = Ltix.GradeService.LineItem.validate(item)
      iex> Exception.message(error)
      "Ltix.GradeService.LineItem field :label is required [AGS §3.2.7]"
  """
  @spec validate(t()) :: :ok | {:error, Exception.t()}
  def validate(%__MODULE__{} = item) do
    fields =
      item
      |> Map.take(@validated_fields)
      |> Map.reject(fn {_field, value} -> is_nil(value) end)

    with {:ok, _fields} <-
           InvalidField.parse(__MODULE__, @validation_schema, fields, &Map.fetch!(@spec_refs, &1)),
         do: :ok
  end

  @doc false
  def label_schema, do: @label_schema

  @doc false
  def score_maximum_schema, do: @score_maximum_schema

  @doc false
  @spec validate_label(String.t(), keyword()) :: :ok | {:error, String.t()}
  def validate_label(label, _opts) do
    if String.trim(label) == "", do: {:error, "must not be blank"}, else: :ok
  end

  @doc """
  Serialize a line item to a map with camelCase string keys.

  ## Examples

      iex> item = %Ltix.GradeService.LineItem{label: "Quiz 1", score_maximum: 100}
      iex> map = Ltix.GradeService.LineItem.to_map(item)
      iex> {map["label"], map["scoreMaximum"]}
      {"Quiz 1", 100}
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = item) do
    fields =
      Map.new(@known_keys, fn {json_key, field} ->
        {json_key, to_json(Map.fetch!(item, field))}
      end)

    fields
    |> Map.reject(fn {_json_key, value} -> is_nil(value) end)
    |> Map.merge(item.extensions)
  end

  defp classify_keys(json) do
    Ltix.GradeService.classify_keys(json, @known_keys)
  end

  # [AGS §4.2](https://www.imsglobal.org/spec/lti-ags/v2p0/#datetime-values)
  defp to_json(%DateTime{} = date_time),
    do: DateTime.to_iso8601(DateTime.shift_zone!(date_time, "Etc/UTC"))

  defp to_json(value), do: value

  defp parse_date_time(value, _key, _spec_ref) when value in [nil, ""], do: {:ok, nil}

  defp parse_date_time(value, key, spec_ref) when is_binary(value) do
    with {:error, _reason} <- DateTime.from_iso8601(value),
         {:error, _reason} <- DateTime.from_iso8601(value, :basic) do
      malformed_date_time(key, spec_ref)
    else
      {:ok, date_time, _offset} -> {:ok, date_time}
    end
  end

  defp parse_date_time(_value, key, spec_ref), do: malformed_date_time(key, spec_ref)

  defp malformed_date_time(key, spec_ref) do
    {:error,
     MalformedResponse.exception(
       service: Ltix.GradeService,
       reason: "#{key} must be an ISO 8601 date and time with a time zone",
       spec_ref: spec_ref
     )}
  end
end

if Code.ensure_loaded?(JSON.Encoder) do
  defimpl JSON.Encoder, for: Ltix.GradeService.LineItem do
    def encode(item, encoder) do
      item
      |> Ltix.GradeService.LineItem.to_map()
      |> JSON.Encoder.Map.encode(encoder)
    end
  end
end

if Code.ensure_loaded?(Jason.Encoder) do
  defimpl Jason.Encoder, for: Ltix.GradeService.LineItem do
    def encode(item, opts) do
      item
      |> Ltix.GradeService.LineItem.to_map()
      |> Jason.Encode.map(opts)
    end
  end
end
