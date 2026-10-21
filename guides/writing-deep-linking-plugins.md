# Writing Deep Linking Plugins

A plugin can add content item types, and add properties to content items. [Writing Plugins](writing-plugins.md) covers writing and enabling a plugin.

## Declare a content item type

A module declares a content item type with `use Ltix.DeepLinking.ContentItemType`, its `type` string, and its fields as Zoi schemas.

```elixir
defmodule Polls.Poll do
  @moduledoc "A poll the platform shows to learners."

  use Ltix.DeepLinking.ContentItemType,
    type: "https://polls.example.com/poll",
    fields: [
      question: Zoi.string(description: "The question to ask."),
      title: title(),
      window: window(),
      closes_at: Zoi.datetime(description: "When the poll closes.") |> Zoi.optional()
    ]
end

defmodule Polls do
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Ltix.Plugin.new(name: "Polls", version: "1.0.0")
    |> Ltix.Plugin.add(Polls.Poll)
  end
end
```

- `use` defines the struct, `new/1`, and `new!/1`. Override `new/1` to accept other input, and call `super/1` to build the item.
- `use` imports the fields content item types share, such as `title()`, `window()`, and `iframe()`, from `Ltix.DeepLinking.ContentItemType.Fields`.
- Fields are sent under the camelCase form of their names, such as `closesAt`. `json_key:` metadata sets another name. A field with `metadata: [json_key: "room_name"]` is sent under `room_name`.
- The moduledoc gets a Fields section with each field's `description:`.

`Ltix.DeepLinking.build_response/3` checks your items' `type` against `accept_types`, and their `window`, `iframe`, or `embed` against the accepted presentation targets. For a check of your own, implement `c:Ltix.DeepLinking.ContentItemType.check/2`. It receives the content item and the `Ltix.DeepLinking.Settings`. This one rejects a poll that opens a window when the platform creates content without asking the user.

```elixir
@impl Ltix.DeepLinking.ContentItemType
def check(%__MODULE__{window: window}, %Ltix.DeepLinking.Settings{auto_create: true})
    when window != nil,
    do: {:error, Polls.WindowNotAllowed.exception([])}

def check(_poll, _settings), do: :ok
```

When the returned exception has an `index` field set to `nil`, Ltix sets it to the item's position. [Building Content Items](cookbooks/building-content-items.md#custom-content-item-type) has the complete type with its exception.

## Add a property to a content item type

Add a property to one of Deep Linking's content item types with the type's `add_property/2`, passing the property's JSON name as `property:` and its name as `name:`.

```elixir
def plugin(_opts) do
  Ltix.Plugin.new(name: "Polls", version: "1.0.0")
  |> Ltix.DeepLinking.ContentItem.LTIResourceLink.add_property(
    property: "https://polls.example.com/weight",
    name: :poll_weight
  )
end
```

An application passes the value to the type's `new/1` by name.

```elixir
{:ok, link} =
  Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
    url: "https://tool.example.com/polls/7",
    poll_weight: 2
  )
```

A property whose value needs converting before Ltix sends it is a module that calls `use` with the type's module and implements `c:Ltix.Property.serialize/2`. `Ltix.Property` describes its options and callbacks.

```elixir
defmodule Polls.Weight do
  use Ltix.DeepLinking.ContentItem.LTIResourceLink,
    property: "https://polls.example.com/weight",
    name: :poll_weight

  @impl Ltix.Property
  def serialize(weight, _opts), do: %{"value" => weight, "unit" => "points"}
end
```

## Test Deep Linking responses

This test uses the setup from [Test a plugin](writing-plugins.md#test-a-plugin).

Build the Deep Linking launch with your plugin, and read the signed response with `Ltix.Test.verify_deep_linking_response/2`.

```elixir
test "sends a poll", %{platform: platform} do
  launch =
    Ltix.Test.build_launch(platform,
      message_type: :deep_linking,
      deep_linking_settings: %{accept_types: ["https://polls.example.com/poll"]},
      plugins: [Polls]
    )

  assert {:ok, response} =
           Ltix.DeepLinking.build_response(launch, [Polls.Poll.new!(question: "Ready?")])

  {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, response.jwt)
  [poll] = claims["https://purl.imsglobal.org/spec/lti-dl/claim/content_items"]
  assert poll["question"] == "Ready?"
end
```

## Next steps

- `Ltix.DeepLinking.ContentItemType` for the full contract
- [Building Content Items](cookbooks/building-content-items.md) for Deep Linking's content item types and a complete custom one
