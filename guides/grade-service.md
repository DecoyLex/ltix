# Grade Service

When your tool needs to send grades back to the platform or manage line items, use the grade service (Assignment and Grade Services, or AGS). This guide covers the two main workflows for working with grades in your application.

## Posting a score after launch

When the platform created a line item for your resource link, authenticate from the launch and post a score.

```elixir
def launch(conn, params) do
  state = get_session(conn, :lti_state)
  {:ok, launch} = Ltix.handle_callback(params, state)

  {:ok, score} = Ltix.GradeService.Score.new(
    user_id: launch.claims.subject,
    score_given: 85,
    score_maximum: 100,
    activity_progress: :completed,
    grading_progress: :fully_graded
  )

  {:ok, client} = Ltix.GradeService.authenticate(launch)
  :ok = Ltix.GradeService.post_score(client, score)

  conn
  |> put_flash(:info, "Grade submitted")
  |> redirect(to: ~p"/assignments")
end
```

Not all launches include the grade service endpoint. If the platform didn't include it, `authenticate/2` returns a `ServiceNotAvailable` error.

```elixir
case Ltix.GradeService.authenticate(launch) do
  {:ok, client} ->
    :ok = Ltix.GradeService.post_score(client, score)

  {:error, %Ltix.Errors.Invalid.ServiceNotAvailable{}} ->
    # Grade passback not available for this launch
    :ok
end
```

See [Building Scores](cookbooks/score-construction.md) for progress tracking, extra credit, comments, and choosing progress values.

## Managing line items

When your tool needs multiple line items per resource link, or creates line items on its own, use the **programmatic** workflow.

```elixir
{:ok, client} = Ltix.GradeService.authenticate(launch)

{:ok, quiz_item} = Ltix.GradeService.create_line_item(client,
  label: "Quiz 1",
  score_maximum: 100,
  tag: "quiz"
)

:ok = Ltix.GradeService.post_score(client, score, line_item: quiz_item)
```

`create_line_item/3` also takes a `%Ltix.GradeService.LineItem{}` as its second argument.

Fetch a line item before updating it to avoid overwriting fields you didn't intend to change.

```elixir
{:ok, item} = Ltix.GradeService.get_line_item(client,
  line_item: quiz_item
)

updated = %{item | label: "Quiz 1 (Updated)", score_maximum: 120}
{:ok, item} = Ltix.GradeService.update_line_item(client, updated)
```

## Filtering line items

`list_line_items/2` supports server-side filtering.

```elixir
{:ok, items} = Ltix.GradeService.list_line_items(client,
  resource_link_id: launch.claims.resource_link.id
)

{:ok, quizzes} = Ltix.GradeService.list_line_items(client,
  tag: "quiz"
)
```

## Reading results

Fetch the current grades the platform has recorded for a line item. Without a `line_item:` option, grade operations use the coupled line item from the launch.

```elixir
{:ok, results} = Ltix.GradeService.list_results(client)

{:ok, results} = Ltix.GradeService.list_results(client,
  line_item: quiz_item,
  user_id: "12345"
)
```

> #### Sparse results {: .info}
>
> The platform may omit users who have no score yet. Do not assume every enrolled user will appear in the results list.

## Streaming large collections

`list_line_items/2` and `list_results/2` fetch every page before returning and stop with a `CollectionTooLarge` error after 10,000 entries. Raise the limit with `max_line_items:` or `max_results:`, or pass `:infinity` to disable it. For collections of unknown size, use a stream.

```elixir
{:ok, stream} = Ltix.GradeService.stream_results(client, line_item: quiz_item)

stream
|> Stream.filter(&(&1.result_score != nil))
|> Enum.each(&record_result/1)
```

`stream_line_items/2` works the same way for line items. Pages are fetched as the stream is consumed, and a failure on a later page raises during enumeration.

## Deleting line items

Tool-created line items can be deleted normally.

```elixir
:ok = Ltix.GradeService.delete_line_item(client, line_item: tool_created_item)
```

Deleting the **coupled** line item (the one the platform created for the resource link) is blocked by default because platforms handle it inconsistently.

- **Canvas** rejects the request with HTTP 401, which returns `Ltix.Errors.Security.AccessDenied`
- **Moodle and Blackboard** delete the gradebook entry entirely
- **D2L Brightspace** removes the link but keeps existing grade data

In all cases the `line_item` URL may be absent from future launch claims, leaving the tool unable to post scores through the coupled flow.

```elixir
# Blocked by default
{:error, %Ltix.Errors.Invalid.CoupledLineItem{}} =
  Ltix.GradeService.delete_line_item(client, line_item: coupled_item)

# Explicit opt-in when you understand the consequences
:ok = Ltix.GradeService.delete_line_item(client, line_item: coupled_item, force: true)
```

## Platform properties

Platforms add properties of their own to line items, scores, and results, such as the submission type of a Canvas assignment. Each one needs a plugin that declares it, like the one [Writing a Canvas Grade Plugin](cookbooks/canvas-grade-plugin.md) builds. Add the plugin to `config :ltix, plugins: [...]`. Then pass each property by name, such as `:canvas_submission_type`, and read it from `item.extensions`.

```elixir
{:ok, item} =
  Ltix.GradeService.create_line_item(client,
    label: "Essay",
    score_maximum: 100,
    canvas_submission_type: %{
      type: "external_tool",
      external_tool_url: "https://tool.example.com/launch"
    }
  )

item.extensions.canvas_submission_type.type
#=> "external_tool"
```

`Score.new/1` takes property names the same way. Properties no plugin declares are in the struct's `unrecognized`, keyed by JSON name.

## Next steps

- [Building Scores](cookbooks/score-construction.md) - progress values, extra credit, comments, and timestamps
- [Syncing Grades in the Background](cookbooks/background-grade-sync.md) - posting grades from Oban workers
- [Writing a Canvas Grade Plugin](cookbooks/canvas-grade-plugin.md) - submission types and metadata for Canvas
- [Advantage Services](advantage-services.md) - token management, caching, and multi-service authentication
- `Ltix.GradeService` - full API reference and options
