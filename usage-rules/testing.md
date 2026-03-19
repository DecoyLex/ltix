# Testing

Rules for testing applications that use Ltix.

## Test Configuration

Add to `config/test.exs`:

```elixir
config :ltix, storage_adapter: Ltix.Test.StorageAdapter
```

This in-memory adapter is process-scoped, safe for `async: true` tests.

## Platform Setup

In your test's `setup` block:

```elixir
setup do
  %{platform: Ltix.Test.setup_platform!()}
end
```

`setup_platform!/1` generates RSA keys, creates a registration and deployment, starts
the in-memory storage adapter, and stubs the JWKS HTTP endpoint. Options:
`:issuer`, `:client_id`, `:deployment_id`.

## Three Test Patterns

### 1. Full OIDC Flow (Controller Tests)

Simulate the complete platform-initiated launch through your routes:

```elixir
test "launch renders dashboard", %{conn: conn, platform: platform} do
  conn = post(conn, ~p"/lti/login", Ltix.Test.login_params(platform))

  state = get_session(conn, :lti_state)
  nonce = Ltix.Test.extract_nonce(redirected_to(conn, 302))

  conn =
    conn
    |> recycle()
    |> Plug.Test.init_test_session(%{lti_state: state})
    |> post(~p"/lti/launch",
      Ltix.Test.launch_params(platform,
        nonce: nonce,
        state: state,
        roles: [:instructor],
        name: "Jane Doe"
      )
    )

  assert html_response(conn, 200) =~ "Dashboard"
end
```

### 2. Direct Context Construction (Unit Tests)

Skip the OIDC flow entirely for business logic tests:

```elixir
test "instructors can manage grades", %{platform: platform} do
  context = Ltix.Test.build_launch_context(platform,
    roles: [:instructor],
    name: "Jane Smith"
  )

  assert MyApp.Permissions.can_manage_grades?(context)
end
```

### 3. Deep Linking Response Verification

Verify signed response JWTs from your tool:

```elixir
test "content selection returns valid JWT", %{platform: platform} do
  context = Ltix.Test.build_launch_context(platform, message_type: :deep_linking)

  {:ok, link} = Ltix.DeepLinking.ContentItem.LtiResourceLink.new(
    url: "https://tool.example.com/quiz/1",
    title: "Quiz"
  )

  {:ok, response} = Ltix.DeepLinking.build_response(context, [link])
  {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, response.jwt)

  content_items = claims["https://purl.imsglobal.org/spec/lti-dl/claim/content_items"]
  assert length(content_items) == 1
end
```

## Claim Customization

`launch_params/2` and `build_launch_context/2` share most options:

- `:roles` — list of atoms (`:instructor`, `:learner`, `:teaching_assistant`, etc.),
  `%Role{}` structs, or URI strings
- `:subject` — user identifier (default: `"user-12345"`)
- `:name`, `:email`, `:given_name`, `:family_name` — user profile fields
- `:context` — map with `:id`, `:label`, `:title` keys
- `:resource_link` — map with `:id`, `:title` keys
- `:message_type` — `:deep_linking` for deep linking requests
- `:deep_linking_settings` — map of settings (for deep linking)
- `:claims` — raw claim map merged last (for advanced overrides)

`build_launch_context/2` also accepts:

- `:memberships_endpoint` — URL string or map (enables memberships service in tests)
- `:ags_endpoint` — map with `:lineitems`, `:lineitem`, `:scope` (enables grade service)

## Login and Callback Options

When testing the library directly (not through your routes):

```elixir
{:ok, result} = Ltix.handle_login(params, redirect_uri, Ltix.Test.login_opts(platform))
{:ok, context} = Ltix.handle_callback(params, state, Ltix.Test.callback_opts(platform))
```

`login_opts/1` and `callback_opts/1` return the correct storage adapter and HTTP stub
configuration for the test platform.
