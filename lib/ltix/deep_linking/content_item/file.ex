defmodule Ltix.DeepLinking.ContentItem.File do
  import Ltix.DeepLinking.ContentItemHelpers,
    only: [extensions_schema: 0, icon_schema: 1]

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItemHelpers

  # [DL §3.3](https://www.imsglobal.org/spec/lti-dl/v2p0/#file)
  @icon_schema icon_schema(description: "Icon or thumbnail for the file.")

  @schema Zoi.struct(
            __MODULE__,
            %{
              url: Zoi.string(description: "URL to download the file."),
              title: Zoi.string(description: "Title for the content item.") |> Zoi.optional(),
              text: Zoi.string(description: "Plain-text description.") |> Zoi.optional(),
              icon: @icon_schema |> Zoi.optional(),
              thumbnail: @icon_schema |> Zoi.optional(),
              media_type:
                Zoi.string(description: "MIME type of the file (e.g. `\"application/pdf\"`).")
                |> Zoi.optional(),
              expires_at:
                Zoi.datetime(description: "When the download URL expires.")
                |> Zoi.optional(),
              extensions: extensions_schema()
            },
            coerce: true,
            unrecognized_keys: :error
          )

  @moduledoc """
  A file content item for Deep Linking responses.

  File URLs are short-lived. The platform downloads the file shortly
  after receiving the response, so the URL only needs to remain valid
  for a few minutes.

  ## Examples

      iex> {:ok, file} = Ltix.DeepLinking.ContentItem.File.new(
      ...>   url: "https://example.com/syllabus.pdf",
      ...>   media_type: "application/pdf"
      ...> )
      iex> Ltix.DeepLinking.ContentItem.to_map(file)
      %{"type" => "file", "url" => "https://example.com/syllabus.pdf", "mediaType" => "application/pdf"}

  ## Options

  #{Zoi.describe(@schema)}
  """

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Create a new file content item.

  Takes the module's options as a keyword list or map, and nested options such as
  `icon` may also be keyword lists. Unknown or invalid options return an
  `Ltix.Errors.Invalid.InvalidField` error.

  ## Examples

      iex> {:ok, file} = Ltix.DeepLinking.ContentItem.File.new(url: "https://example.com/doc.pdf")
      iex> file.url
      "https://example.com/doc.pdf"

      iex> {:error, error} = Ltix.DeepLinking.ContentItem.File.new([])
      iex> Exception.message(error)
      "Ltix.DeepLinking.ContentItem.File field :url is required [DL §3.3]"
  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(opts), do: ContentItemHelpers.new(@schema, opts, "DL §3.3")

  @doc """
  Same as `new/1` but raises on error.

  ## Examples

      iex> Ltix.DeepLinking.ContentItem.File.new!(url: "https://example.com/doc.pdf").url
      "https://example.com/doc.pdf"
  """
  @spec new!(keyword() | map()) :: t()
  def new!(opts) do
    case new(opts) do
      {:ok, item} -> item
      {:error, error} -> raise error
    end
  end

  defimpl ContentItem do
    def to_map(item), do: ContentItemHelpers.to_map(item, "file")
  end
end
