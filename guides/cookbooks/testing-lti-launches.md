# Testing LTI Launches

`Ltix.Test` provides helpers for testing your LTI-powered application.
Set up a simulated platform in one call, then test your controllers,
authorization logic, and role-based behavior without a real LMS.

## Setup

Add your storage adapter and the JWKS test stub to `config/test.exs`:

```elixir
# config/test.exs
config :ltix,
  storage_adapter: MyApp.LtiStorageAdapter,
  req_options: [plug: {Req.Test, Ltix.JWT.KeySet}]
```

Then create a test platform in your setup block. Pass a `:registration`
function to create matching records in your own persistence layer. The
function receives an `Ltix.Registration` with the platform details
(issuer, client_id, endpoints) and returns your app's struct:

```elixir
defmodule MyAppWeb.LtiControllerTest do
  use MyAppWeb.ConnCase, async: true

  setup do
    platform = Ltix.Test.setup_platform!(
      registration: fn reg ->
        jwk = MyApp.Lti.generate_jwk!()

        MyApp.Lti.create_registration!(%{
          issuer: reg.issuer,
          client_id: reg.client_id,
          auth_endpoint: reg.auth_endpoint,
          jwks_uri: reg.jwks_uri,
          token_endpoint: reg.token_endpoint,
          tool_jwk_id: jwk.id
        })
      end
    )

    %{platform: platform}
  end
end
```

If your storage adapter auto-creates deployments (common pattern), you
don't need a deployment factory. Otherwise, pass a 2-arity
`:deployment` function that receives `(Ltix.Deployment, your_registration)`.

## Testing your controller

Simulate a full platform-initiated launch against your controller
endpoints. This exercises your routes, session handling, and response
logic end-to-end.

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
        roles: [:instructor],
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
        roles: [:learner],
        context: %{id: "course-1", title: "Elixir 101"}
      )
    )

  assert html_response(conn, 200) =~ "Elixir 101"
  refute html_response(conn, 200) =~ "Grade"
end
```

## Testing business logic

When testing code that receives a `%LaunchContext{}`, skip the OIDC
flow entirely with `build_launch_context/2`. This is faster and isolates
your logic from controller and HTTP concerns.

```elixir
defmodule MyApp.PermissionsTest do
  use ExUnit.Case, async: true

  setup do
    %{platform: Ltix.Test.setup_platform!()}
  end

  test "instructors can manage grades", %{platform: platform} do
    context = Ltix.Test.build_launch_context(platform,
      roles: [:instructor],
      name: "Jane Doe"
    )

    assert MyApp.Permissions.can_manage_grades?(context)
  end

  test "TAs can view but not manage grades", %{platform: platform} do
    alias Ltix.LaunchClaims.Role

    context = Ltix.Test.build_launch_context(platform,
      roles: [%Role{type: :context, name: :instructor, sub_role: :teaching_assistant}]
    )

    assert MyApp.Permissions.can_view_grades?(context)
    refute MyApp.Permissions.can_manage_grades?(context)
  end

  test "learners see their own submissions only", %{platform: platform} do
    context = Ltix.Test.build_launch_context(platform,
      roles: [:learner],
      subject: "student-42",
      context: %{id: "course-1"}
    )

    submissions = MyApp.Submissions.list_for(context)
    assert Enum.all?(submissions, &(&1.user_id == "student-42"))
  end
end
```

## Customizing launches

### Roles

Pass atoms for common LIS context roles:

```elixir
roles: [:instructor, :learner]
```

For sub-roles, pass a `%Role{}` struct:

```elixir
alias Ltix.LaunchClaims.Role
roles: [%Role{type: :context, name: :instructor, sub_role: :teaching_assistant}]
```

For institution or system roles, or custom role URIs, pass the full URI
string:

```elixir
roles: ["http://purl.imsglobal.org/vocab/lis/v2/institution/person#Faculty"]
```

### Context and resource link

```elixir
Ltix.Test.build_launch_context(platform,
  roles: [:instructor],
  context: %{id: "course-1", label: "CS101", title: "Intro to CS"},
  resource_link: %{id: "assignment-1", title: "Quiz 1"}
)
```

### Raw claim overrides

For claims not covered by the convenience options, use `:claims` to
merge arbitrary key-value pairs into the JWT:

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
