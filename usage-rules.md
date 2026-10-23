# Ltix Usage Rules

Ltix is an Elixir library for building LTI 1.3 tool applications. It handles the OIDC
launch flow, JWT verification, claim parsing, and Advantage Services (grading, roster,
deep linking).

## Two-Function API

The entire OIDC launch flow is two functions.

1. `Ltix.handle_login(params, redirect_uri, opts)` - called when the platform sends the
   user to your login endpoint. Returns `{:ok, %{redirect_uri: url, state: state}}`. Store
   `state` in the session, redirect the user to `redirect_uri`.

2. `Ltix.handle_callback(params, state, opts)` - called when the platform POSTs back to
   your launch endpoint. Returns `{:ok, %LaunchContext{}}` with parsed claims, registration,
   and deployment.

- **Never** call internal OIDC modules directly (`Ltix.OIDC.*`, `Ltix.JWT.Token`). Use
  the two public functions, or their raising variants `handle_login!/3` and
  `handle_callback!/3`.
- `handle_login/3` takes `:storage_adapter` and `:storage_adapter_options`. `handle_callback/3` takes `:storage_adapter`, `:storage_adapter_options`, `:allow_anonymous`, `:max_token_age`, `:local_network_access`, `:req_options`, `:key_set`, `:claim_parsers`, `:role_parsers`, and `:clock_skew`. Each option except `:storage_adapter_options` and `:clock_skew` overrides its application configuration for that call. Unknown or invalid options raise `Ltix.Errors.Invalid.InvalidOption`.

## Required Configuration

Every app must configure a storage adapter.

```elixir
config :ltix, storage_adapter: MyApp.Lti.StorageAdapter
```

The storage adapter module must implement the `Ltix.StorageAdapter` behaviour (3 required callbacks).
**Never** use `Ltix.Test.StorageAdapter` outside of tests.

Phoenix apps typically group LTI-related modules under a context module like `MyApp.Lti`
(e.g., `MyApp.Lti.StorageAdapter`, `MyApp.Lti.Registration`). Ask the user about their
preferred structure before creating modules.

## Registrations & Deployments

- Construct with `Registration.new/1` and `Deployment.new/1` (validated), or their raising
  variants `new!/1`. `Registration.new/1` takes a keyword list or map and returns
  `Ltix.Errors.Invalid.InvalidField` for unknown, missing, or invalid fields. **Never**
  build `%Registration{}` or `%Deployment{}` structs directly. Always use `new/1`.
- Storage adapters return structs implementing `Ltix.Registerable` and `Ltix.Deployable`
  protocols. These can be your own Ecto schemas. The library extracts the `Registration`
  and `Deployment` it needs internally. `%Registration{}` and `%Deployment{}` implement
  both protocols, so returning them directly still works.
- The original struct from the storage adapter is preserved in `LaunchContext`, so you can
  access your own fields (DB IDs, tenant info) without extra queries after launch.
- Issuer must be an HTTPS URL with no query or fragment components.
- All endpoints (`auth_endpoint`, `jwks_uri`, `token_endpoint`) must be HTTPS. HTTP is accepted
  only for loopback and local hosts such as `http://localhost:8080`.
- Platform requests reach only public addresses. For a platform on a private network or on
  the same machine, set `local_network_access: :local` or `:loopback` in `config :ltix` or on
  the call. Otherwise the request returns `Ltix.Errors.Security.LocalNetworkAccessDenied`.
- `client_id` is a non-empty string.
- `deployment_id` must be non-empty, at most 255 characters, ASCII-only, and is case-sensitive.

## StorageAdapter Callbacks

These are the 3 required callbacks.

1. **`get_registration(issuer, client_id, opts)`** - `client_id` can be `nil` when the platform
   omits it from the login request. You must handle both cases.
2. **`get_deployment(registration, deployment_id, opts)`** - called after JWT verification.
   `deployment_id` is case-sensitive. `registration` is the struct your `get_registration/3`
   returned, as it is for every callback that takes one.
3. **`validate_nonce(nonce, registration, expires_at, opts)`** - record the nonce as used, called
   after the ID token is verified. Must prevent replay attacks. Use an atomic
   `INSERT ... ON CONFLICT DO NOTHING` to avoid race conditions, and keep the record until
   `expires_at`.

The callbacks return these types.
- `get_registration/3` returns `{:ok, Registerable.t()} | {:error, :not_found}`, with any
  struct implementing `Ltix.Registerable` (including `%Registration{}` itself)
- `get_deployment/3` returns `{:ok, Deployable.t()} | {:error, :not_found}`, with any
  struct implementing `Ltix.Deployable` (including `%Deployment{}` itself)
- `validate_nonce/4` returns `:ok | {:error, :nonce_already_used}`

Any other `{:error, reason}` from a callback fails the login or launch with `Ltix.Errors.Unknown.StorageError`.

Two optional callbacks sign for the tool. Implement them to call Advantage services or build
deep linking responses.

- **`key_id(registration, opts)`** - `{:ok, kid}` for the key that signs for the registration.
- **`sign(registration, key_id, message, opts)`** - `{:ok, signature}` with the RS256 signature of
  `message` as raw bytes. `Ltix.JWK.sign(jwk, message)` returns this for a key the app holds.

`Ltix.Registration` has no key field. Ltix never stores the tool's private key.

**Nonce is used on callback.** `handle_callback/3` records the nonce as used as part of
validation. If the callback fails for a non-security reason (e.g., `DeploymentNotFound`),
you cannot retry `handle_callback/3` with the same params, because the nonce is already
used. Handle recoverable errors (like auto-creating a deployment) in the storage adapter
itself.

## Error Handling

Errors use the Splode framework with three classes.

- `:invalid` - bad input, missing claims, malformed JWT (HTTP 400)
- `:security` - bad signature, expired token, nonce replay (HTTP 401)
- `:unknown` - network errors, unexpected failures (HTTP 500)

Use `Ltix.Errors.status_code/1` to get the HTTP status for any error (invalid=400, security=401, unknown=500). When Plug is a dependency, all errors also implement `Plug.Exception`, so Phoenix error views use the correct status automatically.

A single failure is returned directly. Several simultaneous failures are grouped in their class, such as `%Ltix.Errors.Invalid{errors: [...]}`.

Match on specific error modules for targeted handling, or match on `.class` for broad
categories.

```elixir
case Ltix.handle_callback(params, state) do
  {:ok, context} ->
    render(conn, :launch, context: context)

  {:error, %Ltix.Errors.Invalid.DeploymentNotFound{} = error} ->
    render(conn, :onboard, deployment_id: error.deployment_id)

  {:error, error} ->
    conn
    |> put_status(Ltix.Errors.status_code(error))
    |> render(:error, class: error.class, message: Exception.message(error))
end
```

## Roles

- `Role.instructor?/1`, `Role.learner?/1`, `Role.teaching_assistant?/1` etc. check
  **context roles only** (course-level).
- `Role.administrator?/1` checks the **institution** administrator role. Use `Role.context_administrator?/1` for course administrators.
- For other institution or system roles, use `Role.has_role?/4`.
- Platform granularity varies.
  - Canvas sends sub-roles (e.g., `Instructor#TeachingAssistant`)
  - Moodle sends only `Instructor` or `Learner` (no sub-roles)
  - Others vary by admin configuration
- **Design for the roles every platform sends.** Only reliably expect Instructor vs Learner
  across all platforms.

## Cross-Origin & Iframe Considerations

LTI launches are cross-origin POSTs (platform domain to tool domain), often inside an
iframe.

- Phoenix defaults to `SameSite=Lax`, which blocks cross-origin POST cookies.
  Set `same_site: "None"`, `secure: true`, and `extra: "Partitioned"` in your endpoint
  session config. `Partitioned` keeps the cookie working in browsers that block
  third-party cookies.
- HTTPS is mandatory in both production and development (`mix phx.gen.cert` for dev certs).
- LTI tools are typically embedded in an iframe by the platform. Set a
  `Content-Security-Policy` header (`frame-ancestors 'self' *`) on LTI routes to allow
  this. The platform domains should be scoped down in production.
- The login endpoint should accept both GET and POST, because the LTI spec allows
  either.
- **Never store `%LaunchContext{}` in the session.** It holds the user's identity and
  course data, and session cookies are signed, not encrypted. Extract only the fields
  you need (e.g., `subject`, `roles`, `context.id`).

## Service Availability

Advantage Service endpoints (grading, roster, deep linking) are optional per-launch. The
platform decides what to include based on tool configuration. **Always** check for
`ServiceNotAvailable` before assuming a service is present.

```elixir
case Ltix.GradeService.authenticate(context) do
  {:ok, client} -> Ltix.GradeService.post_score(client, score)
  {:error, %Ltix.Errors.Invalid.ServiceNotAvailable{}} -> :ok
  {:error, error} -> {:error, error}
end
```

## Optional Configuration

- `:allow_anonymous` - allow launches without a `sub` claim (defaults to `false`)
- `:json_library` - auto-detected (`JSON` on Elixir 1.18+/OTP 27+, else `Jason`)
- `:req_options` - default HTTP options for all outgoing requests
- `:key_set` - name of the `Ltix.JWT.KeySet` to get platform public keys from
  (defaults to `Ltix.JWT.KeySet`). It must be started in your supervision tree, as
  `children = [Ltix.JWT.KeySet]`, or `{Ltix.JWT.KeySet, name: MyApp.LtiKeys}` with
  `config :ltix, key_set: MyApp.LtiKeys`. Pass `key_set:` to `handle_callback/3` to
  override it per call.
- Custom claim/role parsers under the `Ltix.LaunchClaims` config key as `:claim_parsers`
  and `:role_parsers`. Pass the same options to `handle_callback/3` to override them for
  one call.

## Telemetry

Ltix emits `:telemetry` events across the OIDC flow, Advantage services, OAuth, JWKS
cache, and deep linking. All span events follow the `[:ltix, <component>, ...]` naming
convention with `:start`, `:stop`, and `:exception` suffixes.

These are the key event prefixes.
- `[:ltix, :login, ...]` and `[:ltix, :callback, ...]` - OIDC launch flow
- `[:ltix, :grade_service, <action>, ...]` - grade service operations
- `[:ltix, :memberships_service, <action>, ...]` - memberships service operations
- `[:ltix, :deep_linking, :build_response, ...]` - deep linking response building
- `[:ltix, :oauth, :authenticate, ...]` and `[:ltix, :oauth, :refresh, ...]` - OAuth token acquisition
- `[:ltix, :jwks, :cache_hit]` and `[:ltix, :jwks, :cache_miss]` - single events (not spans)

See the [telemetry guide](https://ltix.hexdocs.pm/telemetry.md) for full metadata details.

## Finding Documentation

Use the `usage_rules.docs` and `usage_rules.search_docs` mix tasks.

```
mix usage_rules.docs Ltix.GradeService
mix usage_rules.docs Ltix.GradeService.Score.new/1
mix usage_rules.search_docs "line items" -p ltix
mix usage_rules.search_docs "storage adapter" -p ltix
```

Hexdocs can serve raw markdown, which is much easier to read than HTML. Fetch module
docs and guides directly.

```
# Module docs
https://ltix.hexdocs.pm/Ltix.GradeService.md
https://ltix.hexdocs.pm/Ltix.StorageAdapter.md

# Guides
https://ltix.hexdocs.pm/getting-started.md
https://ltix.hexdocs.pm/storage-adapters.md
https://ltix.hexdocs.pm/error-handling.md
https://ltix.hexdocs.pm/advantage-services.md
https://ltix.hexdocs.pm/deep-linking.md
https://ltix.hexdocs.pm/grade-service.md
https://ltix.hexdocs.pm/memberships-service.md
https://ltix.hexdocs.pm/working-with-roles.md
https://ltix.hexdocs.pm/jwk-management.md
https://ltix.hexdocs.pm/telemetry.md

# Cookbooks
https://ltix.hexdocs.pm/testing-lti-launches.md
https://ltix.hexdocs.pm/score-construction.md
https://ltix.hexdocs.pm/building-content-items.md
https://ltix.hexdocs.pm/token-caching-and-reuse.md
https://ltix.hexdocs.pm/auto-create-deployments.md
https://ltix.hexdocs.pm/background-grade-sync.md
https://ltix.hexdocs.pm/managing-jwks-with-ecto.md
https://ltix.hexdocs.pm/canvas-grade-extensions.md
```

Use the `.md` URLs with `curl` or web fetch tools for detailed reference when the mix
tasks don't give enough context.

## Skills

Ltix includes two pre-built skills for common integration tasks. These are step-by-step
guides with collaboration checkpoints. They prompt you to ask the user about app-specific
decisions before writing code.

- **`implement-storage-adapter`** - implement `Ltix.StorageAdapter` with Ecto schemas,
  nonce management, and deployment policy decisions
- **`add-lti-launch`** - set up LTI 1.3 launch endpoints in a Phoenix app (routes,
  session config, CSRF pipeline, controller skeleton)
