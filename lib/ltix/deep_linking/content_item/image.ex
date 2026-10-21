defmodule Ltix.DeepLinking.ContentItem.Image do
  @moduledoc """
  An image content item for Deep Linking responses.

  The platform renders the image directly using an HTML `img` tag.
  For images that are part of a larger resource, consider using
  `Ltix.DeepLinking.ContentItem.Link` with an `embed`.

  ## Examples

      iex> {:ok, image} = Ltix.DeepLinking.ContentItem.Image.new(
      ...>   url: "https://example.com/diagram.png",
      ...>   width: 800
      ...> )
      iex> image.width
      800

      iex> {:error, error} = Ltix.DeepLinking.ContentItem.Image.new([])
      iex> Exception.message(error)
      "Ltix.DeepLinking.ContentItem.Image field :url is required"
  """

  # [DL §3.5](https://www.imsglobal.org/spec/lti-dl/v2p0/#image)
  use Ltix.DeepLinking.ContentItemType,
    type: "image",
    fields: [
      url: Zoi.string(description: "URL of the image."),
      title: title(),
      text: text(),
      icon: icon(),
      thumbnail: thumbnail(),
      width: Zoi.integer(description: "Width of the image in pixels.") |> Zoi.optional(),
      height: Zoi.integer(description: "Height of the image in pixels.") |> Zoi.optional()
    ]

  @doc """
  Adds an anonymous property of `image` content items to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)
end
