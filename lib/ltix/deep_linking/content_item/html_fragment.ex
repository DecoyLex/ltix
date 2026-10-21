defmodule Ltix.DeepLinking.ContentItem.HTMLFragment do
  @moduledoc """
  An HTML fragment content item for Deep Linking responses.

  Represents a chunk of HTML that the platform embeds directly.

  ## Examples

      iex> {:ok, fragment} = Ltix.DeepLinking.ContentItem.HTMLFragment.new(html: "<p>Hello</p>")
      iex> fragment.html
      "<p>Hello</p>"

      iex> {:error, error} = Ltix.DeepLinking.ContentItem.HTMLFragment.new([])
      iex> Exception.message(error)
      "Ltix.DeepLinking.ContentItem.HTMLFragment field :html is required"
  """

  # [DL §3.4](https://www.imsglobal.org/spec/lti-dl/v2p0/#html-fragment)
  use Ltix.DeepLinking.ContentItemType,
    type: "html",
    fields: [
      html: Zoi.string(description: "HTML markup to embed."),
      title: title(),
      text: text()
    ]

  @doc """
  Adds an anonymous property of `html` content items to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)
end
