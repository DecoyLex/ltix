# Building Content Items

Common content item patterns for deep linking responses. Each section shows a self-contained example you can adapt.

## LTI resource link

The simplest content item. The platform creates a link that launches back into your tool.

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
  url: "https://tool.example.com/activities/42",
  title: "Week 3 Activity"
)
```

Omit `url` to use the tool's base launch URL configured in the platform.

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
  title: "Activity from Tool"
)
```

## Resource link with a line item

Include a `line_item` to ask the platform to create a line item for the link. The platform can ignore the request. When it creates the line item, post scores to it with the grade service.

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
  url: "https://tool.example.com/quizzes/7",
  title: "Midterm Quiz",
  line_item: [
    score_maximum: 100,
    label: "Midterm Quiz",
    tag: "quiz",
    grades_released: true
  ]
)
```

`score_maximum` is required and must be positive. The `label` defaults to the content item's title if omitted, and must not be blank when given. `link.line_item` is an `Ltix.DeepLinking.LineItem`.

`line_item` also accepts an `Ltix.GradeService.LineItem`. Deep linking can only send `label`, `score_maximum`, `resource_id`, `tag`, and `grades_released`, so a line item that sets any other field, such as `id`, returns an error.

## Resource link with custom properties

Custom properties are sent to your tool on every launch of the created link. Pass them as a keyword list or a map with string or atom keys. Values must be strings.

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
  url: "https://tool.example.com/assignments",
  title: "Essay Submission",
  custom: [
    assignment_id: "essay-3",
    rubric: "standard",
    allow_late: "true"
  ]
)
```

## Setting availability windows

Control when the link is accessible and when submissions are accepted.

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
  url: "https://tool.example.com/exams/final",
  title: "Final Exam",
  available: [
    start_date_time: ~U[2025-05-01 08:00:00Z],
    end_date_time: ~U[2025-05-01 12:00:00Z]
  ],
  submission: [
    end_date_time: ~U[2025-05-01 11:30:00Z]
  ]
)
```

Both fields in each window are optional. You can set just an end time and leave the start unset.

## External link

For URLs outside your tool. Use `Link` when the resource isn't an LTI launch.

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.Link.new(
  url: "https://docs.example.com/getting-started",
  title: "Getting Started Guide",
  icon: [url: "https://docs.example.com/favicon.png", width: 32, height: 32]
)
```

Control how the platform opens the link with `window` or `iframe`.

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.Link.new(
  url: "https://videos.example.com/lecture-5",
  title: "Lecture 5 Recording",
  iframe: [src: "https://videos.example.com/embed/lecture-5", width: 800, height: 450]
)
```

Include embeddable HTML with `embed`.

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.Link.new(
  url: "https://interactive.example.com/sim/42",
  title: "Physics Simulation",
  embed: [html: ~s(<iframe src="https://interactive.example.com/embed/42"></iframe>)]
)
```

## File with expiry

File URLs are expected to be short-lived. Set `expires_at` to send the platform the time the URL stops working.

```elixir
{:ok, file} = Ltix.DeepLinking.ContentItem.File.new(
  url: "https://tool.example.com/exports/report-abc123.pdf",
  title: "Lab Report Template",
  media_type: "application/pdf",
  expires_at: ~U[2025-03-15 12:00:00Z]
)
```

## HTML fragment

Inline HTML the platform embeds directly in its page.

```elixir
{:ok, fragment} = Ltix.DeepLinking.ContentItem.HTMLFragment.new(
  html: """
  <div class="tool-widget">
    <h3>Study Flashcards</h3>
    <p>25 cards covering Chapter 4</p>
  </div>
  """,
  title: "Chapter 4 Flashcards"
)
```

> #### Prefer Link with embed {: .tip}
>
> If your HTML renders a single resource that also has a direct URL, use `Link` with an `embed`. This gives the platform both the embeddable HTML and a fallback URL.

## Image

An image the platform renders directly with an `img` tag.

```elixir
{:ok, image} = Ltix.DeepLinking.ContentItem.Image.new(
  url: "https://tool.example.com/diagrams/architecture.png",
  title: "System Architecture",
  width: 1200,
  height: 800
)
```

Include a thumbnail for list views.

```elixir
{:ok, image} = Ltix.DeepLinking.ContentItem.Image.new(
  url: "https://tool.example.com/photos/lab-setup.jpg",
  title: "Lab Setup Photo",
  thumbnail: [
    url: "https://tool.example.com/photos/lab-setup-thumb.jpg",
    width: 150,
    height: 100
  ]
)
```

## Vendor property

Add the plugin that declares a vendor property to `config :ltix, plugins: [...]`, then pass the property to `new/1` by its property name.

```elixir
{:ok, link} =
  Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
    url: "https://tool.example.com/activity/5",
    title: "Proctored Exam",
    proctoring_minutes: 90
  )
```

A property of the link's line item goes with the line item's fields.

```elixir
{:ok, link} =
  Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
    title: "Essay",
    line_item: [score_maximum: 100, grading_scheme: "letter"]
  )
```

The response sends each property under its JSON name. To declare a property, see [Add a property to a content item type](../writing-deep-linking-plugins.md#add-a-property-to-a-content-item-type).

## Custom content item type

To return content that Deep Linking doesn't define, such as a poll, declare a content item type. Use a URL you control as its `type`. Fields are Zoi schemas. Add `{:zoi, "~> 0.17"}` to your dependencies.

```elixir
defmodule MyApp.Poll do
  @moduledoc "A poll the platform shows to learners."

  use Ltix.DeepLinking.ContentItemType,
    type: "https://myapp.example.com/poll",
    fields: [
      question: Zoi.string(description: "The question to ask."),
      choices: Zoi.list(Zoi.string(), description: "The answers to choose from."),
      title: title(),
      window: window(),
      closes_at: Zoi.datetime(description: "When the poll closes.") |> Zoi.optional()
    ]

  @impl Ltix.DeepLinking.ContentItemType
  def check(%__MODULE__{window: window}, %Ltix.DeepLinking.Settings{auto_create: true})
      when window != nil,
      do: {:error, MyApp.PollWindowNotAllowed.exception([])}

  def check(_poll, _settings), do: :ok
end

defmodule MyApp.PollWindowNotAllowed do
  defexception [:index]

  @impl Exception
  def message(%{index: index}),
    do: "The poll at index #{index} opens a window, which auto-created content can't use"
end
```

`use` imports the fields content item types share, such as `title()` and `window()`. `check/2` rejects a poll with a window when `auto_create` is `true`, which means the platform adds content without asking the user. Ltix sets the error's `index`.

Add the type to a plugin with `Ltix.Plugin.add/2`, and enable the plugin in your configuration. [Write a plugin](../writing-plugins.md#write-a-plugin) shows how.

The platform must accept the poll's `type` and the `window` presentation target.

```elixir
{:ok, poll} =
  MyApp.Poll.new(
    question: "Which topic next?",
    choices: ["Recursion", "Streams"],
    window: [target_name: "poll"],
    closes_at: ~U[2025-03-15 12:00:00Z]
  )

{:ok, response} = Ltix.DeepLinking.build_response(launch, [poll])
```

The response sends fields under their camelCase names.

```json
{
  "type": "https://myapp.example.com/poll",
  "question": "Which topic next?",
  "choices": ["Recursion", "Streams"],
  "window": {"targetName": "poll"},
  "closesAt": "2025-03-15T12:00:00Z"
}
```

## Returning multiple items

Pass a list of mixed content item types to `build_response/3`.

```elixir
{:ok, quiz} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
  url: "https://tool.example.com/quizzes/1",
  title: "Quiz 1",
  line_item: [score_maximum: 50]
)

{:ok, reading} = Ltix.DeepLinking.ContentItem.Link.new(
  url: "https://docs.example.com/chapter-3",
  title: "Chapter 3 Reading"
)

{:ok, response} = Ltix.DeepLinking.build_response(launch, [quiz, reading],
  message: "Added 2 items"
)
```

Check `settings.accept_multiple` before offering multi-select. If `accept_multiple` is `false`, `build_response/3` returns a `ContentItemsExceedLimit` error for more than one item.

## Returning no items

Return an empty list with a message when the user cancels or an error occurs.

```elixir
# User cancelled
{:ok, response} = Ltix.DeepLinking.build_response(launch, [],
  message: "No items selected"
)

# Something went wrong
{:ok, response} = Ltix.DeepLinking.build_response(launch, [],
  error_message: "Could not load available activities",
  error_log: "ActivityService returned 503"
)
```

An empty items list is always valid regardless of platform constraints.
