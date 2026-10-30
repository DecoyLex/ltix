defmodule Ltix.GradeService.LineItem do
  @moduledoc """
  A line item, which has one score per user for one activity. The platform
  decides where the scores appear, usually as a gradebook column.

  Each line item has a label, maximum score, and optional bindings to resource
  links or tool resources.

  ## Examples

      item = %Ltix.GradeService.LineItem{label: "Chapter 5 Test", score_maximum: 60}
      {:ok, item} = Ltix.GradeService.create_line_item(client, item)

  ## Properties

  Plugins add properties to line items, such as a Canvas submission type,
  with `Ltix.Property`. Pass a property by its name, and read it from
  `extensions`.

      {:ok, item} =
        Ltix.GradeService.create_line_item(client,
          label: "Essay",
          score_maximum: 10,
          canvas_submission_type: %{type: "external_tool"}
        )

      item.extensions.canvas_submission_type.type
      #=> "external_tool"

  A property's [`:writes`](`m:Ltix.Property#module-options`) option lists the
  operations that send it, `:create` for `Ltix.GradeService.create_line_item/3`
  and `:update` for `Ltix.GradeService.update_line_item/3`.
  """

  use Ltix.Provider, hook: [Ltix.Property]

  alias Ltix.Errors.Invalid.InvalidField

  # [AGS, startDateTime](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#start-date-time)
  # [AGS, endDateTime](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#end-date-time)
  @date_time_schema Zoi.datetime(
                      metadata: [
                        from_json: &__MODULE__.parse_date_time/1,
                        to_json: &__MODULE__.date_time_to_json/1
                      ]
                    )

  # [AGS, Line item service scope and allowed http methods](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#line-item-service-scope-and-allowed-http-methods)
  use Ltix.Type,
    json_keys: :camel_case,
    fields: [
      id: Zoi.string() |> Zoi.optional(),
      label: Zoi.string() |> Zoi.optional(),
      score_maximum: Zoi.number() |> Zoi.optional(),
      resource_link_id: Zoi.string() |> Zoi.optional(),
      resource_id: Zoi.string() |> Zoi.optional(),
      tag: Zoi.string() |> Zoi.optional(),
      start_date_time: Zoi.optional(@date_time_schema),
      end_date_time: Zoi.optional(@date_time_schema),
      grades_released: Zoi.boolean() |> Zoi.optional()
    ]

  # [AGS, Label](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#label)
  @label_schema Zoi.string(description: "Label for the line item.")
                |> Zoi.refine({__MODULE__, :validate_label, []})

  # [AGS, scoreMaximum](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#score-maximum)
  @score_maximum_schema Zoi.number(description: "Maximum score, greater than 0.")
                        |> Zoi.positive()

  @validation_fields %{
    label: @label_schema,
    score_maximum: @score_maximum_schema,
    start_date_time: Zoi.optional(Zoi.datetime()),
    end_date_time: Zoi.optional(Zoi.datetime())
  }

  @validation_schema Zoi.map(@validation_fields)

  @date_time_error "must be an ISO 8601 date and time with a time zone"

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
      "Ltix.GradeService.LineItem field :label is required"
  """
  @spec validate(t()) :: :ok | {:error, Exception.t()}
  def validate(%__MODULE__{} = item) do
    fields =
      item
      |> Map.take(Map.keys(@validation_fields))
      |> Map.reject(fn {_field, value} -> is_nil(value) end)

    with {:ok, _fields} <- InvalidField.parse(__MODULE__, @validation_schema, fields), do: :ok
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

  # [AGS, Datetime values](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#datetime-values)
  @doc false
  @spec date_time_to_json(DateTime.t()) :: String.t()
  def date_time_to_json(date_time),
    do: DateTime.to_iso8601(DateTime.shift_zone!(date_time, "Etc/UTC"))

  @doc false
  @spec parse_date_time(term()) :: {:ok, DateTime.t()} | {:error, String.t()}
  def parse_date_time(value) when is_binary(value) do
    with {:error, _reason} <- DateTime.from_iso8601(value),
         {:error, _reason} <- DateTime.from_iso8601(value, :basic) do
      {:error, @date_time_error}
    else
      {:ok, date_time, _offset} -> {:ok, date_time}
    end
  end

  def parse_date_time(_value), do: {:error, @date_time_error}

  @doc """
  Adds an anonymous property of line items to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)
end
