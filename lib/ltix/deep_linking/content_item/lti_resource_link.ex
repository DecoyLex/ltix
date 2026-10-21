defmodule Ltix.DeepLinking.ContentItem.LTIResourceLink do
  @moduledoc """
  An LTI resource link content item for Deep Linking responses.

  All fields are optional. The platform can use the tool's base URL when
  no `url` is provided. Include a `line_item` to have the platform
  auto-create a gradebook column for the link.

  See [Building Content Items](cookbooks/building-content-items.md) for
  common patterns including line items, custom properties, and
  availability windows.

  ## Examples

      iex> {:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
      ...>   url: "https://tool.example.com/quizzes/7",
      ...>   line_item: [score_maximum: 100]
      ...> )
      iex> link.line_item
      %{score_maximum: 100}

  `line_item` also takes an `Ltix.GradeService.LineItem`.

      iex> line_item = %Ltix.GradeService.LineItem{label: "Quiz 7", score_maximum: 100}
      iex> {:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(line_item: line_item)
      iex> link.line_item
      %{label: "Quiz 7", score_maximum: 100}
  """

  alias Ltix.DeepLinking.Settings
  alias Ltix.Errors.Invalid.LineItemNotAccepted
  alias Ltix.Extensions
  alias Ltix.GradeService.LineItem

  @time_window %{
    start_date_time: Zoi.datetime(description: "Start of the window.") |> Zoi.optional(),
    end_date_time: Zoi.datetime(description: "End of the window.") |> Zoi.optional()
  }

  # [DL §3.2](https://www.imsglobal.org/spec/lti-dl/v2p0/#lti-resource-link)
  use Ltix.DeepLinking.ContentItemType,
    type: "ltiResourceLink",
    fields: [
      url: Zoi.string(description: "Launch URL for the resource link.") |> Zoi.optional(),
      title: title(),
      text: text(),
      icon: icon(),
      thumbnail: thumbnail(),
      window: window(),
      iframe: iframe(),
      custom:
        Zoi.string()
        |> Extensions.string_keyed_map(description: "Custom property keys and values.")
        |> Zoi.optional(),
      line_item:
        Ltix.Type.object(
          %{
            score_maximum: LineItem.score_maximum_schema(),
            label: Zoi.optional(LineItem.label_schema()),
            resource_id:
              Zoi.string(description: "Tool-defined identifier for the resource.")
              |> Zoi.optional(),
            tag: Zoi.string(description: "Tag for grouping line items.") |> Zoi.optional(),
            grades_released:
              Zoi.boolean(description: "Whether grades are released to students.")
              |> Zoi.optional()
          },
          description:
            "Gradebook column for the platform to create, with `score_maximum` and optional `label`, `resource_id`, `tag`, and `grades_released`, or an `Ltix.GradeService.LineItem`."
        )
        |> Zoi.optional(),
      available:
        Ltix.Type.object(@time_window,
          description:
            "When learners can open the link, with optional `start_date_time` and `end_date_time`."
        )
        |> Zoi.optional(),
      submission:
        Ltix.Type.object(@time_window,
          description:
            "When learners can submit to the link, with optional `start_date_time` and `end_date_time`."
        )
        |> Zoi.optional()
    ]

  @impl Ltix.DeepLinking.ContentItemType
  def check(%__MODULE__{line_item: line_item}, %Settings{accept_line_item: false})
      when line_item != nil,
      do: {:error, LineItemNotAccepted.exception()}

  def check(_link, _settings), do: :ok

  def new(fields) do
    super(
      Map.new(fields, fn
        {:line_item, %LineItem{} = line_item} -> {:line_item, line_item_fields(line_item)}
        field -> field
      end)
    )
  end

  # Returns every set field, so fields Deep Linking can't send are rejected as unknown.
  defp line_item_fields(line_item) do
    for {field, value} <- Map.from_struct(line_item), value not in [nil, %{}], into: %{} do
      {field, value}
    end
  end

  @doc """
  Adds an anonymous property of `ltiResourceLink` content items to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)
end
