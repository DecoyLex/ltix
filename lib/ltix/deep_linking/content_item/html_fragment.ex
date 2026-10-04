defmodule Ltix.DeepLinking.ContentItem.HTMLFragment do
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

  ## Examples

      iex> {:ok, fragment} = Ltix.DeepLinking.ContentItem.HTMLFragment.new(html: "<p>Hello</p>")
      iex> Ltix.DeepLinking.ContentItem.to_map(fragment)
      %{"type" => "html", "html" => "<p>Hello</p>"}

  ## Options

  #{Zoi.describe(@schema)}
  """

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Create a new HTML fragment content item.

  ## Examples

      iex> {:ok, fragment} = Ltix.DeepLinking.ContentItem.HTMLFragment.new(html: "<p>Hello</p>")
      iex> fragment.html
      "<p>Hello</p>"

      iex> {:error, error} = Ltix.DeepLinking.ContentItem.HTMLFragment.new([])
      iex> error.field
      "html_fragment.html"
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(opts), do: ContentItemHelpers.new(@schema, opts, :html_fragment, "DL §3.4")

  defimpl ContentItem do
    def item_type(_item), do: "html"

    def to_map(item) do
      %{"type" => "html"}
      |> put_fields(item, [:html, :title, :text])
      |> Map.merge(item.extensions)
    end
  end
end
