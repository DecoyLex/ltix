# Testing LTI Launches

`Ltix.Test` provides helpers for testing your LTI application. Set up a simulated platform in one call, then test your controllers, authorization logic, and role-based behavior without a real platform.

## Setup

Add your storage adapter and the Req test plug to `config/test.exs`.

```elixir
# config/test.exs
config :ltix,
  storage_adapter: MyApp.LtiStorageAdapter,
  req_options: [plug: {Req.Test, :ltix}]
```

The `:ltix` atom is a sentinel. Each internal module rewrites it to its own stub name so that HTTP calls are isolated per service. `setup_platform!/1` automatically stubs key set fetches.

Then create a test platform in your setup block. Pass a `:registration` function to create matching records in your own persistence layer. The function receives an `Ltix.Registration` with the registration details (issuer, client_id, endpoints) and returns your application's struct.

```elixir
defmodule MyAppWeb.LtiControllerTest do
  use MyAppWeb.ConnCase, async: true

  setup do
    jwk = MyApp.Lti.create_jwk!()

    platform = Ltix.Test.setup_platform!(
      registration: fn reg ->
        MyApp.Lti.create_registration!(%{
          issuer: reg.issuer,
          client_id: reg.client_id,
          auth_endpoint: reg.auth_endpoint,
          jwks_uri: reg.jwks_uri,
          token_endpoint: reg.token_endpoint,
          jwk_id: jwk.id
        })
      end,
      tool_jwk: Ltix.JWK.new!(private_key_pem: jwk.private_key_pem, kid: jwk.kid)
    )

    %{platform: platform}
  end
end
```

Pass the key your storage adapter signs with as `:tool_jwk`, so `Ltix.Test.verify_deep_linking_response/2` can verify what your tool signs.

If your storage adapter auto-creates deployments (common pattern), you don't need a deployment factory. Otherwise, pass a 2-arity `:deployment` function that receives `(Ltix.Deployment, your_registration)`.

Without a storage adapter of your own, use the in-memory `Ltix.Test.StorageAdapter`. Set it as `storage_adapter` in `config/test.exs`, then start it in your setup with your test platforms.

```elixir
setup do
  platform = Ltix.Test.setup_platform!()
  {:ok, pid} = Ltix.Test.StorageAdapter.start_link(platforms: [platform])
  Ltix.Test.StorageAdapter.set_pid(pid)

  %{platform: platform}
end
```

## Checking your storage adapter

`Ltix.Test.assert_storage_adapter!/2` checks your real adapter's registration and deployment lookups, protocol conversions, nonce replay prevention, and signatures. See [Testing your adapter](storage-adapters.md#testing-your-adapter) for factories and database sandbox setup.

## Testing your controller

Simulate a full platform-initiated launch against your controller endpoints. This tests your routes, session handling, and response logic end-to-end.

```elixir
test "instructor launch renders the dashboard", %{conn: conn, platform: platform} do
  # Platform initiates login
  conn =
    conn
    |> post(~p"/lti/login", Ltix.Test.login_params(platform))

  # Follow the redirect back to your launch endpoint
  assert redirected_to(conn, 302) =~ "https://platform.example.com/auth"
  state = get_session(conn, :lti_state)
  redirect_uri = redirected_to(conn, 302)
  nonce = Ltix.Test.extract_nonce(redirect_uri)

  conn =
    conn
    |> recycle()
    |> Plug.Test.init_test_session(%{lti_state: state})
    |> post(
      ~p"/lti/launch",
      Ltix.Test.launch_params(platform,
        nonce: nonce,
        state: state,
        roles: [Ltix.Role.context_instructor()],
        name: "Jane Doe"
      )
    )

  assert html_response(conn, 200) =~ "Dashboard"
  assert html_response(conn, 200) =~ "Jane Doe"
end

test "learner launch renders the assignment view", %{conn: conn, platform: platform} do
  conn = post(conn, ~p"/lti/login", Ltix.Test.login_params(platform))
  state = get_session(conn, :lti_state)
  nonce = Ltix.Test.extract_nonce(redirected_to(conn, 302))

  conn =
    conn
    |> recycle()
    |> Plug.Test.init_test_session(%{lti_state: state})
    |> post(
      ~p"/lti/launch",
      Ltix.Test.launch_params(platform,
        nonce: nonce,
        state: state,
        roles: [Ltix.Role.context_learner()],
        context: %{id: "course-1", title: "Elixir 101"}
      )
    )

  assert html_response(conn, 200) =~ "Elixir 101"
  refute html_response(conn, 200) =~ "Grade"
end
```

## Testing business logic

When testing code that receives a `%Ltix.Launch{}`, skip the OIDC flow entirely with `build_launch/2`. This is faster and isolates your logic from controller and HTTP concerns.

```elixir
defmodule MyApp.PermissionsTest do
  use ExUnit.Case, async: true

  setup do
    %{platform: Ltix.Test.setup_platform!()}
  end

  test "instructors can manage grades", %{platform: platform} do
    launch = Ltix.Test.build_launch(platform,
      roles: [Ltix.Role.context_instructor()],
      name: "Jane Doe"
    )

    assert MyApp.Permissions.can_manage_grades?(launch)
  end

  test "TAs can view but not manage grades", %{platform: platform} do
    launch = Ltix.Test.build_launch(platform,
      roles: [Ltix.Role.instructor_teaching_assistant()]
    )

    assert MyApp.Permissions.can_view_grades?(launch)
    refute MyApp.Permissions.can_manage_grades?(launch)
  end

  test "learners see their own submissions only", %{platform: platform} do
    launch = Ltix.Test.build_launch(platform,
      roles: [Ltix.Role.context_learner()],
      subject: "student-42",
      context: %{id: "course-1"}
    )

    submissions = MyApp.Submissions.list_for(launch)
    assert Enum.all?(submissions, &(&1.user_id == "student-42"))
  end
end
```

## Customizing launches

`launch_params/2` and `build_launch/2` take the same launch options with the same defaults, so a launch built either way has the same claims. Without options, the launch is a resource link launch by an instructor with subject `"user-12345"` in context `"context-001"`.

### Roles

Pass each role as its URI, or a context role as its plain name. `Ltix.Role` has a constant for each standard role.

```elixir
roles: [Ltix.Role.context_instructor(), Ltix.Role.instructor_teaching_assistant()]
roles: ["Learner", "https://lms.example.com/roles#CourseDesigner"]
```

### Context and resource link

```elixir
Ltix.Test.build_launch(platform,
  roles: [Ltix.Role.context_instructor()],
  context: %{
    id: "course-1",
    label: "CS101",
    title: "Intro to CS",
    type: ["http://purl.imsglobal.org/vocab/lis/v2/course#CourseOffering"]
  },
  resource_link: %{id: "assignment-1", title: "Quiz 1"}
)
```

Both options also take the `%Ltix.Claims.Context{}` and `%Ltix.Claims.ResourceLink{}` structs.

### Deep linking

Pass `message_type: :deep_linking`. Settings you leave out accept the five standard content types, every presentation target, and multiple items.

```elixir
Ltix.Test.build_launch(platform,
  message_type: :deep_linking,
  deep_linking_settings: %{accept_types: ["ltiResourceLink"], accept_line_item: true}
)
```

### Anonymous launches

Pass `subject: nil` for a launch without a user identifier.

```elixir
Ltix.Test.launch_params(platform, nonce: nonce, state: state, subject: nil)
```

`Ltix.handle_callback/3` rejects such a launch unless your app accepts anonymous launches. Pass `allow_anonymous: true` to the call, or set it for the whole app with `config :ltix, allow_anonymous: true`.

```elixir
Ltix.handle_callback(params, state, allow_anonymous: true)
```

`build_launch/2` also rejects it unless you pass `allow_anonymous: true` or set the configuration.

### Service endpoints

Give the launch grade and memberships service endpoints as maps of the endpoint struct fields, or the structs themselves. The grade service endpoint needs its scopes, and the memberships endpoint can be just its URL.

```elixir
Ltix.Test.launch_params(platform,
  nonce: nonce,
  state: state,
  ags_endpoint: %{
    line_items: "https://platform.example.com/lineitems",
    scopes: ["https://purl.imsglobal.org/spec/lti-ags/scope/lineitem"]
  },
  memberships_endpoint: "https://platform.example.com/memberships"
)
```

### Raw claim overrides

For claims not covered by the convenience options, use `:claims` to merge raw claims over the built ones.

```elixir
Ltix.Test.launch_params(platform,
  nonce: nonce,
  state: state,
  claims: %{
    "https://purl.imsglobal.org/spec/lti/claim/custom" => %{
      "canvas_course_id" => "12345"
    }
  }
)
```

### Plugins

`build_launch/2` runs the launch steps of your configured plugins. Pass `plugins:` to use others, such as the plugin under test.

### Hand-built tokens

To test how your app handles a token `launch_params/2` doesn't build, start from `valid_lti_claims/2`, change the claims, and sign them with the platform's key.

```elixir
claims =
  platform
  |> Ltix.Test.valid_lti_claims(%{"nonce" => nonce})
  |> Map.delete("sub")

params = %{"id_token" => Ltix.Test.sign_id_token(claims, platform.jwk), "state" => state}
```

## Testing advantage services

When your application uses `Ltix.GradeService` or `Ltix.MembershipsService`, you need to stub both the OAuth token request and the service's HTTP calls.

### Grade service

```elixir
test "submits a score after launch", %{platform: platform} do
  Ltix.Test.stub_token_response(scopes: [
    "https://purl.imsglobal.org/spec/lti-ags/scope/score"
  ])

  Ltix.Test.stub_post_score()

  launch = Ltix.Test.build_launch(platform,
    ags_endpoint: %{
      line_item: "https://platform.example.com/lineitems/1",
      scopes: ["https://purl.imsglobal.org/spec/lti-ags/scope/score"]
    }
  )

  {:ok, client} = Ltix.GradeService.authenticate(launch)

  {:ok, score} = Ltix.GradeService.Score.new(
    user_id: "student-42",
    score_given: 85,
    score_maximum: 100,
    activity_progress: :completed,
    grading_progress: :fully_graded
  )

  assert :ok = Ltix.GradeService.post_score(client, score)
end
```

### Memberships service

```elixir
test "fetches roster", %{platform: platform} do
  alias Ltix.MembershipsService.Member

  Ltix.Test.stub_token_response(scopes: [
    "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"
  ])

  Ltix.Test.stub_list_members(
    [%Member{user_id: "student-1", roles: [Ltix.Role.context_learner()], name: "Alice"}],
    context: %{id: "course-1", title: "Elixir 101"}
  )

  launch = Ltix.Test.build_launch(platform,
    memberships_endpoint: "https://platform.example.com/memberships"
  )

  {:ok, client} = Ltix.MembershipsService.authenticate(launch)
  {:ok, roster} = Ltix.MembershipsService.list_members(client)

  assert length(roster.members) == 1
  assert hd(roster.members).name == "Alice"
end
```

### Several grade operations

Each stub handles one operation, so stub every operation your code calls. Stubbing an operation again replaces its stub. A request without a matching stub fails the test with its method and URL.

```elixir
test "creates a line item and posts a score to it", %{platform: platform} do
  alias Ltix.GradeService.LineItem

  Ltix.Test.stub_token_response()

  Ltix.Test.stub_create_line_item(
    %LineItem{id: "https://lms.example.com/lineitems/9", label: "Quiz 1", score_maximum: 100}
  )

  Ltix.Test.stub_post_score()

  launch = Ltix.Test.build_launch(platform,
    ags_endpoint: %{
      line_items: "https://lms.example.com/lineitems",
      scopes: [
        "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
        "https://purl.imsglobal.org/spec/lti-ags/scope/score"
      ]
    }
  )

  {:ok, client} = Ltix.GradeService.authenticate(launch)
  {:ok, item} = Ltix.GradeService.create_line_item(client, label: "Quiz 1", score_maximum: 100)

  score =
    Ltix.GradeService.Score.new!(
      user_id: "student-42",
      score_given: 85,
      score_maximum: 100,
      activity_progress: :completed,
      grading_progress: :fully_graded
    )

  assert :ok = Ltix.GradeService.post_score(client, score, line_item: item)
end
```

To return different data per line item, pass `:line_item` to the per-line-item stubs. A stub without it handles every line item the others do not.

```elixir
Ltix.Test.stub_list_line_items([quiz, exam])
Ltix.Test.stub_list_results(quiz_results, line_item: quiz)
Ltix.Test.stub_list_results(exam_results, line_item: exam)
```

The list stubs handle `list_*` and `stream_*` calls, one page at a time when the call passes `:per_page`.

Stubs apply to the test process and to any process you allow with `Req.Test.allow(Ltix.GradeService, self(), pid)`, so they work in async tests and in processes your code starts.

Per-operation stubs accept the struct(s) the platform would return. Line item, result, and member stubs send each struct's unrecognized properties and every property it has a value for, using the plugins in `config :ltix, plugins:` or the stub's `plugins:` option. For custom response logic (inspecting headers, returning errors, etc.), use `Req.Test.stub(Ltix.GradeService, fn conn -> ... end)` directly. It replaces every `Ltix.Test` stub of that service.
