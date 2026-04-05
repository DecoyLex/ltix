# Advantage Services

Rules for working with LTI Advantage Services: Grade Service (AGS), Memberships Service
(NRPS), and OAuth token management.

## Authenticate-Then-Call Pattern

All services follow the same pattern:

```elixir
{:ok, client} = Ltix.GradeService.authenticate(context)
{:ok, items} = Ltix.GradeService.list_line_items(client)
```

`authenticate/2` returns an `%OAuth.Client{}` with the access token and endpoints baked in.
Pass the client to all subsequent service calls.

You can also authenticate from a `%Registration{}` directly (for background jobs):

```elixir
{:ok, client} = Ltix.MembershipsService.authenticate(registration, endpoint: endpoint)
```

## Service Availability

Services are optional per-launch. **Always** handle `ServiceNotAvailable`:

```elixir
case Ltix.GradeService.authenticate(context) do
  {:ok, client} -> # use it
  {:error, %Ltix.Errors.Invalid.ServiceNotAvailable{}} -> # degrade gracefully
end
```

## Token Lifecycle

- Tokens typically last ~1 hour. Safe to ignore for single request handlers.
- For background jobs, check expiry before each call:

```elixir
client = Ltix.OAuth.Client.refresh!(client)
```

- Tokens are scoped to a registration (platform + client_id), not a course. Reuse across
  courses on the same platform with `Client.with_endpoints/2`.
- Platforms may grant fewer scopes than requested. Service functions validate automatically
  and return `ScopeMismatch` if the required scope is missing.

## Grade Service

### Posting Scores

```elixir
{:ok, score} = Ltix.GradeService.Score.new(
  user_id: context.claims.subject,
  score_given: 85,
  score_maximum: 100,
  activity_progress: :completed,
  grading_progress: :fully_graded
)

:ok = Ltix.GradeService.post_score(client, score)
```

- `Score.new/1` validates fields and auto-generates `:timestamp` if omitted.
- **Only `:fully_graded`** guarantees the grade appears in the platform's gradebook. Other
  grading progress values (`:pending`, `:pending_manual`, `:not_ready`, `:failed`) may be
  ignored by the platform.
- `score_given` can exceed `score_maximum` (extra credit is allowed).
- Activity progress enum: `:initialized`, `:started`, `:in_progress`, `:submitted`, `:completed`
- Grading progress enum: `:fully_graded`, `:pending`, `:pending_manual`, `:failed`, `:not_ready`

### Line Items

**Coupled** (platform-created): The platform creates a line item for the resource link
automatically. Post scores directly without specifying a line item.

**Programmatic**: The tool manages its own line items:

```elixir
{:ok, item} = Ltix.GradeService.create_line_item(client, label: "Quiz 1", score_maximum: 100)
:ok = Ltix.GradeService.post_score(client, score, line_item: item)
```

- `label` and `score_maximum` are required when creating line items.
- `score_maximum` must be a positive number.

### Coupled Line Item Deletion

**Do not** delete coupled line items — behavior varies wildly by platform:
- Canvas: rejects deletion (HTTP 401)
- Moodle/Blackboard: deletes the gradebook entry entirely
- D2L: severs the link but preserves grade data

Ltix blocks deletion of coupled line items by default. **Never** pass `force: true`
without confirming with the user which LMS platforms they target and that they understand
the consequences.

### Canvas Extensions

Pass Canvas-specific properties via `:extensions`:

```elixir
{:ok, score} = Ltix.GradeService.Score.new(
  user_id: user_id,
  score_given: 90,
  score_maximum: 100,
  activity_progress: :completed,
  grading_progress: :fully_graded,
  extensions: %{
    "https://canvas.instructure.com/lti/submission_type" => %{
      "type" => "external_tool",
      "external_tool_url" => "https://my.tool.url/launch"
    }
  }
)
```

## Memberships Service

### Fetching Roster

```elixir
{:ok, client} = Ltix.MembershipsService.authenticate(context)
{:ok, roster} = Ltix.MembershipsService.get_members(client)
```

- `get_members/2` loads the entire roster into memory (safety limit: 10,000 members).
- For large courses, use `stream_members/2` for lazy, paginated processing:

```elixir
{:ok, stream} = Ltix.MembershipsService.stream_members(client)

stream
|> Stream.filter(&(&1.status == :active))
|> Enum.each(&process_member/1)
```

- Increase limit with `max_members:` or disable with `max_members: :infinity`.

### Filtering

- `:role` — filter server-side (`:learner`, `:instructor`, etc.)
- `:resource_link_id` — only members with access to a specific resource link

### Missing PII

Only `user_id` and `roles` are guaranteed in roster responses. Name, email, and picture
depend on platform privacy settings. **Always** handle `nil` for these fields.

## Background Service Calls

**Ask the user** before implementing background service patterns — these involve
architectural decisions about where to store endpoint URLs, how to schedule jobs, and
how to handle token caching. The pattern below is a starting point, not a prescription.

Store the endpoint URL during the first launch for later use in background jobs:

```elixir
# During launch
url = context.claims.memberships_endpoint.context_memberships_url
MyApp.Courses.store_memberships_url(course_id, url)

# In background job
endpoint = Ltix.LaunchClaims.MembershipsEndpoint.new(stored_url)
{:ok, client} = Ltix.MembershipsService.authenticate(registration, endpoint: endpoint)
```
