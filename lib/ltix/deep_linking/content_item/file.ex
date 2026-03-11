defmodule Ltix.DeepLinking.ContentItem.File do
  import Ltix.DeepLinking.ContentItemHelpers,
    only: [put_fields: 3, put_sub_map: 3, icon_schema: 1]

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
                Zoi.string(description: "ISO 8601 timestamp when the download URL expires.")
                |> Zoi.optional(),
              extensions:
                Zoi.map(Zoi.string(), Zoi.any(),
                  description: "Vendor-specific extension properties."
                )
                |> Zoi.default(%{})
            },
            coerce: true
          )

  @moduledoc """
  A file content item for Deep Linking responses.

  File URLs are short-lived. The platform downloads the file shortly
  after receiving the response, so the URL only needs to remain valid
  for a few minutes.

  ## Options

  #{Zoi.describe(@schema)}
  """

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Create a new file content item.

  ## Examples

      iex> {:ok, file} = Ltix.DeepLinking.ContentItem.File.new(url: "https://example.com/doc.pdf")
      iex> file.url
      "https://example.com/doc.pdf"

      iex> {:error, %Ltix.Errors.Invalid{}} =
      ...>   Ltix.DeepLinking.ContentItem.File.new([])
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(opts), do: ContentItemHelpers.new(@schema, opts, :file, "DL §3.3")

  defimpl ContentItem do
    def item_type(_item), do: "file"

    @doc """
    Serialize a file to a JSON-compatible map.

    ## Examples

        iex> {:ok, file} = Ltix.DeepLinking.ContentItem.File.new(url: "https://example.com/doc.pdf")
        iex> json = Ltix.DeepLinking.ContentItem.File.to_json(file)
        iex> json["type"]
        "file"
    """
    def to_json(item) do
      %{"type" => "file"}
      |> put_fields(item, [:url, :title, :text, :media_type, :expires_at])
      |> put_sub_map("icon", item.icon)
      |> put_sub_map("thumbnail", item.thumbnail)
      |> Map.merge(item.extensions)
    end
  end
end
