# Writing a Canvas Grade Plugin

Canvas adds its own properties to line items and scores. This recipe builds a plugin that adds three of them.

- `https://canvas.instructure.com/lti/submission_type` sets the submission type of the assignment Canvas creates for a new line item.
- `https://canvas.instructure.com/lti/launch_url` is the launch URL Canvas returns for a line item.
- `https://canvas.instructure.com/lti/submission` adds submission details to a score.

[Add a property to line items, scores, or results](../writing-advantage-service-plugins.md#add-a-property-to-line-items-scores-or-results) explains each option. Ltix sends a property only when the line item or score has a value for it. The properties parse with Zoi, so add `{:zoi, "~> 0.17"}` to your dependencies.

## Plugin

The launch URL and the score's submission details need only their options, so the plugin adds them with `add_property/2`.

- The launch URL is read-only, so `writes:` is `[]`.
- The submission details are separate from the score's standard `submission` field, which has the start and submission times. Your app passes them as a map, which Ltix sends as JSON. Ltix doesn't read scores, so the property has no schema.

```elixir
# lib/my_app/canvas.ex
defmodule MyApp.Canvas do
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Ltix.Plugin.new(name: "Canvas", version: "1.0.0")
    |> Ltix.Plugin.add(MyApp.Canvas.SubmissionType)
    |> Ltix.GradeService.LineItem.add_property(
      property: "https://canvas.instructure.com/lti/launch_url",
      name: :canvas_launch_url,
      schema: Zoi.string(),
      writes: []
    )
    |> Ltix.GradeService.Score.add_property(
      property: "https://canvas.instructure.com/lti/submission",
      name: :canvas_submission
    )
  end
end
```

## Submission type property

Canvas accepts the submission type only when it creates a line item, so `writes:` is `[:create]`. Your app passes and reads the type as a map with atom keys. Its `serialize/2` leaves out an `external_tool_url` the app doesn't set, so the property is a module.

```elixir
# lib/my_app/canvas/submission_type.ex
defmodule MyApp.Canvas.SubmissionType do
  use Ltix.GradeService.LineItem,
    property: "https://canvas.instructure.com/lti/submission_type",
    name: :canvas_submission_type,
    schema:
      Zoi.map(
        %{type: Zoi.string(), external_tool_url: Zoi.string() |> Zoi.optional()},
        coerce: true
      ),
    writes: [:create]

  @impl Ltix.Property
  def serialize(submission_type, _opts) do
    %{"type" => submission_type.type, "external_tool_url" => submission_type[:external_tool_url]}
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end
end
```

Add the plugin to your config.

```elixir
# config/config.exs
config :ltix, plugins: [MyApp.Canvas]
```

## Creating a line item with a submission type

```elixir
{:ok, item} =
  Ltix.GradeService.create_line_item(client,
    label: "External Assignment",
    score_maximum: 100,
    canvas_submission_type: %{
      type: "external_tool",
      external_tool_url: "https://my.tool.url/launch"
    }
  )
```

## Reading the launch URL

When the request includes `include[]=launch_url`, Canvas returns the launch URL.

```elixir
url =
  item.id
  |> URI.parse()
  |> URI.append_query("include[]=launch_url")
  |> URI.to_string()

{:ok, item} = Ltix.GradeService.get_line_item(client, line_item: url)
item.extensions.canvas_launch_url
#=> "https://my.tool.url/launch"
```

## Posting submission details

```elixir
{:ok, score} =
  Ltix.GradeService.Score.new(
    user_id: user_id,
    score_given: 85,
    score_maximum: 100,
    activity_progress: :completed,
    grading_progress: :fully_graded,
    canvas_submission: %{
      new_submission: true,
      submission_type: "online_url",
      submission_data: "https://example.com/student-work"
    }
  )

:ok = Ltix.GradeService.post_score(client, score)
```

## Next steps

- [Canvas score documentation](https://canvas.instructure.com/doc/api/score.html) - every submission field
- [Grade Service](../grade-service.md) - creating line items and posting scores
- `Ltix.Property` - the property options and callbacks
