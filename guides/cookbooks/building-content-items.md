# Building Content Items

Common content item patterns for deep linking responses. Each section
shows a self-contained example you can adapt.

## LTI resource link

The simplest content item. The platform creates a link that launches
back into your tool:

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.LtiResourceLink.new(
  url: "https://tool.example.com/activities/42",
  title: "Week 3 Activity"
)
```

Omit `url` to use the tool's base launch URL configured in the
platform:

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.LtiResourceLink.new(
  title: "Activity from Tool"
)
```

## Resource link with a line item

Include a `line_item` so the platform auto-creates a gradebook column.
You can then post scores to it using the grade service:

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.LtiResourceLink.new(
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

`score_maximum` is required and must be positive. The `label` defaults
to the content item's title if omitted.

## Resource link with custom parameters

Custom parameters are passed to your tool on every launch of the
created link. Both keys and values must be strings:

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.LtiResourceLink.new(
  url: "https://tool.example.com/assignments",
  title: "Essay Submission",
  custom: %{
    "assignment_id" => "essay-3",
    "rubric" => "standard",
    "allow_late" => "true"
  }
)
```

## Setting availability windows

Control when the link is accessible and when submissions are accepted:

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.LtiResourceLink.new(
  url: "https://tool.example.com/exams/final",
  title: "Final Exam",
  available: [
    start_date_time: "2025-05-01T08:00:00Z",
    end_date_time: "2025-05-01T12:00:00Z"
  ],
  submission: [
    end_date_time: "2025-05-01T11:30:00Z"
  ]
)
```

Both fields in each window are optional. You can set just an end time
to leave the start open.

## External link

For URLs outside your tool. Use `Link` instead of `LtiResourceLink`
when the resource isn't an LTI launch:

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.Link.new(
  url: "https://docs.example.com/getting-started",
  title: "Getting Started Guide",
  icon: [url: "https://docs.example.com/favicon.png", width: 32, height: 32]
)
```

Control how the platform opens the link with `window` or `iframe`:

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.Link.new(
  url: "https://videos.example.com/lecture-5",
  title: "Lecture 5 Recording",
  iframe: [src: "https://videos.example.com/embed/lecture-5", width: 800, height: 450]
)
```

Include embeddable HTML with `embed`:

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.Link.new(
  url: "https://interactive.example.com/sim/42",
  title: "Physics Simulation",
  embed: [html: ~s(<iframe src="https://interactive.example.com/embed/42"></iframe>)]
)
```

## File with expiry

File URLs are expected to be short-lived. Set `expires_at` to tell the
platform when the URL stops working:

```elixir
{:ok, file} = Ltix.DeepLinking.ContentItem.File.new(
  url: "https://tool.example.com/exports/report-abc123.pdf",
  title: "Lab Report Template",
  media_type: "application/pdf",
  expires_at: "2025-03-15T12:00:00Z"
)
```

## HTML fragment

Inline HTML the platform embeds directly in its page:

```elixir
{:ok, fragment} = Ltix.DeepLinking.ContentItem.HtmlFragment.new(
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
> If your HTML renders a single resource that also has a direct URL,
> use `Link` with an `embed` instead. This gives the platform both the
> embeddable HTML and a fallback URL.

## Image

An image the platform renders directly with an `img` tag:

```elixir
{:ok, image} = Ltix.DeepLinking.ContentItem.Image.new(
  url: "https://tool.example.com/diagrams/architecture.png",
  title: "System Architecture",
  width: 1200,
  height: 800
)
```

Include a thumbnail for list views:

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

## Using extensions

Add vendor-specific properties keyed by fully qualified URLs. Extensions
are merged into the top-level JSON output:

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.LtiResourceLink.new(
  url: "https://tool.example.com/activity/5",
  title: "Proctored Exam",
  extensions: %{
    "https://vendor.example.com/proctoring" => %{
      "required" => true,
      "duration_minutes" => 90
    }
  }
)
```

All five content item types support the `extensions` field.

## Returning multiple items

Pass a list of mixed content item types to `build_response/3`:

```elixir
{:ok, quiz} = Ltix.DeepLinking.ContentItem.LtiResourceLink.new(
  url: "https://tool.example.com/quizzes/1",
  title: "Quiz 1",
  line_item: [score_maximum: 50]
)

{:ok, reading} = Ltix.DeepLinking.ContentItem.Link.new(
  url: "https://docs.example.com/chapter-3",
  title: "Chapter 3 Reading"
)

{:ok, response} = Ltix.DeepLinking.build_response(context, [quiz, reading],
  msg: "Added 2 items"
)
```

Check `settings.accept_multiple` before offering multi-select. If
`accept_multiple` is `false`, `build_response/3` returns a
`ContentItemsExceedLimit` error for more than one item.

## Returning no items

Return an empty list with a message when the user cancels or an error
occurs:

```elixir
# User cancelled
{:ok, response} = Ltix.DeepLinking.build_response(context, [],
  msg: "No items selected"
)

# Something went wrong
{:ok, response} = Ltix.DeepLinking.build_response(context, [],
  error_message: "Could not load available activities",
  error_log: "ActivityService returned 503"
)
```

An empty items list is always valid regardless of platform constraints.
