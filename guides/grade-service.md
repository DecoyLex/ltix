# Grade Service

When your tool needs to send grades back to the platform or manage
gradebook columns, use the grade service (Assignment and Grade
Services, or AGS). This guide covers the two main workflows for
working with grades in your application.

## Posting a score after launch

The simplest case: the platform created a gradebook column (line item)
for your resource link, and you just need to post a score. Authenticate
from the launch context and post directly:

```elixir
def launch(conn, params) do
  state = get_session(conn, :lti_state)
  {:ok, context} = Ltix.handle_callback(params, state)

  {:ok, score} = Ltix.GradeService.Score.new(
    user_id: context.claims.subject,
    score_given: 85,
    score_maximum: 100,
    activity_progress: :completed,
    grading_progress: :fully_graded
  )

  {:ok, client} = Ltix.GradeService.authenticate(context)
  :ok = Ltix.GradeService.post_score(client, score)

  conn
  |> put_flash(:info, "Grade submitted")
  |> redirect(to: ~p"/assignments")
end
```

Not all launches include the grade service endpoint. If the platform
didn't include it, `authenticate/2` returns a `ServiceNotAvailable`
error:

```elixir
case Ltix.GradeService.authenticate(context) do
  {:ok, client} ->
    :ok = Ltix.GradeService.post_score(client, score)

  {:error, %Ltix.Errors.Invalid.ServiceNotAvailable{}} ->
    # Grade passback not available for this launch
end
```

See [Building Scores](cookbooks/score-construction.md) for progress
tracking, extra credit, comments, and choosing progress values.

## Managing line items

When your tool needs multiple gradebook columns per resource link, or
wants to create columns on its own, use the **programmatic** workflow:

```elixir
{:ok, client} = Ltix.GradeService.authenticate(context)

{:ok, quiz_item} = Ltix.GradeService.create_line_item(client,
  label: "Quiz 1",
  score_maximum: 100,
  tag: "quiz"
)

:ok = Ltix.GradeService.post_score(client, score, line_item: quiz_item)
```

Fetch a line item before updating it to avoid overwriting fields you
didn't intend to change:

```elixir
{:ok, item} = Ltix.GradeService.get_line_item(client,
  line_item: quiz_item
)

updated = %{item | label: "Quiz 1 (Updated)", score_maximum: 120}
{:ok, item} = Ltix.GradeService.update_line_item(client, updated)
```

## Filtering line items

`list_line_items/2` supports server-side filtering:

```elixir
{:ok, items} = Ltix.GradeService.list_line_items(client,
  resource_link_id: context.claims.resource_link.id
)

{:ok, quizzes} = Ltix.GradeService.list_line_items(client,
  tag: "quiz"
)
```

## Reading results

Fetch the current grades the platform has recorded for a line item:

```elixir
{:ok, results} = Ltix.GradeService.get_results(client)

{:ok, results} = Ltix.GradeService.get_results(client,
  line_item: quiz_item,
  user_id: "12345"
)
```

> #### Sparse results {: .info}
>
> The platform may skip users who have no score yet. Do not assume
> every enrolled user will appear in the results list.

## Deleting line items

Tool-created line items can be deleted normally:

```elixir
:ok = Ltix.GradeService.delete_line_item(client, tool_created_item)
```

Deleting the **coupled** line item — the one the platform created for
the resource link — is a different story. Ltix blocks it by default
because platforms handle it inconsistently:

- **Canvas** rejects the request outright (HTTP 401)
- **Moodle and Blackboard** delete the gradebook entry entirely
- **D2L Brightspace** severs the link but preserves existing grade data

In all cases the `lineitem` URL may vanish from future launch claims,
leaving the tool unable to post scores through the coupled flow.

```elixir
# Blocked by default
{:error, %Ltix.Errors.Invalid.CoupledLineItem{}} =
  Ltix.GradeService.delete_line_item(client, coupled_item)

# Explicit opt-in when you understand the consequences
:ok = Ltix.GradeService.delete_line_item(client, coupled_item, force: true)
```

## Next steps

- [Building Scores](cookbooks/score-construction.md): progress
  values, extra credit, comments, and timestamps
- [Syncing Grades in the Background](cookbooks/background-grade-sync.md):
  posting grades from Oban workers
- [Using Canvas Grade Extensions](cookbooks/canvas-grade-extensions.md):
  submission types and metadata for Canvas
- [Advantage Services](advantage-services.md): token management,
  caching, and multi-service authentication
- `Ltix.GradeService`: full API reference and options
