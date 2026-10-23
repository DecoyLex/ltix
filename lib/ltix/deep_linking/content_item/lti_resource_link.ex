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
      %Ltix.DeepLinking.LineItem{score_maximum: 100}

  ## Line items

  `line_item` takes an `Ltix.DeepLinking.LineItem`, a keyword list or map of
  its fields, or an `Ltix.GradeService.LineItem`. From a grade service line
  item, the link takes `label`, `score_maximum`, `resource_id`, `tag`, and
  `grades_released`. Any other field set on it is an
  `Ltix.Errors.Invalid.InvalidField` error, as is a property that no enabled
  plugin adds to Deep Linking line items.

      iex> line_item = %Ltix.GradeService.LineItem{label: "Quiz 7", score_maximum: 100}
      iex> {:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(line_item: line_item)
      iex> link.line_item
      %Ltix.DeepLinking.LineItem{label: "Quiz 7", score_maximum: 100}
  """

  alias Ltix.DeepLinking.LineItem
  alias Ltix.DeepLinking.Settings
  alias Ltix.Errors.Invalid.LineItemNotAccepted
  alias Ltix.GradeService

  # Custom property names are given as strings or atoms, kept as strings, and
  # sent as written.
  @custom_key_schema [Zoi.string(), Zoi.atom()]
                     |> Zoi.union(error: "must be keyed by a string or atom")
                     |> Zoi.transform({__MODULE__, :key_to_string, []})

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
        Zoi.map(@custom_key_schema, Zoi.string(),
          description: "Custom property keys and values.",
          error: "must be a map or keyword list"
        )
        |> Zoi.optional(),
      line_item:
        Ltix.Type.schema(LineItem,
          description: "Line item for the platform to create."
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
    fields = Map.new(fields)
    super(Map.replace(fields, :line_item, line_item(fields[:line_item])))
  end

  # A grade service line item's set fields, properties, and unrecognized
  # properties, as a Deep Linking line item's fields. Deep Linking line items
  # don't have some of them, which makes `new/1` return an error for each.
  defp line_item(%GradeService.LineItem{} = line_item) do
    fields =
      for {field, value} <- Ltix.Type.standard_fields(line_item), value != nil, do: {field, value}

    unrecognized =
      if line_item.unrecognized == %{}, do: [], else: [unrecognized: line_item.unrecognized]

    Map.merge(Map.new(fields ++ unrecognized), line_item.extensions)
  end

  defp line_item(line_item), do: line_item

  @doc """
  Adds an anonymous property of `ltiResourceLink` content items to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)

  @doc false
  def key_to_string(key, _opts), do: {:ok, to_string(key)}
end
