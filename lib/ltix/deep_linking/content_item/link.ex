defmodule Ltix.DeepLinking.ContentItem.Link do
  import Ltix.DeepLinking.ContentItemHelpers,
    only: [
      extensions_schema: 0,
      icon_schema: 1,
      object: 1,
      object: 2,
      window_schema: 1
    ]

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItemHelpers

  # [DL §3.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#link)
  @icon_schema icon_schema(description: "Icon or thumbnail for the link.")

  @embed_schema object(%{
                  html: Zoi.string(description: "HTML embed code.")
                })

  @window_schema window_schema(description: "Window presentation for the link.")

  @iframe_schema object(
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
              extensions: extensions_schema()
            },
            coerce: true,
            unrecognized_keys: :error,
            empty_values: [nil]
          )

  @moduledoc """
  A URL link content item for Deep Linking responses.

  Use this for external URLs hosted outside your tool, such as articles,
  documentation, or third-party resources. For links that launch back
  into your tool via LTI, use `Ltix.DeepLinking.ContentItem.LTIResourceLink`.

  ## Examples

      iex> {:ok, link} = Ltix.DeepLinking.ContentItem.Link.new(
      ...>   url: "https://example.com/article",
      ...>   window: [target_name: "articles"]
      ...> )
      iex> Ltix.DeepLinking.ContentItem.to_map(link)
      %{"type" => "link", "url" => "https://example.com/article", "window" => %{"targetName" => "articles"}}

  ## Options

  #{Zoi.describe(@schema)}
  """

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Create a new link content item.

  Takes the module's options as a keyword list or map, and nested options such as
  `icon` may also be keyword lists. Unknown or invalid options return an
  `Ltix.Errors.Invalid.InvalidField` error.

  ## Examples

      iex> {:ok, link} = Ltix.DeepLinking.ContentItem.Link.new(url: "https://example.com")
      iex> link.url
      "https://example.com"

      iex> {:error, error} = Ltix.DeepLinking.ContentItem.Link.new([])
      iex> Exception.message(error)
      "Ltix.DeepLinking.ContentItem.Link field :url is required"
  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(opts), do: ContentItemHelpers.new(@schema, opts)

  @doc """
  Same as `new/1` but raises on error.

  ## Examples

      iex> Ltix.DeepLinking.ContentItem.Link.new!(url: "https://example.com").url
      "https://example.com"
  """
  @spec new!(keyword() | map()) :: t()
  def new!(opts) do
    case new(opts) do
      {:ok, item} -> item
      {:error, error} -> raise error
    end
  end

  defimpl ContentItem do
    def to_map(item), do: ContentItemHelpers.to_map(item, "link")
  end
end
