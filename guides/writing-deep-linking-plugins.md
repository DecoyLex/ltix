# Writing Deep Linking Plugins

A plugin can add content item types, add properties to content items and their line items, and add claims to Deep Linking responses. [Writing Plugins](writing-plugins.md) covers writing and enabling a plugin.

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

## Add a property to Deep Linking line items

A resource link's line item is an `Ltix.DeepLinking.LineItem`, which takes its own properties. Add one with `Ltix.DeepLinking.LineItem.add_property/2`, which takes the same options as a content item type's `add_property/2`.

Submission Review defines `submissionReview` on both kinds of line item, as an object. Its property is a module that `use`s each line item type, and converts the object with `Ltix.Type`.

```elixir
defmodule Review.SubmissionReview do
  use Ltix.GradeService.LineItem,
    property: "submissionReview",
    name: :submission_review

  use Ltix.DeepLinking.LineItem

  use Ltix.Type,
    json_keys: :camel_case,
    fields: [
      reviewable_status: Zoi.list(Zoi.string()) |> Zoi.optional(),
      label: Zoi.string() |> Zoi.optional(),
      url: Zoi.string() |> Zoi.optional(),
      custom: Zoi.map(Zoi.string(), Zoi.string()) |> Zoi.optional()
    ]

  @impl Ltix.Property
  def parse(json, _opts), do: Ltix.Type.from_json(__MODULE__, json)

  @impl Ltix.Property
  def serialize(review, _opts), do: Ltix.Type.to_json(review)
end
```

`use Ltix.Type` defines the struct from Zoi schemas. `Ltix.Type.from_json/3` and `Ltix.Type.to_json/3` convert it from and to JSON, with camelCase names such as `reviewableStatus`.

Pass the property's options to the first `use` only. An application passes the value by name with the line item's fields.

```elixir
{:ok, link} =
  Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
    url: "https://tool.example.com/essays/7",
    line_item: [
      label: "Essay",
      score_maximum: 10,
      submission_review: %Review.SubmissionReview{reviewable_status: ["Submitted"]}
    ]
  )
```

When a property's [`:writes`](`m:Ltix.Property#module-options`) option has `:create`, a Deep Linking response includes the property. `:writes` defaults to `[:create, :update]`.

`LTIResourceLink.new/1` also takes a grade service line item, and copies its properties to the Deep Linking line item by name. It returns an error for a property that no plugin declares on Deep Linking line items.

## Add claims to Deep Linking responses

`Ltix.DeepLinking.Response.add_step/2` adds a step that changes the response's claims before Ltix signs them.

```elixir
@impl Ltix.Plugin
def plugin(_opts) do
  Ltix.Plugin.new(name: "Polls", version: "1.0.0")
  |> Ltix.Plugin.add(Polls.Poll)
  |> Ltix.DeepLinking.Response.add_step(fn response ->
    items = response.claims["https://purl.imsglobal.org/spec/lti-dl/claim/content_items"]
    {:ok, put_in(response.claims["https://polls.example.com/claim/poll_count"], length(items))}
  end)
end
```

`response.claims` has every claim by name, including the content items as JSON. `response.launch` is the Deep Linking request's launch. Steps run only when every content item passes its checks. When a step records an error, `build_response/3` returns it and signs nothing. A step that other steps order against is a module that calls `use Ltix.DeepLinking.Response`.

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
  assert claims["https://polls.example.com/claim/poll_count"] == 1
end
```

## Next steps

- `Ltix.DeepLinking.ContentItemType` and `Ltix.DeepLinking.Response` for the full contracts
- [Building Content Items](cookbooks/building-content-items.md) for Deep Linking's content item types and a complete custom one
