defmodule Ltix.DeepLinking.ContentItem.LtiResourceLink do
  import Ltix.DeepLinking.ContentItemHelpers,
    only: [put_fields: 3, put_sub_map: 3, put_passthrough: 3, icon_schema: 1, window_schema: 1]

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItemHelpers

  # [DL §3.2](https://www.imsglobal.org/spec/lti-dl/v2p0/#lti-resource-link)
  @icon_schema icon_schema(description: "Icon or thumbnail for the LTI resource link.")

  @window_schema window_schema(description: "Window presentation for the LTI resource link.")

  @iframe_schema Zoi.map(%{
                   width:
                     Zoi.integer(description: "Suggested iframe width in pixels.")
                     |> Zoi.optional(),
                   height:
                     Zoi.integer(description: "Suggested iframe height in pixels.")
                     |> Zoi.optional()
                 })

  @line_item_schema Zoi.map(%{
                      score_maximum:
                        Zoi.number(
                          description: "Maximum score for the line item; must be positive."
                        )
                        |> Zoi.positive(),
                      label:
                        Zoi.string(description: "Label for the gradebook column.")
                        |> Zoi.optional(),
                      resource_id:
                        Zoi.string(description: "Tool-defined identifier for the resource.")
                        |> Zoi.optional(),
                      tag:
                        Zoi.string(description: "Tag for grouping line items.") |> Zoi.optional(),
                      grades_released:
                        Zoi.boolean(description: "Whether grades are released to students.")
                        |> Zoi.optional()
                    })

  @time_window_schema Zoi.map(%{
                        start_date_time:
                          Zoi.string(description: "ISO 8601 start timestamp.") |> Zoi.optional(),
                        end_date_time:
                          Zoi.string(description: "ISO 8601 end timestamp.") |> Zoi.optional()
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
                Zoi.map(Zoi.string(), Zoi.string(),
                  description: "Custom parameter key-value pairs."
                )
                |> Zoi.optional(),
              line_item: @line_item_schema |> Zoi.optional(),
              available: @time_window_schema |> Zoi.optional(),
              submission: @time_window_schema |> Zoi.optional(),
              extensions:
                Zoi.map(Zoi.string(), Zoi.any(),
                  description: "Vendor-specific extension properties."
                )
                |> Zoi.default(%{})
            },
            coerce: true
          )

  @moduledoc """
  An LTI resource link content item for Deep Linking responses.

  All fields are optional. The platform can use the tool's base URL when
  no `url` is provided. Include a `line_item` to have the platform
  auto-create a gradebook column for the link.

  See [Building Content Items](cookbooks/building-content-items.md) for
  common patterns including line items, custom parameters, and
  availability windows.

  ## Options

  #{Zoi.describe(@schema)}
  """

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Create a new LTI resource link content item.

  ## Examples

      iex> {:ok, link} = Ltix.DeepLinking.ContentItem.LtiResourceLink.new([])
      iex> link.url
      nil

      iex> {:ok, link} = Ltix.DeepLinking.ContentItem.LtiResourceLink.new(url: "https://tool.example.com")
      iex> link.url
      "https://tool.example.com"
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(opts), do: ContentItemHelpers.new(@schema, opts, :lti_resource_link, "DL §3.2")

  defimpl ContentItem do
    def item_type(_item), do: "ltiResourceLink"

    @doc """
    Serialize an LTI resource link to a JSON-compatible map.

    ## Examples

        iex> {:ok, link} = Ltix.DeepLinking.ContentItem.LtiResourceLink.new(url: "https://tool.example.com")
        iex> json = Ltix.DeepLinking.ContentItem.LtiResourceLink.to_json(link)
        iex> json["type"]
        "ltiResourceLink"
    """
    def to_json(item) do
      %{"type" => "ltiResourceLink"}
      |> put_fields(item, [:url, :title, :text])
      |> put_sub_map("icon", item.icon)
      |> put_sub_map("thumbnail", item.thumbnail)
      |> put_sub_map("window", item.window)
      |> put_sub_map("iframe", item.iframe)
      |> put_sub_map("lineItem", item.line_item)
      |> put_sub_map("available", item.available)
      |> put_sub_map("submission", item.submission)
      |> put_passthrough("custom", item.custom)
      |> Map.merge(item.extensions)
    end
  end
end
