defmodule Ltix.DeepLinking.ContentItemType.Fields do
  @moduledoc """
  Schemas for fields that content item types share, such as `title` and
  `window`. `use Ltix.DeepLinking.ContentItemType` imports these functions.

      fields: [
        question: Zoi.string(description: "The question to ask."),
        title: title(description: "Title of the poll.")
      ]

  Each function returns an optional field's schema, and takes Zoi options,
  such as `description:`, that replace its defaults.

    * `title/1` - the content item's plain-text title
    * `text/1` - a plain-text description of the content item
    * `icon/1` - an icon the platform shows with the content item, with `url`
      and optional `width` and `height`
    * `thumbnail/1` - a thumbnail the platform shows as a link to the content
      item, with `url` and optional `width` and `height`
    * `window/1` - how to open the content item in a new window or tab, with
      optional `target_name`, `width`, `height`, and `window_features`
    * `iframe/1` - how to show the content item in an iframe, with optional
      `width` and `height`. With `src: true`, it also requires a `src`.
    * `embed/1` - HTML that embeds the content item, with `html`

  `Ltix.Type.object/2` builds the schema of a nested object of your own.
  """

  alias Ltix.Options
  alias Ltix.Type

  @iframe_schema Zoi.keyword(
                   [
                     src:
                       Zoi.boolean(
                         description:
                           "When `true`, the schema requires a `src` key. When `false`, it rejects one."
                       )
                       |> Zoi.default(false)
                   ],
                   unrecognized_keys: :error
                 )

  # [DL, Link](https://standards.1edtech.org/lti/specifications/launch_messages/deep_linking/lti-deep-linking-spec#link)

  @doc """
  Returns a schema for the content item's plain-text title.

      iex> Zoi.parse(Ltix.DeepLinking.ContentItemType.Fields.title(), "Quiz 1")
      {:ok, "Quiz 1"}
  """
  @spec title(keyword()) :: Zoi.schema()
  def title(zoi_options \\ []),
    do: Zoi.string(described(zoi_options, "Title for the content item.")) |> Zoi.optional()

  @doc """
  Returns a schema for a plain-text description of the content item.

      iex> Zoi.parse(Ltix.DeepLinking.ContentItemType.Fields.text(), "Ten questions")
      {:ok, "Ten questions"}
  """
  @spec text(keyword()) :: Zoi.schema()
  def text(zoi_options \\ []),
    do: Zoi.string(described(zoi_options, "Plain-text description.")) |> Zoi.optional()

  @doc """
  Returns a schema for an icon the platform shows with the content item, with
  `url` and optional `width` and `height`.

      iex> Zoi.parse(
      ...>   Ltix.DeepLinking.ContentItemType.Fields.icon(),
      ...>   %{url: "https://tool.example.com/icon.png", width: 32}
      ...> )
      {:ok, %{url: "https://tool.example.com/icon.png", width: 32}}
  """
  @spec icon(keyword()) :: Zoi.schema()
  def icon(zoi_options \\ []),
    do:
      image(
        described(
          zoi_options,
          "Icon to show with the content item, with `url` and optional `width` and `height`."
        )
      )

  @doc """
  Returns a schema for a thumbnail the platform shows as a link to the content
  item, with `url` and optional `width` and `height`.

      iex> Zoi.parse(
      ...>   Ltix.DeepLinking.ContentItemType.Fields.thumbnail(),
      ...>   %{url: "https://tool.example.com/thumbnail.png"}
      ...> )
      {:ok, %{url: "https://tool.example.com/thumbnail.png"}}
  """
  @spec thumbnail(keyword()) :: Zoi.schema()
  def thumbnail(zoi_options \\ []),
    do:
      image(
        described(
          zoi_options,
          "Thumbnail to show as a link to the content item, with `url` and optional `width` and `height`."
        )
      )

  @doc """
  Returns a schema for how to open the content item in a new window or tab,
  with optional `target_name`, `width`, `height`, and `window_features`.

      iex> Zoi.parse(Ltix.DeepLinking.ContentItemType.Fields.window(), %{target_name: "quiz"})
      {:ok, %{target_name: "quiz"}}
  """
  @spec window(keyword()) :: Zoi.schema()
  def window(zoi_options \\ []) do
    %{
      target_name: Zoi.string(description: "Name of the window or tab.") |> Zoi.optional(),
      width: Zoi.integer(description: "Suggested window width in pixels.") |> Zoi.optional(),
      height: Zoi.integer(description: "Suggested window height in pixels.") |> Zoi.optional(),
      window_features:
        Zoi.string(description: "Comma-separated window features, such as `\"menubar=no\"`.")
        |> Zoi.optional()
    }
    |> Type.object(
      described(
        zoi_options,
        "How to open the content item in a new window or tab, with optional `target_name`, `width`, `height`, and `window_features`."
      )
    )
    |> Zoi.optional()
  end

  @doc """
  Returns a schema for how to show the content item in an iframe, with
  optional `width` and `height`. With `src: true`, it also requires a `src`.

      iex> Zoi.parse(Ltix.DeepLinking.ContentItemType.Fields.iframe(), %{width: 800})
      {:ok, %{width: 800}}

  ## Options

  #{Zoi.describe(@iframe_schema)}

  The other options are Zoi options, such as `description:`.
  """
  @spec iframe(keyword()) :: Zoi.schema()
  def iframe(opts \\ []) do
    {iframe_opts, zoi_options} = Keyword.split(opts, [:src])
    src? = Keyword.fetch!(Options.parse!(iframe_opts, @iframe_schema), :src)
    {fields, description} = iframe_fields(src?)

    fields
    |> Type.object(described(zoi_options, description))
    |> Zoi.optional()
  end

  defp iframe_fields(false) do
    {%{
       width: Zoi.integer(description: "Suggested iframe width in pixels.") |> Zoi.optional(),
       height: Zoi.integer(description: "Suggested iframe height in pixels.") |> Zoi.optional()
     }, "How to show the content item in an iframe, with optional `width` and `height`."}
  end

  defp iframe_fields(true) do
    {fields, _description} = iframe_fields(false)

    {Map.put(fields, :src, Zoi.string(description: "URL to load in the iframe.")),
     "How to show the content item in an iframe, with `src` and optional `width` and `height`."}
  end

  @doc """
  Returns a schema for HTML that embeds the content item, with a required
  `html` key.

      iex> Zoi.parse(Ltix.DeepLinking.ContentItemType.Fields.embed(), %{html: "<p>Poll</p>"})
      {:ok, %{html: "<p>Poll</p>"}}
  """
  @spec embed(keyword()) :: Zoi.schema()
  def embed(zoi_options \\ []) do
    %{html: Zoi.string(description: "HTML that embeds the content item.")}
    |> Type.object(described(zoi_options, "HTML that embeds the content item, with `html`."))
    |> Zoi.optional()
  end

  defp image(zoi_options) do
    %{
      url: Zoi.string(description: "URL of the image."),
      width: Zoi.integer(description: "Width in pixels.") |> Zoi.optional(),
      height: Zoi.integer(description: "Height in pixels.") |> Zoi.optional()
    }
    |> Type.object(zoi_options)
    |> Zoi.optional()
  end

  defp described(zoi_options, description),
    do: Keyword.put_new(zoi_options, :description, description)
end
