defmodule Ltix.DeepLinking.ContentItem.Link do
  import Ltix.DeepLinking.ContentItemHelpers,
    only: [put_fields: 3, put_sub_map: 3, icon_schema: 1, window_schema: 1]

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItemHelpers

  # [DL §3.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#link)
  @icon_schema icon_schema(description: "Icon or thumbnail for the link.")

  @embed_schema Zoi.map(%{
                  html: Zoi.string(description: "HTML embed code.")
                })

  @window_schema window_schema(description: "Window presentation for the link.")

  @iframe_schema Zoi.map(
                   %{
                     src: Zoi.string(description: "URL to load in the iframe."),
                     width:
                       Zoi.integer(description: "Suggested iframe width in pixels.")
                       |> Zoi.optional(),
                     height:
                       Zoi.integer(description: "Suggested iframe height in pixels.")
                       |> Zoi.optional()
                   },
                   description: "Iframe presentation for the link."
                 )

  @schema Zoi.struct(
            __MODULE__,
            %{
              url: Zoi.string(description: "URL of the link."),
              title: Zoi.string(description: "Title for the content item.") |> Zoi.optional(),
              text: Zoi.string(description: "Plain-text description.") |> Zoi.optional(),
              icon: @icon_schema |> Zoi.optional(),
              thumbnail: @icon_schema |> Zoi.optional(),
              embed: @embed_schema |> Zoi.optional(),
              window: @window_schema |> Zoi.optional(),
              iframe: @iframe_schema |> Zoi.optional(),
              extensions:
                Zoi.map(Zoi.string(), Zoi.any(),
                  description: "Vendor-specific extension properties."
                )
                |> Zoi.default(%{})
            },
            coerce: true
          )

  @moduledoc """
  A URL link content item for Deep Linking responses.

  Use this for external URLs hosted outside your tool, such as articles,
  documentation, or third-party resources. For links that launch back
  into your tool via LTI, use `Ltix.DeepLinking.ContentItem.LtiResourceLink`
  instead.

  ## Options

  #{Zoi.describe(@schema)}
  """

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Create a new link content item.

  ## Examples

      iex> {:ok, link} = Ltix.DeepLinking.ContentItem.Link.new(url: "https://example.com")
      iex> link.url
      "https://example.com"

      iex> {:error, %Ltix.Errors.Invalid{}} =
      ...>   Ltix.DeepLinking.ContentItem.Link.new([])
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(opts), do: ContentItemHelpers.new(@schema, opts, :link, "DL §3.1")

  defimpl ContentItem do
    def item_type(_item), do: "link"

    @doc """
    Serialize a link to a map.

    ## Examples

        iex> {:ok, link} = Ltix.DeepLinking.ContentItem.Link.new(url: "https://example.com")
        iex> json = Ltix.DeepLinking.ContentItem.Link.to_map(link)
        iex> json["type"]
        "link"
    """
    def to_map(item) do
      %{"type" => "link"}
      |> put_fields(item, [:url, :title, :text])
      |> put_sub_map("icon", item.icon)
      |> put_sub_map("thumbnail", item.thumbnail)
      |> put_sub_map("embed", item.embed)
      |> put_sub_map("window", item.window)
      |> put_sub_map("iframe", item.iframe)
      |> Map.merge(item.extensions)
    end
  end
end
