defmodule Ltix.DeepLinking.ContentItem.LTIResourceLink do
  import Ltix.DeepLinking.ContentItemHelpers,
    only: [
      extensions_schema: 0,
      icon_schema: 1,
      object: 1,
      object: 2,
      string_keyed_map: 2,
      window_schema: 1
    ]

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItemHelpers
  alias Ltix.GradeService.LineItem

  # [DL §3.2](https://www.imsglobal.org/spec/lti-dl/v2p0/#lti-resource-link)
  @icon_schema icon_schema(description: "Icon or thumbnail for the LTI resource link.")

  @window_schema window_schema(description: "Window presentation for the LTI resource link.")

  @iframe_schema object(%{
                   width:
                     Zoi.integer(description: "Suggested iframe width in pixels.")
                     |> Zoi.optional(),
                   height:
                     Zoi.integer(description: "Suggested iframe height in pixels.")
                     |> Zoi.optional()
                 })

  @line_item_schema object(
                      %{
                        score_maximum: LineItem.score_maximum_schema(),
                        label: Zoi.optional(LineItem.label_schema()),
                        resource_id:
                          Zoi.string(description: "Tool-defined identifier for the resource.")
                          |> Zoi.optional(),
                        tag:
                          Zoi.string(description: "Tag for grouping line items.")
                          |> Zoi.optional(),
                        grades_released:
                          Zoi.boolean(description: "Whether grades are released to students.")
                          |> Zoi.optional()
                      },
                      description:
                        "Gradebook column for the platform to create, as a keyword list or map."
                    )

  @time_window_schema object(%{
                        start_date_time:
                          Zoi.datetime(description: "Start of the window.") |> Zoi.optional(),
                        end_date_time:
                          Zoi.datetime(description: "End of the window.") |> Zoi.optional()
                      })

  @schema Zoi.struct(
            __MODULE__,
            %{
              url: Zoi.string(description: "Launch URL for the resource link.") |> Zoi.optional(),
              title: Zoi.string(description: "Title for the content item.") |> Zoi.optional(),
              text: Zoi.string(description: "Plain-text description.") |> Zoi.optional(),
              icon: @icon_schema |> Zoi.optional(),
              thumbnail: @icon_schema |> Zoi.optional(),
              window: @window_schema |> Zoi.optional(),
              iframe: @iframe_schema |> Zoi.optional(),
              custom:
                Zoi.string()
                |> string_keyed_map(description: "Custom parameter key-value pairs.")
                |> Zoi.optional(),
              line_item: @line_item_schema |> Zoi.optional(),
              available: @time_window_schema |> Zoi.optional(),
              submission: @time_window_schema |> Zoi.optional(),
              extensions: extensions_schema()
            },
            coerce: true,
            unrecognized_keys: :error
          )

  @moduledoc """
  An LTI resource link content item for Deep Linking responses.

  All fields are optional. The platform can use the tool's base URL when
  no `url` is provided. Include a `line_item` to have the platform
  auto-create a gradebook column for the link.

  See [Building Content Items](cookbooks/building-content-items.md) for
  common patterns including line items, custom parameters, and
  availability windows.

  ## Examples

      iex> {:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
      ...>   url: "https://tool.example.com/quizzes/7",
      ...>   line_item: [score_maximum: 100]
      ...> )
      iex> Ltix.DeepLinking.ContentItem.to_map(link)
      %{"type" => "ltiResourceLink", "url" => "https://tool.example.com/quizzes/7", "lineItem" => %{"scoreMaximum" => 100}}

  ## Options

  #{Zoi.describe(@schema)}
  """

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Create a new LTI resource link content item.

  Takes the module's options as a keyword list or map, and nested options such as
  `icon` may also be keyword lists. Unknown or invalid options return an
  `Ltix.Errors.Invalid.InvalidField` error.

  ## Examples

      iex> {:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new([])
      iex> link.url
      nil

      iex> {:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(url: "https://tool.example.com")
      iex> link.url
      "https://tool.example.com"
  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(opts), do: ContentItemHelpers.new(@schema, opts, "DL §3.2")

  defimpl ContentItem do
    def item_type(_item), do: "ltiResourceLink"

    def to_map(item), do: ContentItemHelpers.to_map(item, "ltiResourceLink")
  end
end
