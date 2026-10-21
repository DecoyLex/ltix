defmodule TestPlugins.Poll do
  @moduledoc false
  # A content item type with a presentation field, a list of nested objects, a
  # map with any keys, and no checks of its own.
  use Ltix.DeepLinking.ContentItemType,
    type: "https://vendor.example.com/poll",
    fields: [
      question: Zoi.string(description: "The question to ask."),
      title: title(),
      closes_at: Zoi.datetime(description: "When the poll closes.") |> Zoi.optional(),
      window: window(),
      choices:
        Zoi.array(Ltix.Type.object(%{choice_label: Zoi.string()}), description: "The choices.")
        |> Zoi.optional(),
      results:
        Zoi.map(Zoi.atom(), Ltix.Type.object(%{vote_count: Zoi.integer()}),
          description: "Results, keyed by the tool's names for the choices."
        )
        |> Zoi.optional()
    ]
end

defmodule TestPlugins.OtherPoll do
  @moduledoc false
  # Declares the content item type `TestPlugins.Poll` declares.
  use Ltix.DeepLinking.ContentItemType,
    type: "https://vendor.example.com/poll",
    fields: [prompt: Zoi.string()]
end

defmodule TestPlugins.Weight do
  @moduledoc false
  # A property on `ltiResourceLink` content items.
  use Ltix.DeepLinking.ContentItem.LTIResourceLink,
    property: "https://vendor.example.com/weight",
    name: :weight

  @impl Ltix.Property
  def serialize(weight, opts), do: %{"value" => weight, "unit" => Keyword.get(opts, :unit)}
end

defmodule TestPlugins.OtherWeight do
  @moduledoc false
  # Declares the property `TestPlugins.Weight` declares.
  use Ltix.DeepLinking.ContentItem.LTIResourceLink,
    property: "https://vendor.example.com/weight",
    name: :other_weight
end

defmodule TestPlugins.ItemNote do
  @moduledoc false
  # A vendor's note on Deep Linking's content item types other than
  # `ltiResourceLink`.
  use Ltix.DeepLinking.ContentItem.Link, property: "https://vendor.example.com/note", name: :note
  use Ltix.DeepLinking.ContentItem.File
  use Ltix.DeepLinking.ContentItem.HTMLFragment
  use Ltix.DeepLinking.ContentItem.Image
end
