# Advantage Services

Rules for working with LTI Advantage Services. Covers Grade Service (AGS), Memberships Service (NRPS), and OAuth token management.

## Authenticate, then call

All services follow the same pattern.

```elixir
{:ok, client} = Ltix.GradeService.authenticate(launch)
{:ok, items} = Ltix.GradeService.list_line_items(client)
```

`authenticate/2` returns an `%OAuth.Client{}` that holds the access token and the service endpoints. Pass the client to all subsequent service calls.

You can also authenticate from a `%Registration{}` directly (for background jobs).

```elixir
{:ok, client} = Ltix.MembershipsService.authenticate(registration, endpoint: endpoint)
```

## Service availability

Services are optional per-launch. **Always** handle `ServiceNotAvailable`.

```elixir
case Ltix.GradeService.authenticate(launch) do
  {:ok, client} -> Ltix.GradeService.post_score(client, score)
  {:error, %Ltix.Errors.Invalid.ServiceNotAvailable{}} -> :ok
  {:error, error} -> {:error, error}
end
```

## Token lifecycle

- Tokens typically last ~1 hour. Safe to ignore for single request handlers.
- For background jobs, check expiry before each call.

```elixir
client = Ltix.OAuth.Client.refresh!(client)
```

- Tokens are scoped to a registration (platform and client ID). Reuse across courses on the same platform with `Client.with_endpoints/3`.
- Platforms may grant fewer scopes than requested. Authentication still succeeds. Service functions validate automatically and return `ScopeMismatch` if the required scope is missing. Pass `require_all_scopes: true` to fail at authentication instead.

## Grade service

### Posting scores

```elixir
{:ok, score} = Ltix.GradeService.Score.new(
  user_id: launch.claims.subject,
  score_given: 85,
  score_maximum: 100,
  activity_progress: :completed,
  grading_progress: :fully_graded
)

:ok = Ltix.GradeService.post_score(client, score)
```

- `Score.new/1` takes a keyword list or map, validates fields, and auto-generates `:timestamp` if omitted. Timestamps are `DateTime` structs. Invalid or unknown fields return `Ltix.Errors.Invalid.InvalidField`, and `Score.new!/1` raises it.
- **Only `:fully_graded`** guarantees the grade appears in the platform's gradebook. Other grading progress values (`:pending`, `:pending_manual`, `:not_ready`, `:failed`) may be ignored by the platform.
- `score_given` can exceed `score_maximum` (extra credit is allowed).
- Activity progress enum values are `:initialized`, `:started`, `:in_progress`, `:submitted`, and `:completed`
- Grading progress enum values are `:fully_graded`, `:pending`, `:pending_manual`, `:failed`, and `:not_ready`

### Line items

**Coupled** (platform-created). The platform creates a line item for the resource link automatically. Post scores directly without specifying a line item.

**Programmatic.** The tool manages its own line items.

```elixir
{:ok, item} = Ltix.GradeService.create_line_item(client, label: "Quiz 1", score_maximum: 100)
:ok = Ltix.GradeService.post_score(client, score, line_item: item)
```

- `label` and `score_maximum` are required when creating line items.
- `score_maximum` must be a positive number.
- Per-item operations take a `line_item:` option (a URL or `%LineItem{}`) and default to the coupled line item, as in `get_line_item(client, line_item: item)`, `delete_line_item(client, line_item: item)`, and `list_results(client, line_item: item)`.
- `list_line_items/2` and `list_results/2` stop at `max_line_items` and `max_results` (both default to 10,000) and return `CollectionTooLarge` beyond them. Use `stream_line_items/2` or `stream_results/2` for large collections.
- Every operation has a raising variant, such as `post_score!/3`.

### Coupled line item deletion

**Do not** delete coupled line items, because behavior varies by platform.
- Canvas rejects deletion (HTTP 401)
- Moodle and Blackboard delete the gradebook entry entirely
- D2L removes the link but preserves grade data

Ltix blocks deletion of coupled line items by default. **Never** pass `force: true` without confirming with the user which platforms they target and that they understand the consequences.

### Platform properties

**Never** pass `extensions:` to `create_line_item/3` or `Score.new/1`. Add the plugin that declares a vendor property to `config :ltix, plugins: [...]`. Pass the property by its `:name`, and read it from `item.extensions`.

```elixir
# config/config.exs
config :ltix, plugins: [MyApp.Canvas]
```

```elixir
{:ok, item} =
  Ltix.GradeService.create_line_item(client,
    label: "Essay",
    score_maximum: 100,
    canvas_submission_type: %{type: "external_tool", external_tool_url: "https://my.tool.url/launch"}
  )

item.extensions.canvas_submission_type
```

- `Score.new/1` takes property names the same way.
- A name that's neither a field nor a declared property raises `ArgumentError` from `create_line_item/3` and returns `InvalidField` from `Score.new/1`.
- Undeclared properties are in `unrecognized`, keyed by JSON name.
- To declare a property, follow [Add a property to line items, scores, or results](https://ltix.hexdocs.pm/writing-advantage-service-plugins.md#add-a-property-to-line-items-scores-or-results).

## Memberships service

### Fetching the roster

```elixir
{:ok, client} = Ltix.MembershipsService.authenticate(launch)
{:ok, roster} = Ltix.MembershipsService.list_members(client)
```

- `list_members/2` loads the entire roster into memory (the safety limit is 10,000 members). Beyond that it returns `CollectionTooLarge`.
- For large courses, use `stream_members/2` for lazy, paginated processing.

```elixir
{:ok, stream} = Ltix.MembershipsService.stream_members(client)

stream
|> Stream.filter(&(&1.status == :active))
|> Enum.each(&process_member/1)
```

- Increase limit with `max_members:` or disable with `max_members: :infinity`.

### Filtering

- `:role` - filter server-side by role URI, such as `Ltix.Role.context_learner()`
- `:resource_link_id` - only members with access to a specific resource link

### Missing PII

Only `user_id` and `roles` are guaranteed in roster responses. Name, email, and picture depend on platform privacy settings. **Always** handle `nil` for these fields.

### Platform properties and messages

- Undeclared member properties are in `member.unrecognized`, keyed by JSON name. Read a declared property by its name, as in `member.extensions.student_number`. To declare one, follow [Add a property to members or membership containers](https://ltix.hexdocs.pm/writing-advantage-service-plugins.md#add-a-property-to-members-or-membership-containers).
- In a roster filtered by resource link, `member.message` is `nil` or a list of claim maps like `launch.claims`. Read a claim from every message with `for message <- member.message || [], do: message.custom`.

## Background service calls

**Ask the user** before implementing background service patterns. These involve architectural decisions about where to store endpoint URLs, how to schedule jobs, and how to handle token caching. The pattern below is an example to adapt.

Store the endpoint URL during the first launch for later use in background jobs.

```elixir
# During launch
url = Ltix.Launch.get_endpoint(launch, Ltix.MembershipsService).context_memberships_url
MyApp.Courses.store_memberships_url(course_id, url)

# In background job
endpoint = Ltix.MembershipsService.Endpoint.new!(stored_url)
{:ok, client} = Ltix.MembershipsService.authenticate(registration, endpoint: endpoint)
```

If the application passes `plugins:` to `Ltix.handle_callback/3`, pass the same `plugins:` when authenticating from a registration.

## Custom services

A custom service is a plugin with an endpoint claim and an `Ltix.ClientAssertion` step that adds its scope. Follow the [Building a Custom Advantage Service](https://ltix.hexdocs.pm/custom-advantage-service.md) cookbook, then authenticate with `Ltix.OAuth.authenticate(launch, services: [MyService])` and send requests with `Ltix.OAuth.Client.request(client, MyService, url: url)`.
