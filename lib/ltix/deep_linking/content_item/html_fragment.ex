defmodule Ltix.DeepLinking.ContentItem.HTMLFragment do
  import Ltix.DeepLinking.ContentItemHelpers, only: [extensions_schema: 0]

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItemHelpers

  # [DL §3.4](https://www.imsglobal.org/spec/lti-dl/v2p0/#html-fragment)
  @schema Zoi.struct(
            __MODULE__,
            %{
              html: Zoi.string(description: "HTML markup to embed."),
              title: Zoi.string(description: "Title for the content item.") |> Zoi.optional(),
              text: Zoi.string(description: "Plain-text description.") |> Zoi.optional(),
              extensions: extensions_schema()
            },
            coerce: true,
            unrecognized_keys: :error
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

  Takes the module's options as a keyword list or map. Unknown or invalid options return
  an `Ltix.Errors.Invalid.InvalidField` error.

  ## Examples

      iex> {:ok, fragment} = Ltix.DeepLinking.ContentItem.HTMLFragment.new(html: "<p>Hello</p>")
      iex> fragment.html
      "<p>Hello</p>"

      iex> {:error, error} = Ltix.DeepLinking.ContentItem.HTMLFragment.new([])
      iex> Exception.message(error)
      "Ltix.DeepLinking.ContentItem.HTMLFragment field :html is required [DL §3.4]"
  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(opts), do: ContentItemHelpers.new(@schema, opts, "DL §3.4")

  defimpl ContentItem do
    def to_map(item), do: ContentItemHelpers.to_map(item, "html")
  end
end
