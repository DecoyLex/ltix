# Advantage Services

After a successful launch, your tool can call back into the platform
to query rosters, post grades, or manage content. These platform APIs
are called Advantage services. This guide covers authenticating to
them and managing tokens in your application.

## Calling a service after launch

A launch gives you a `%LaunchContext{}` containing the platform's
service endpoints. Authenticate and call a service directly in your
controller:

```elixir
def launch(conn, params) do
  state = get_session(conn, :lti_state)
  {:ok, context} = Ltix.handle_callback(params, state)

  # Authenticate to the memberships service
  case Ltix.MembershipsService.authenticate(context) do
    {:ok, client} ->
      {:ok, roster} = Ltix.MembershipsService.get_members(client)

      conn
      |> assign(:roster, roster)
      |> assign(:context, context)
      |> render(:launch)

    {:error, %Ltix.Errors.Invalid.ServiceNotAvailable{}} ->
      # Platform didn't include the memberships endpoint in this launch
      conn
      |> assign(:roster, nil)
      |> assign(:context, context)
      |> render(:launch)
  end
end
```

Each service provides an `authenticate/2` shorthand that extracts the
endpoint from launch claims and acquires a token in one step. See
[Memberships Service](memberships-service.md) for the full roster API.

## Background service calls

Outside of a launch, you won't have a `%LaunchContext{}`. Instead,
authenticate directly with a registration and a stored endpoint URL:

```elixir
alias Ltix.LaunchClaims.MembershipsEndpoint

endpoint = MembershipsEndpoint.new(stored_memberships_url)

{:ok, client} = Ltix.MembershipsService.authenticate(registration,
  endpoint: endpoint
)

{:ok, roster} = Ltix.MembershipsService.get_members(client)
```

Store the endpoint URL when you first see it during a launch, then
use it later in background jobs:

```elixir
# During launch: save the endpoint URL for later
url = context.claims.memberships_endpoint.context_memberships_url
MyApp.Courses.store_memberships_url(course_id, url)

# In an Oban worker: use the stored URL
def perform(%{args: %{"course_id" => course_id}}) do
  url = MyApp.Courses.get_memberships_url(course_id)
  registration = MyApp.Courses.get_registration(course_id)
  endpoint = MembershipsEndpoint.new(url)

  {:ok, client} = Ltix.MembershipsService.authenticate(registration,
    endpoint: endpoint
  )

  {:ok, roster} = Ltix.MembershipsService.get_members(client)
  MyApp.Courses.sync_roster(course_id, roster)
end
```

## Managing tokens

Tokens are not refreshed automatically. For a single request handler,
tokens last long enough that you don't need to worry about expiry.
For long-running processes, check before each operation:

```elixir
alias Ltix.OAuth.Client

client =
  if Client.expired?(client) do
    Client.refresh!(client)
  else
    client
  end
```

> #### Token lifetime {: .info}
>
> Tokens typically last about 1 hour. For request handlers that
> authenticate and immediately call a service, expiry is not a
> concern. For background jobs that run longer, check expiry between
> operations.

## Reusing tokens across courses

A token is scoped to a registration (platform + client_id), not to a
specific course. If your tool syncs multiple courses on the same
platform, you can reuse one token:

```elixir
# Authenticate once
{:ok, client} = Ltix.MembershipsService.authenticate(registration,
  endpoint: course_a_endpoint
)

# Switch to a different course without re-authenticating
{:ok, client_b} = Client.with_endpoints(client, %{
  Ltix.MembershipsService => course_b_endpoint
})

{:ok, roster_b} = Ltix.MembershipsService.get_members(client_b)
```

For caching tokens across processes and other advanced patterns, see
[Token Caching and Reuse](cookbooks/token-caching-and-reuse.md).

## Multiple services in one token

If your tool calls multiple services, request all scopes in a single
token by passing multiple endpoints:

```elixir
{:ok, client} = Ltix.OAuth.authenticate(registration,
  endpoints: %{
    Ltix.MembershipsService => memberships_endpoint,
    Ltix.GradeService => ags_endpoint
  }
)

# The same client works for both services
{:ok, roster} = Ltix.MembershipsService.get_members(client)
:ok = Ltix.GradeService.post_score(client, score)
```

> #### Scope negotiation {: .warning}
>
> Platforms may grant fewer scopes than requested. Service functions
> check scopes automatically and return a `ScopeMismatch` error if
> the required scope was not granted.

## Custom platform APIs

If your platform exposes proprietary APIs (e.g., proctoring,
analytics), you can plug them into the same authentication flow by
implementing the `Ltix.AdvantageService` behaviour. See
`Ltix.AdvantageService` for a full example.

## Next steps

- [Memberships Service](memberships-service.md): querying course
  rosters
- [Grade Service](grade-service.md): posting grades and managing
  line items
- [JWK Management](jwk-management.md): managing the key pairs
  used for authentication
- [Token Caching and Reuse](cookbooks/token-caching-and-reuse.md):
  batch refreshing, multi-course tokens, and ETS caching
- [Error Handling](error-handling.md): matching on error classes
- `Ltix.OAuth.Client`: token lifecycle API reference
