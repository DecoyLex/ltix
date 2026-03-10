# Syncing Grades in the Background

For scheduled grade sync or Oban workers, store the AGS endpoint
during launch and authenticate from a registration later.

## Storing the endpoint

Save the endpoint when you first see it during a launch:

```elixir
endpoint = context.claims.ags_endpoint
MyApp.Courses.store_ags_endpoint(course_id, endpoint)
```

## Posting grades in a background job

```elixir
def perform(%{args: %{"course_id" => course_id, "user_id" => user_id}}) do
  registration = MyApp.Courses.get_registration(course_id)
  endpoint = MyApp.Courses.get_ags_endpoint(course_id)

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

See [Advantage Services](../advantage-services.md) for details on
token management and reusing tokens across courses.
