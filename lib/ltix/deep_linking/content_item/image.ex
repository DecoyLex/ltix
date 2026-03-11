defmodule Ltix.DeepLinking.ContentItem.Image do
  import Ltix.DeepLinking.ContentItemHelpers,
    only: [put_fields: 3, put_sub_map: 3, icon_schema: 1]

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItemHelpers

  # [DL §3.5](https://www.imsglobal.org/spec/lti-dl/v2p0/#image)
  @icon_schema icon_schema(description: "Icon or thumbnail for the image.")

  @schema Zoi.struct(
            __MODULE__,
            %{
              url: Zoi.string(description: "URL of the image."),
              title: Zoi.string(description: "Title for the content item.") |> Zoi.optional(),
              text: Zoi.string(description: "Plain-text description.") |> Zoi.optional(),
              icon: @icon_schema |> Zoi.optional(),
              thumbnail: @icon_schema |> Zoi.optional(),
              width: Zoi.integer(description: "Width of the image in pixels.") |> Zoi.optional(),
              height:
                Zoi.integer(description: "Height of the image in pixels.") |> Zoi.optional(),
              extensions:
                Zoi.map(Zoi.string(), Zoi.any(),
                  description: "Vendor-specific extension properties."
                )
                |> Zoi.default(%{})
            },
            coerce: true
          )

  @moduledoc """
  An image content item for Deep Linking responses.

  The platform renders the image directly using an HTML `img` tag.
  For images that are part of a larger resource, consider using
  `Ltix.DeepLinking.ContentItem.Link` with an `embed` instead.

  ## Options

  #{Zoi.describe(@schema)}
  """

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Create a new image content item.

  ## Examples

      iex> {:ok, image} = Ltix.DeepLinking.ContentItem.Image.new(url: "https://example.com/photo.png")
      iex> image.url
      "https://example.com/photo.png"

      iex> {:error, %Ltix.Errors.Invalid{}} =
      ...>   Ltix.DeepLinking.ContentItem.Image.new([])
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(opts), do: ContentItemHelpers.new(@schema, opts, :image, "DL §3.5")

  defimpl ContentItem do
    def item_type(_item), do: "image"

    @doc """
    Serialize an image to a JSON-compatible map.

    ## Examples

        iex> {:ok, image} = Ltix.DeepLinking.ContentItem.Image.new(url: "https://example.com/photo.png")
        iex> json = Ltix.DeepLinking.ContentItem.Image.to_json(image)
        iex> json["type"]
        "image"
    """
    def to_json(item) do
      %{"type" => "image"}
      |> put_fields(item, [:url, :title, :text, :width, :height])
      |> put_sub_map("icon", item.icon)
      |> put_sub_map("thumbnail", item.thumbnail)
      |> Map.merge(item.extensions)
    end
  end
end
