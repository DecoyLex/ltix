# Memberships Service

When your tool needs to know who is enrolled in a course, use the
memberships service to fetch the roster from the platform. This guide
covers common patterns for working with rosters in your application.

## Fetching the roster after launch

Authenticate from the launch context and fetch the roster in your
controller:

```elixir
def launch(conn, params) do
  state = get_session(conn, :lti_state)
  {:ok, context} = Ltix.handle_callback(params, state)

  {:ok, client} = Ltix.MembershipsService.authenticate(context)
  {:ok, roster} = Ltix.MembershipsService.get_members(client)

  active_learners =
    roster
    |> Enum.filter(fn m -> m.status == :active end)
    |> Enum.filter(fn m -> Ltix.LaunchClaims.Role.learner?(m.roles) end)

  conn
  |> assign(:learners, active_learners)
  |> assign(:course_title, roster.context.title)
  |> render(:launch)
end
```

Not all launches include the memberships endpoint. If the platform
didn't include it, `authenticate/2` returns a `ServiceNotAvailable`
error. Check for this if your tool should still work without roster
access:

```elixir
case Ltix.MembershipsService.authenticate(context) do
  {:ok, client} ->
    {:ok, roster} = Ltix.MembershipsService.get_members(client)
    # use roster

  {:error, %Ltix.Errors.Invalid.ServiceNotAvailable{}} ->
    # roster not available for this launch
end
```

## Syncing rosters in the background

For scheduled syncs or Oban workers, store the endpoint URL during
the first launch and authenticate from a registration later:

```elixir
# During launch: save the endpoint URL
url = context.claims.memberships_endpoint.context_memberships_url
MyApp.Courses.store_memberships_url(course_id, url)
```

```elixir
# In a background job
alias Ltix.LaunchClaims.MembershipsEndpoint

def perform(%{args: %{"course_id" => course_id}}) do
  registration = MyApp.Courses.get_registration(course_id)
  url = MyApp.Courses.get_memberships_url(course_id)

  {:ok, client} = Ltix.MembershipsService.authenticate(registration,
    endpoint: MembershipsEndpoint.new(url)
  )

  {:ok, roster} = Ltix.MembershipsService.get_members(client)

  Enum.each(roster, fn member ->
    MyApp.Users.upsert_from_lti(course_id, %{
      lti_user_id: member.user_id,
      name: member.name,
      email: member.email,
      role: classify_role(member.roles)
    })
  end)
end

defp classify_role(roles) do
  alias Ltix.LaunchClaims.Role

  cond do
    Role.instructor?(roles) -> :instructor
    Role.teaching_assistant?(roles) -> :ta
    Role.learner?(roles) -> :learner
    true -> :other
  end
end
```

See [Advantage Services](advantage-services.md) for details on token
management and reusing tokens across courses.

## Filtering rosters

### By role

The `:role` option filters server-side, so the platform only returns
matching members:

```elixir
# Only learners
{:ok, roster} = Ltix.MembershipsService.get_members(client, role: :learner)

# Only instructors
{:ok, roster} = Ltix.MembershipsService.get_members(client, role: :instructor)
```

See [Working with Roles](working-with-roles.md) for the full role
vocabulary and predicates.

### By resource link

Retrieve only members with access to a specific resource link:

```elixir
{:ok, roster} = Ltix.MembershipsService.get_members(client,
  resource_link_id: context.claims.resource_link.id
)
```

## Handling missing PII

Only `user_id` and `roles` are guaranteed on every member. Fields
like `name`, `email`, and `picture` depend on the platform's privacy
settings. A Canvas admin must explicitly enable "include name" and
"include email" in the tool configuration.

Always handle `nil`:

```elixir
defp display_name(member) do
  member.name || member.given_name || "User #{member.user_id}"
end
```

## Large courses

`get_members/2` loads the entire roster into memory. For courses with
thousands of students, use `stream_members/2` to process members
incrementally:

```elixir
{:ok, stream} = Ltix.MembershipsService.stream_members(client)

stream
|> Stream.filter(&(&1.status == :active))
|> Enum.each(fn member ->
  MyApp.Users.upsert_from_lti(course_id, member)
end)
```

`get_members/2` includes a safety limit (default: 10,000 members) and
returns a `RosterTooLarge` error if exceeded. Increase it with
`max_members: 50_000` or disable it with `max_members: :infinity`.
For rosters of unknown size, streaming is the safer choice.

## Next steps

- [Advantage Services](advantage-services.md): token management,
  caching, and multi-service authentication
- [Working with Roles](working-with-roles.md): role predicates
  for authorization with roster members
- `Ltix.MembershipsService`: full API reference and options
- `Ltix.MembershipsService.Member`: member struct fields
