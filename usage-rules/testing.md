# Testing

Rules for testing applications that use Ltix.

## Test Configuration

Add to `config/test.exs`.

```elixir
config :ltix,
  storage_adapter: MyApp.LtiStorageAdapter,
  req_options: [plug: {Req.Test, :ltix}, retry: false]
```

- Replace `MyApp.LtiStorageAdapter` with your storage adapter, or use `Ltix.Test.StorageAdapter`. Platform Setup has an example.
- The `plug` option sends Ltix's requests to the `Ltix.Test` stubs. Stub platform responses with `Ltix.Test` functions. A `Req.Test.stub(:ltix, ...)` stub has no effect.
- Keep `retry: false` so a stubbed failure returns at once.

## Platform Failures

To test how your application handles a failing platform, call `Ltix.Test.stub_token_response/1` or `Ltix.Test.stub_key_set/2` with one of these options.

- `:status` and `:body`, for the response the platform sends. A string body is sent as text, and anything else as JSON. An error status without `:body` has an empty body.
- `:transport_error`, a `Req.TransportError` reason such as `:econnrefused` or `:timeout`, for a platform that doesn't respond. It can't be combined with other options.

| Failure | Stub | Error Ltix returns |
|---|---|---|
| Token request rejected | `Ltix.Test.stub_token_response(status: 400, body: %{"error" => "invalid_client"})` | `Ltix.Errors.Invalid.TokenRequestFailed` from `authenticate/2` |
| Token endpoint down | `Ltix.Test.stub_token_response(status: 503, body: "Service Unavailable")` | `Ltix.Errors.Invalid.TokenRequestFailed` from `authenticate/2` |
| Token response without a token | `Ltix.Test.stub_token_response(body: "<html>Maintenance</html>")` | `Ltix.Errors.Invalid.MalformedResponse` from `authenticate/2` |
| Token endpoint unreachable | `Ltix.Test.stub_token_response(transport_error: :econnrefused)` | `Ltix.Errors.Unknown.TransportError` from `authenticate/2` |
| Key set down | `Ltix.Test.stub_key_set(platform, status: 503)` | `Ltix.Errors.Unknown.TransportError` from `Ltix.handle_callback/3` |
| Key set refused | `Ltix.Test.stub_key_set(platform, status: 403)` | `Ltix.Errors.Security.AccessDenied` from `Ltix.handle_callback/3` |
| Key set unreachable | `Ltix.Test.stub_key_set(platform, transport_error: :timeout)` | `Ltix.Errors.Unknown.TransportError` from `Ltix.handle_callback/3` |
| Key set not JSON | `Ltix.Test.stub_key_set(platform, body: "<html>Maintenance</html>")` | `Ltix.Errors.Invalid.MalformedResponse` from `Ltix.handle_callback/3` |
| Key set without the signing key | `Ltix.Test.stub_key_set(platform, body: %{"keys" => []})` | `Ltix.Errors.Security.KidNotFound` from `Ltix.handle_callback/3` |

- `Ltix.Test.stub_key_set(platform)` without options serves the platform's keys again.
- Test key set failures through the full OIDC flow. `build_launch/2` doesn't fetch the key set.
- When you pass `setup_platform!/1` a `:registration` struct, give each test's registration its own `jwks_uri`. Async tests that share a key set URL can receive each other's responses.
- For a grade or memberships service error, see the custom response rule in Testing Advantage Services.

## Platform Setup

Set up the platform in your test's `setup` block.

```elixir
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
    # The key your storage adapter signs with, for verify_deep_linking_response/2
    tool_jwk: Ltix.JWK.new!(private_key_pem: jwk.private_key_pem, kid: jwk.kid)
  )

  %{platform: platform}
end
```

`setup_platform!/1` generates platform-side RSA keys, builds a registration and deployment, and stubs the key set URL. Pass `:registration` and `:deployment` functions to create matching records in your database. It also takes `:issuer`, `:client_id`, `:deployment_id`, `:deployment`, and `:tool_jwk`.

Without a storage adapter of your own, configure the in-memory `Ltix.Test.StorageAdapter` and start it with your test platforms. Use it only in tests.

```elixir
{:ok, pid} = Ltix.Test.StorageAdapter.start_link(platforms: [platform])
Ltix.Test.StorageAdapter.set_pid(pid)
```

## Three Test Patterns

### 1. Full OIDC Flow (Controller Tests)

Simulate the complete platform-initiated launch through your routes.

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
        roles: [Ltix.Role.context_instructor()],
        name: "Jane Doe"
      )
    )

  assert html_response(conn, 200) =~ "Dashboard"
end
```

### 2. Direct Launch Construction (Unit Tests)

Skip the OIDC flow entirely for business logic tests.

```elixir
test "instructors can manage grades", %{platform: platform} do
  launch = Ltix.Test.build_launch(platform,
    roles: [Ltix.Role.context_instructor()],
    name: "Jane Smith"
  )

  assert MyApp.Permissions.can_manage_grades?(launch)
end
```

### 3. Deep Linking Response Verification

Verify signed response JWTs from your tool.

```elixir
test "content selection returns valid JWT", %{platform: platform} do
  launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)

  {:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
    url: "https://tool.example.com/quiz/1",
    title: "Quiz"
  )

  {:ok, response} = Ltix.DeepLinking.build_response(launch, [link])
  {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, response.jwt)

  content_items = claims["https://purl.imsglobal.org/spec/lti-dl/claim/content_items"]
  assert length(content_items) == 1
end
```

## Claim Customization

`launch_params/2` and `build_launch/2` take the same options for building claims, with the same defaults. Unknown options, including unknown keys in nested maps, raise `Ltix.Errors.Invalid.InvalidOption`.

- `:roles` - list of role URIs, such as `Ltix.Role.context_learner()` and `Ltix.Role.instructor_teaching_assistant()` (defaults to an instructor). URIs are sent as given.
- `:subject` - user identifier (defaults to `"user-12345"`), `nil` for an anonymous launch
- `:name`, `:email`, `:given_name`, `:family_name` - user profile fields
- `:context` - `%Ltix.Claims.Context{}` or map with `:id`, `:label`, `:title`, `:type` keys (the default id is `"context-001"`)
- `:resource_link` - `%Ltix.Claims.ResourceLink{}` or map with `:id`, `:title`, `:description` keys
- `:message_type` - `:resource_link` (default), `:deep_linking`, or a message type string, such as `"LtiSubmissionReviewRequest"`, whose launch has no resource link or Deep Linking settings
- `:deep_linking_settings` - `%Ltix.DeepLinking.Settings{}` or map of its fields (defaults accept the five standard content types, every presentation target, and multiple items)
- `:target_link_uri` - launch URL (defaults to `"https://tool.example.com/launch"`)
- `:ags_endpoint` - `%Ltix.GradeService.Endpoint{}` or map with `:line_items`, `:line_item`, and the required `:scopes`
- `:memberships_endpoint` - `%Ltix.MembershipsService.Endpoint{}`, URL string, or map with `:context_memberships_url` and `:service_versions`
- `:claims` - raw claim map merged last (for advanced overrides)

A launch with subject identifiers in the `role_scope_mentor` claim fails unless `:roles` has the Mentor context role or one of its sub-roles, such as `Ltix.Role.context_mentor()` or `Ltix.Role.mentor_advisor()`.

`launch_params/2` also requires `:nonce` and `:state`, and takes `:plugins`, the plugins to send the properties of claim structs with. `build_launch/2` also takes `:allow_anonymous`, which a resource link launch without a subject needs, and `:plugins`, the plugins the launch runs with. It takes the registration and deployment from the platform, skips the security checks and the storage adapter, runs the other launch steps, including every plugin's, and raises when the launch fails.

## Hand-Built Tokens

For a token `launch_params/2` doesn't build, such as one missing a claim, start from `valid_lti_claims/2` and sign it with the platform key using `sign_id_token/3`. The platform key is `platform.jwk`, an `%Ltix.JWK{}`.

```elixir
claims = Map.delete(Ltix.Test.valid_lti_claims(platform, %{"nonce" => nonce}), "sub")
params = %{"id_token" => Ltix.Test.sign_id_token(claims, platform.jwk), "state" => state}
```

## Testing Advantage Services

When testing code that uses `Ltix.GradeService` or `Ltix.MembershipsService`, stub both the OAuth token endpoint and the service endpoint.

```elixir
test "posts a score after launch", %{platform: platform} do
  Ltix.Test.stub_token_response(scopes: [
    "https://purl.imsglobal.org/spec/lti-ags/scope/score"
  ])

  Ltix.Test.stub_post_score()

  launch = Ltix.Test.build_launch(platform,
    ags_endpoint: %Ltix.GradeService.Endpoint{
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

  :ok = Ltix.GradeService.post_score(client, score)
end
```

Each service call has a stub.

- `stub_list_line_items/2`, `stub_get_line_item/2`, `stub_create_line_item/2`, `stub_update_line_item/2`, `stub_delete_line_item/1`
- `stub_post_score/1`, `stub_list_results/2`
- `stub_list_members/2`
- `stub_token_response/1`, which accepts `:scopes`, `:access_token`, and `:expires_in`, and the failure options in Platform Failures

Rules for the stubs.

- Stub every operation the code under test calls. Stubs for different operations can be set in the same test.
- Stubbing an operation again replaces its stub.
- A request without a matching stub fails the test. The failure message includes the request's method and URL.
- To match one line item only, pass `line_item:` with its URL or a `%Ltix.GradeService.LineItem{}` to `stub_get_line_item/2`, `stub_update_line_item/2`, `stub_delete_line_item/1`, `stub_post_score/1`, or `stub_list_results/2`.
- List stubs also handle `stream_*` calls, and split results into pages when the call passes `:per_page`.
- Build stub data from the structs the service call returns.
- To include a plugin's properties in a stubbed response, configure the plugin in `config :ltix, plugins:` or pass it as the stub's `plugins:` option.
- To set the membership container's properties, pass `stub_list_members/2` a `%Ltix.MembershipsService.MembershipContainer{}`.

```elixir
Ltix.Test.stub_list_line_items([
  %Ltix.GradeService.LineItem{id: "https://lms.example.com/lineitems/1", label: "Quiz 1", score_maximum: 100}
])
```

For an error or other custom response, call `Req.Test.stub/2` with the service module, such as `Req.Test.stub(Ltix.GradeService, fn conn -> ... end)`. It replaces every `Ltix.Test` stub of that service.

Stubs apply to the test process and the processes it starts, such as tasks, LiveViews, and `start_supervised/2` children. For any other process, such as a GenServer your application supervises, call `Ltix.Test.allow_stubs(pid)`. The process can then use every `Ltix.Test` stub and the test's `Ltix.Test.StorageAdapter`, including those set after the call.
