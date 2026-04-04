defmodule Ltix.DeepLinking.ContentItem.HtmlFragment do
  import Ltix.DeepLinking.ContentItemHelpers, only: [put_fields: 3]

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItemHelpers

  # [DL §3.4](https://www.imsglobal.org/spec/lti-dl/v2p0/#html-fragment)
  @schema Zoi.struct(
            __MODULE__,
            %{
              html: Zoi.string(description: "HTML markup to embed."),
              title: Zoi.string(description: "Title for the content item.") |> Zoi.optional(),
              text: Zoi.string(description: "Plain-text description.") |> Zoi.optional(),
              extensions:
                Zoi.map(Zoi.string(), Zoi.any(),
                  description: "Vendor-specific extension properties."
                )
                |> Zoi.default(%{})
            },
            coerce: true
          )

  @moduledoc """
  An HTML fragment content item for Deep Linking responses.

  Represents a chunk of HTML that the platform embeds directly.

  ## Options

  #{Zoi.describe(@schema)}
  """

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Create a new HTML fragment content item.

  ## Examples

      iex> {:ok, fragment} = Ltix.DeepLinking.ContentItem.HtmlFragment.new(html: "<p>Hello</p>")
      iex> fragment.html
      "<p>Hello</p>"

      iex> {:error, %Ltix.Errors.Invalid{}} =
      ...>   Ltix.DeepLinking.ContentItem.HtmlFragment.new([])
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(opts), do: ContentItemHelpers.new(@schema, opts, :html_fragment, "DL §3.4")

  defimpl ContentItem do
    def item_type(_item), do: "html"

    @doc """
    Serialize an HTML fragment to a map.

    ## Examples

        iex> {:ok, fragment} = Ltix.DeepLinking.ContentItem.HtmlFragment.new(html: "<p>Hello</p>")
        iex> json = Ltix.DeepLinking.ContentItem.HtmlFragment.to_map(fragment)
        iex> json["type"]
        "html"
        iex> json["html"]
        "<p>Hello</p>"
    """
    def to_map(item) do
      %{"type" => "html"}
      |> put_fields(item, [:html, :title, :text])
      |> Map.merge(item.extensions)
    end
  end
end
