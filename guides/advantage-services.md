# Advantage Services

After a successful launch, your tool can call the platform
to query rosters, post grades, or manage content. These platform APIs
are called Advantage services. This guide covers authenticating to
them and managing tokens in your application.

## Calling a service after launch

A launch gives you a `%LaunchContext{}` containing the platform's
service endpoints. Authenticate and call a service directly in your
controller.

```elixir
def launch(conn, params) do
  state = get_session(conn, :lti_state)
  {:ok, context} = Ltix.handle_callback(params, state)

  # Authenticate to the memberships service
  case Ltix.MembershipsService.authenticate(context) do
    {:ok, client} ->
      {:ok, roster} = Ltix.MembershipsService.list_members(client)

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

Each token request is signed by your storage adapter's `key_id/2` and `sign/4` callbacks. See [Storage Adapters](storage-adapters.md#signing).

A token request from a launch context includes the launch's deployment ID. When you authenticate from a registration, pass `:deployment` with your deployment struct or the deployment ID. A platform may require it before it issues a token.

## Background service calls

Outside of a launch, you won't have a `%LaunchContext{}`. Authenticate
directly with a registration and a stored endpoint URL.

```elixir
alias Ltix.LaunchClaims.MembershipsEndpoint

endpoint = MembershipsEndpoint.new!(stored_memberships_url)

{:ok, client} = Ltix.MembershipsService.authenticate(registration,
  endpoint: endpoint
)

{:ok, roster} = Ltix.MembershipsService.list_members(client)
```

Store the endpoint URL when you first receive it during a launch, then
use it later in background jobs.

```elixir
# During launch: save the endpoint URL for later
url = context.claims.memberships_endpoint.context_memberships_url
MyApp.Courses.store_memberships_url(course_id, url)

# In an Oban worker: use the stored URL
def perform(%{args: %{"course_id" => course_id}}) do
  url = MyApp.Courses.get_memberships_url(course_id)
  registration = MyApp.Courses.get_registration(course_id)
  endpoint = MembershipsEndpoint.new!(url)

  {:ok, client} = Ltix.MembershipsService.authenticate(registration,
    endpoint: endpoint
  )

  {:ok, roster} = Ltix.MembershipsService.list_members(client)
  MyApp.Courses.sync_roster(course_id, roster)
end
```

The grade service endpoint also includes the scopes the platform allows, and authenticating requires them. Store them alongside the URLs and rebuild the endpoint with `Ltix.LaunchClaims.AGSEndpoint.new!/1`.

```elixir
alias Ltix.LaunchClaims.AGSEndpoint

# During launch
%AGSEndpoint{line_items: line_items, line_item: line_item, scopes: scopes} =
  context.claims.ags_endpoint

MyApp.Courses.store_ags_endpoint(course_id, line_items, line_item, scopes)

# In an Oban worker
{line_items, line_item, scopes} = MyApp.Courses.get_ags_endpoint(course_id)
endpoint = AGSEndpoint.new!(line_items: line_items, line_item: line_item, scopes: scopes)

{:ok, client} = Ltix.GradeService.authenticate(registration, endpoint: endpoint)
```

## Managing tokens

Tokens are not refreshed automatically. For a single request handler,
tokens last long enough that you don't need to worry about expiry.
For long-running processes, refresh before each operation.
`refresh!/1` requests a new token only when the current one has
expired.

```elixir
client = Ltix.OAuth.Client.refresh!(client)
```

> #### Token lifetime {: .info}
>
> Tokens typically last about 1 hour. For request handlers that
> authenticate and immediately call a service, expiry is not a
> concern. For background jobs that run longer, check expiry between
> operations.

## Reusing tokens across courses

A token is scoped to a registration (platform + client_id) and works for every course on it. A platform may also limit a token to the deployment it was requested for. If your tool syncs multiple courses in the same deployment, you can reuse one token.

```elixir
# Authenticate once
{:ok, client} = Ltix.MembershipsService.authenticate(registration,
  endpoint: course_a_endpoint
)

# Switch to a different course without re-authenticating
{:ok, client_b} = Ltix.OAuth.Client.with_endpoints(client, %{
  Ltix.MembershipsService => course_b_endpoint
})

{:ok, roster_b} = Ltix.MembershipsService.list_members(client_b)
```

For caching tokens across processes and other advanced patterns, see
[Token Caching and Reuse](cookbooks/token-caching-and-reuse.md).

## Multiple services in one token

If your tool calls multiple services, request all scopes in a single
token by passing multiple endpoints.

```elixir
{:ok, client} = Ltix.OAuth.authenticate(registration,
  endpoints: %{
    Ltix.MembershipsService => memberships_endpoint,
    Ltix.GradeService => ags_endpoint
  }
)

# The same client works for both services
{:ok, roster} = Ltix.MembershipsService.list_members(client)
:ok = Ltix.GradeService.post_score(client, score)
```

From a launch, list the services, and Ltix reads each endpoint from the launch claims.

```elixir
{:ok, client} = Ltix.OAuth.authenticate(context,
  services: [Ltix.MembershipsService, Ltix.GradeService]
)
```

> #### Scope negotiation {: .warning}
>
> Platforms may grant fewer scopes than requested. Authentication still succeeds, and each service function returns a `ScopeMismatch` error if its scope was not granted. Pass `require_all_scopes: true` to `Ltix.OAuth.authenticate/2`, `Ltix.GradeService.authenticate/2`, `Ltix.MembershipsService.authenticate/2`, `Ltix.OAuth.Client.with_endpoints/3`, or `Ltix.OAuth.Client.from_access_token/2` to get that error from that call.

## Custom platform APIs

If your platform exposes proprietary APIs (e.g., proctoring,
analytics), you can use the same authentication flow for them by
implementing the `Ltix.AdvantageService` behaviour. See
[Building a Custom Advantage Service](cookbooks/custom-advantage-service.md)
for a complete walkthrough.

## Next steps

- [Memberships Service](memberships-service.md) - querying course
  rosters
- [Grade Service](grade-service.md) - posting grades and managing
  line items
- [JWK Management](jwk-management.md) - managing the signing keys
  used for authentication
- [Token Caching and Reuse](cookbooks/token-caching-and-reuse.md) -
  batch refreshing, multi-course tokens, and ETS caching
- [Error Handling](error-handling.md) - matching on error classes
- `Ltix.OAuth.Client` - token lifecycle API reference
