# Token Caching and Reuse

Most LTI tools authenticate once per request or job and never think
about token management. But when a background job processes hundreds of
grades or syncs multiple courses, understanding the token lifecycle
avoids redundant authentication and handles mid-job expiry.

## Refreshing during a batch

When processing many items in a single job, the token may expire before
you finish. Check between batches with `expired?/1` and `refresh!/1`:

```elixir
def perform(%{args: %{"course_id" => course_id}}) do
  registration = MyApp.Courses.get_registration(course_id)
  endpoint = MyApp.Courses.get_ags_endpoint(course_id)

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

`refresh/1` re-derives scopes from the client's endpoints and requests
a new token from the platform. The returned client keeps the same
endpoints and registration — only the token changes.

## Syncing multiple courses

A token is scoped to a registration (platform + client\_id), not to a
course. If you sync several courses on the same platform in one job,
authenticate once and swap endpoints with `with_endpoints!/2`:

```elixir
def perform(%{args: %{"platform_id" => platform_id}}) do
  registration = MyApp.Platforms.get_registration(platform_id)
  courses = MyApp.Courses.for_platform(platform_id)

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

    {:ok, roster} = Ltix.MembershipsService.get_members(client)
    MyApp.Courses.sync_roster(course.id, roster)

    client
  end)

  :ok
end
```

`with_endpoints/2` validates that the client's granted scopes cover the
new endpoint's requirements. If the platform granted fewer scopes than
needed, you get a `ScopeMismatch` error at swap time rather than
mid-request.

## Caching tokens across workers

When many Oban workers hit the same platform concurrently — say, one
job per course — each authenticates independently by default. To share
a single token, cache it in ETS:

```elixir
defmodule MyApp.LTI.TokenCache do
  @table :lti_token_cache

  alias Ltix.OAuth.{AccessToken, Client}

  def get_or_authenticate(registration, service, endpoint) do
    key = {registration.issuer, registration.client_id}
    ensure_table()

    case :ets.lookup(@table, key) do
      [{^key, token}] ->
        if token_expired?(token) do
          authenticate_and_cache(key, registration, service, endpoint)
        else
          Client.from_access_token(token,
            registration: registration,
            endpoints: %{service => endpoint}
          )
        end

      [] ->
        authenticate_and_cache(key, registration, service, endpoint)
    end
  end

  defp authenticate_and_cache(key, registration, service, endpoint) do
    {:ok, client} = service.authenticate(registration, endpoint: endpoint)

    token = %AccessToken{
      access_token: client.access_token,
      token_type: "bearer",
      granted_scopes: MapSet.to_list(client.scopes),
      expires_at: client.expires_at
    }

    :ets.insert(@table, {key, token})
    {:ok, client}
  end

  defp token_expired?(%{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), DateTime.add(expires_at, -60)) != :lt
  end

  defp ensure_table do
    :ets.new(@table, [:set, :public, :named_table])
  rescue
    ArgumentError -> :ok
  end
end
```

Usage in an Oban worker:

```elixir
def perform(%{args: %{"course_id" => course_id}}) do
  registration = MyApp.Courses.get_registration(course_id)
  endpoint = MyApp.Courses.get_memberships_endpoint(course_id)

  {:ok, client} = MyApp.LTI.TokenCache.get_or_authenticate(
    registration,
    Ltix.MembershipsService,
    endpoint
  )

  {:ok, roster} = Ltix.MembershipsService.get_members(client)
  MyApp.Courses.sync_roster(course_id, roster)
end
```

> #### Race conditions {: .info}
>
> This ETS cache uses last-write-wins. Concurrent workers may both
> miss the cache and authenticate simultaneously, producing two valid
> tokens. This is harmless — the platform issues independent tokens,
> and one simply goes unused.

## When to cache

Don't add caching complexity unless you have a reason:

| Scenario | Approach |
|---|---|
| Single API call per job | Just authenticate. No caching needed. |
| One job, many API calls | Refresh mid-batch with `expired?/1` + `refresh!/1`. |
| One job, many courses | Authenticate once, swap with `with_endpoints/2`. |
| Many concurrent jobs, same platform | Cache tokens in ETS. |

## Next steps

- [Advantage Services](../advantage-services.md): overview of service
  authentication and token management
- [Syncing Grades in the Background](background-grade-sync.md): simple
  background grading without caching
- `Ltix.OAuth.Client`: full token lifecycle API reference
- `Ltix.OAuth.AccessToken`: cacheable token struct
