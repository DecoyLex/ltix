defmodule Ltix.DeepLinking.ContentItem.Image do
  import Ltix.DeepLinking.ContentItemHelpers,
    only: [extensions_schema: 0, icon_schema: 1]

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
              extensions: extensions_schema()
            },
            coerce: true,
            unrecognized_keys: :error,
            empty_values: [nil]
          )

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
      iex> Ltix.DeepLinking.ContentItem.to_map(image)
      %{"type" => "image", "url" => "https://example.com/diagram.png", "width" => 800}

  ## Options

  #{Zoi.describe(@schema)}
  """

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Create a new image content item.

  Takes the module's options as a keyword list or map, and nested options such as
  `icon` may also be keyword lists. Unknown or invalid options return an
  `Ltix.Errors.Invalid.InvalidField` error.

  ## Examples

      iex> {:ok, image} = Ltix.DeepLinking.ContentItem.Image.new(url: "https://example.com/photo.png")
      iex> image.url
      "https://example.com/photo.png"

      iex> {:error, error} = Ltix.DeepLinking.ContentItem.Image.new([])
      iex> Exception.message(error)
      "Ltix.DeepLinking.ContentItem.Image field :url is required"
  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(opts), do: ContentItemHelpers.new(@schema, opts)

  @doc """
  Same as `new/1` but raises on error.

  ## Examples

      iex> Ltix.DeepLinking.ContentItem.Image.new!(url: "https://example.com/photo.png").url
      "https://example.com/photo.png"
  """
  @spec new!(keyword() | map()) :: t()
  def new!(opts) do
    case new(opts) do
      {:ok, item} -> item
      {:error, error} -> raise error
    end
  end

  defimpl ContentItem do
    def to_map(item), do: ContentItemHelpers.to_map(item, "image")
  end
end
