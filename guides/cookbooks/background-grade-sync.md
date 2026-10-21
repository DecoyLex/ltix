# Syncing Grades in the Background

For scheduled grade sync or Oban workers, store the AGS endpoint during launch and authenticate from a registration later.

## Storing the endpoint

Save the endpoint URLs and scopes from the first launch. The scopes are required to authenticate later.

```elixir
endpoint = Ltix.Launch.get_endpoint(launch, Ltix.GradeService)

MyApp.Courses.store_ags_endpoint(course_id, %{
  line_items_url: endpoint.line_items,
  line_item_url: endpoint.line_item,
  scopes: endpoint.scopes
})
```

## Posting grades in a background job

Rebuild the endpoint with `Ltix.GradeService.Endpoint.new!/1`.

```elixir
alias Ltix.GradeService.Endpoint

def perform(%{args: %{"course_id" => course_id, "user_id" => user_id}}) do
  registration = MyApp.Courses.get_registration(course_id)
  stored = MyApp.Courses.get_ags_endpoint(course_id)

  endpoint =
    Endpoint.new!(
      line_items: stored.line_items_url,
      line_item: stored.line_item_url,
      scopes: stored.scopes
    )

  {:ok, client} = Ltix.GradeService.authenticate(registration,
    endpoint: endpoint
  )

  {:ok, score} = Ltix.GradeService.Score.new(
    user_id: user_id,
    score_given: calculate_grade(course_id, user_id),
    score_maximum: 100,
    activity_progress: :completed,
    grading_progress: :fully_graded
  )

  :ok = Ltix.GradeService.post_score(client, score)
end
```

See [Persisting Service Endpoints](persisting-service-endpoints.md) for schema examples, [Advantage Services](../advantage-services.md) for an overview of token management, and [Token Caching and Reuse](token-caching-and-reuse.md) for batch refreshing, multi-course tokens, and ETS caching patterns.
