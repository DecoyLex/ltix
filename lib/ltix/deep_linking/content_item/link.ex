defmodule Ltix.DeepLinking.ContentItem.Link do
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
      iex> link.window
      %{target_name: "articles"}

      iex> {:error, error} = Ltix.DeepLinking.ContentItem.Link.new([])
      iex> Exception.message(error)
      "Ltix.DeepLinking.ContentItem.Link field :url is required"
  """

  # [DL §3.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#link)
  use Ltix.DeepLinking.ContentItemType,
    type: "link",
    fields: [
      url: Zoi.string(description: "URL of the link."),
      title: title(),
      text: text(),
      icon: icon(),
      thumbnail: thumbnail(),
      embed: embed(),
      window: window(),
      iframe: iframe(src: true)
    ]

  @doc """
  Adds an anonymous property of `link` content items to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)
end
