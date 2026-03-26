# Testing

Rules for testing applications that use Ltix.

## Test Configuration

Add to `config/test.exs`:

```elixir
config :ltix,
  storage_adapter: MyApp.LtiStorageAdapter,
  req_options: [plug: {Req.Test, :ltix}]
```

Point at your own storage adapter. The `req_options` plug routes all
outbound HTTP through `Req.Test`. Each internal module rewrites the plug
name to its own well-known stub name, so you can stub each independently:

| Stub name                       | HTTP call                         |
|---------------------------------|-----------------------------------|
| `Ltix.JWT.KeySet`               | JWKS public key fetches           |
| `Ltix.OAuth.ClientCredentials`  | OAuth token requests              |
| `Ltix.GradeService`            | Grade service (AGS) requests       |
| `Ltix.MembershipsService`      | Memberships (NRPS) requests        |

`setup_platform!/1` automatically stubs `Ltix.JWT.KeySet`.

## Platform Setup

In your test's `setup` block:

```elixir
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
```

`setup_platform!/1` generates platform-side RSA keys, builds a registration
and deployment, and stubs the JWKS HTTP endpoint. Pass a `:registration`
function to create matching records in your persistence layer. Options:
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

## Testing Advantage Services

When testing code that uses `Ltix.GradeService` or `Ltix.MembershipsService`,
stub both the OAuth token endpoint and the service endpoint:

```elixir
test "posts a score after launch", %{platform: platform} do
  Ltix.Test.stub_token_response(scopes: [
    "https://purl.imsglobal.org/spec/lti-ags/scope/score"
  ])

  Ltix.Test.stub_post_score()

  context = Ltix.Test.build_launch_context(platform,
    ags_endpoint: %Ltix.LaunchClaims.AgsEndpoint{
      lineitem: "https://platform.example.com/lineitems/1",
      scope: ["https://purl.imsglobal.org/spec/lti-ags/scope/score"]
    }
  )

  {:ok, client} = Ltix.GradeService.authenticate(context)

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

Per-operation stubs are available for each service call:

- `stub_list_line_items/1`, `stub_get_line_item/1`, `stub_create_line_item/1`,
  `stub_update_line_item/1`, `stub_delete_line_item/0`
- `stub_post_score/0`, `stub_get_results/1`
- `stub_get_members/1`

Each accepts the struct(s) the platform would return. For custom response
logic, use `Req.Test.stub(Ltix.GradeService, fn conn -> ... end)` directly.

`stub_token_response/1` accepts `:scopes`, `:access_token`, and `:expires_in`.
