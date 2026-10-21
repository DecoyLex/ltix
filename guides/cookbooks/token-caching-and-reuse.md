# Token Caching and Reuse

Most LTI tools authenticate once per request or job and need no token management. But when a background job processes hundreds of grades or syncs multiple courses, understanding the token lifecycle avoids redundant authentication and handles mid-job expiry.

## Refreshing during a batch

When processing many items in a single job, the token may expire before you finish. Call `refresh!/1` between batches. The endpoint is rebuilt from the URL and scopes saved during a launch. [Syncing Grades in the Background](background-grade-sync.md) shows how to save and rebuild it.

```elixir
def perform(%{args: %{"course_id" => course_id}}) do
  registration = MyApp.Courses.get_registration(course_id)
  stored = MyApp.Courses.get_ags_endpoint(course_id)
  endpoint = Ltix.GradeService.Endpoint.new!(line_item: stored.line_item_url, scopes: stored.scopes)

  {:ok, client} = Ltix.GradeService.authenticate(registration,
    endpoint: endpoint
  )

  course_id
  |> MyApp.Grades.pending_scores()
  |> Enum.chunk_every(50)
  |> Enum.reduce(client, fn batch, client ->
    client = ensure_fresh(client)

    Enum.each(batch, fn {user_id, score_given} ->
      {:ok, score} = Ltix.GradeService.Score.new(
        user_id: user_id,
        score_given: score_given,
        score_maximum: 100,
        activity_progress: :completed,
        grading_progress: :fully_graded
      )

      :ok = Ltix.GradeService.post_score(client, score)
    end)

    client
  end)

  :ok
end

defp ensure_fresh(client) do
  Ltix.OAuth.Client.refresh!(client)
end
```

`refresh/1` requests a new token only when `Ltix.OAuth.Client.expired?/1` is true for the current one. Otherwise it returns the client unchanged. The returned client has the same endpoints and registration, and only the token changes. To request a new token regardless of expiry, use `force_refresh!/1`.

## Syncing multiple courses

A token is scoped to a registration, identified by issuer and client\_id. If you sync several courses on the same platform in one job, authenticate once and swap endpoints with `with_endpoints!/3`.

```elixir
def perform(%{args: %{"registration_id" => registration_id}}) do
  registration = MyApp.Lti.get_registration(registration_id)
  courses = MyApp.Courses.for_registration(registration_id)

  # Bootstrap with any course's endpoint to acquire the token
  first_endpoint = MyApp.Courses.get_memberships_endpoint(hd(courses).id)

  {:ok, client} = Ltix.MembershipsService.authenticate(registration,
    endpoint: first_endpoint
  )

  Enum.reduce(courses, client, fn course, client ->
    endpoint = MyApp.Courses.get_memberships_endpoint(course.id)

    client = Ltix.OAuth.Client.with_endpoints!(client, %{
      Ltix.MembershipsService => endpoint
    })

    client = ensure_fresh(client)

    {:ok, roster} = Ltix.MembershipsService.list_members(client)
    MyApp.Courses.sync_roster(course.id, roster)

    client
  end)

  :ok
end
```

The token's granted scopes do not change. If it lacks a scope a new endpoint needs, that service returns a `ScopeMismatch` error when called. Pass `require_all_scopes: true` to `with_endpoints/3` to get the error at swap time.

## Caching tokens across workers

When many Oban workers call the same platform concurrently (say, one job per course), each authenticates independently by default. To share tokens, cache them in ETS. A token has only the scopes it was requested for, and a platform may limit it to the deployment it was requested for, so key the cache by the registration, the deployment, and the scopes the service requests. Workers calling the same service share one token, and a service that needs other scopes gets a separate token.

```elixir
defmodule MyApp.LTI.TokenCache do
  @table :lti_token_cache

  alias Ltix.OAuth.{AccessToken, Client}

  def create_table do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    :ok
  end

  def get_or_authenticate(registration, deployment, service, endpoint) do
    key =
      {registration.issuer, registration.client_id, deployment.deployment_id,
       Enum.sort(service.scopes(endpoint))}

    case :ets.lookup(@table, key) do
      [{^key, token}] ->
        if AccessToken.expired?(token) do
          authenticate_and_cache(key, registration, deployment, service, endpoint)
        else
          Client.from_access_token(token,
            registration: registration,
            deployment: deployment,
            endpoints: %{service => endpoint}
          )
        end

      [] ->
        authenticate_and_cache(key, registration, deployment, service, endpoint)
    end
  end

  defp authenticate_and_cache(key, registration, deployment, service, endpoint) do
    {:ok, client} =
      service.authenticate(registration, endpoint: endpoint, deployment: deployment)

    :ets.insert(@table, {key, client.token})
    {:ok, client}
  end
end
```

An ETS table is deleted when the process that created it exits, so create the table once when your application starts.

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  :ok = MyApp.LTI.TokenCache.create_table()

  children = [
    MyApp.Repo,
    {Oban, Application.fetch_env!(:my_app, Oban)}
  ]

  Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
end
```

Use the cache in an Oban worker.

```elixir
def perform(%{args: %{"course_id" => course_id}}) do
  registration = MyApp.Courses.get_registration(course_id)
  deployment = MyApp.Courses.get_deployment(course_id)
  endpoint = MyApp.Courses.get_memberships_endpoint(course_id)

  {:ok, client} = MyApp.LTI.TokenCache.get_or_authenticate(
    registration,
    deployment,
    Ltix.MembershipsService,
    endpoint
  )

  {:ok, roster} = Ltix.MembershipsService.list_members(client)
  MyApp.Courses.sync_roster(course_id, roster)
end
```

> #### Race conditions {: .info}
>
> This ETS cache uses last-write-wins. Concurrent workers may both miss the cache and authenticate simultaneously, producing two valid tokens. This is harmless because the platform issues independent tokens, and one simply goes unused.

## Storing tokens outside ETS

To share tokens across nodes, store them in your database or a shared cache. `Ltix.OAuth.AccessToken.to_map/1` returns a map that encodes to JSON, and `Ltix.OAuth.AccessToken.from_map/1` restores the token.

```elixir
stored = Ltix.OAuth.AccessToken.to_map(client.token)

{:ok, token} = Ltix.OAuth.AccessToken.from_map(stored)
```

The map holds the bearer token, so store it like any other credential.

## When to cache

Don't add caching complexity unless you have a reason.

| Scenario | Approach |
|---|---|
| Single API call per job | Just authenticate. No caching needed. |
| One job, many API calls | Refresh mid-batch with `refresh!/1`. |
| One job, many courses | Authenticate once, swap with `with_endpoints/3`. |
| Many concurrent jobs, same platform | Cache tokens in ETS. |

## Next steps

- [Advantage Services](../advantage-services.md) for an overview of service authentication and token management
- [Syncing Grades in the Background](background-grade-sync.md) for simple background grading without caching
- `Ltix.OAuth.Client` for the full token lifecycle API reference
- `Ltix.OAuth.AccessToken` for the cacheable token struct
