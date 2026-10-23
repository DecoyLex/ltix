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

## Using plugins in a worker

A client authenticated from a registration uses your configured plugins. If your launches pass `plugins:` to `Ltix.handle_callback/3`, pass the same plugins here.

```elixir
{:ok, client} = Ltix.GradeService.authenticate(registration,
  endpoint: endpoint,
  plugins: [MyApp.Canvas]
)
```

See [Writing a Canvas Grade Plugin](canvas-grade-plugin.md) for the plugin.

## Testing the worker

With a test platform from [Testing LTI Launches](testing-lti-launches.md), store an endpoint for the worker to read, stub the token and score requests, and run the job.

```elixir
use Oban.Testing, repo: MyApp.Repo

test "posts the student's grade", %{platform: platform} do
  course = MyApp.Courses.create_course!(registration: platform.registration)

  MyApp.Courses.store_ags_endpoint(course.id, %{
    line_items_url: "https://platform.example.com/lineitems",
    line_item_url: "https://platform.example.com/lineitems/1",
    scopes: ["https://purl.imsglobal.org/spec/lti-ags/scope/score"]
  })

  Ltix.Test.stub_token_response()
  Ltix.Test.stub_post_score()

  args = %{"course_id" => course.id, "user_id" => "student-42"}

  assert :ok = perform_job(MyApp.GradeSyncWorker, args)
end
```

If your grade sync runs in a process your application supervises, such as a GenServer that batches scores, pass that process to `Ltix.Test.allow_stubs/1`.

```elixir
Ltix.Test.allow_stubs(Process.whereis(MyApp.GradeBatcher))
```
