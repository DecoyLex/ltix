# Ltix Usage Rules

Ltix is an Elixir library for building LTI 1.3 tool applications. It handles the OIDC
launch flow, JWT verification, claim parsing, and Advantage Services (grading, roster,
deep linking).

## Two-Function API

The entire OIDC launch flow is two functions:

1. `Ltix.handle_login(params, redirect_uri, opts)` — called when the platform POSTs to
   your login endpoint. Returns `{:ok, %{redirect_uri: url, state: state}}`. Store `state`
   in the session, redirect the user to `redirect_uri`.

2. `Ltix.handle_callback(params, state, opts)` — called when the platform POSTs back to
   your launch endpoint. Returns `{:ok, %LaunchContext{}}` with parsed claims, registration,
   and deployment.

- **Never** call internal OIDC modules directly (`Ltix.OIDC.*`, `Ltix.JWT.Token`). Use
  the two public functions.
- All configuration can be set in `config.exs` or passed per-call via opts.

## Required Configuration

Every app must configure a storage adapter:

```elixir
config :ltix, storage_adapter: MyApp.Lti.StorageAdapter
```

The storage adapter module must implement the `Ltix.StorageAdapter` behaviour (4 callbacks).
**Never** use `Ltix.Test.StorageAdapter` outside of tests.

Phoenix apps typically group LTI-related modules under a context module like `MyApp.Lti`
(e.g., `MyApp.Lti.StorageAdapter`, `MyApp.Lti.Registration`). Ask the user about their
preferred structure before creating modules.

## Registrations & Deployments

- Construct with `Registration.new/1` and `Deployment.new/1` (Zoi-validated). **Never**
  build `%Registration{}` or `%Deployment{}` structs directly — always go through `new/1`.
- Issuer must be an HTTPS URL with no query or fragment components.
- All endpoints (`auth_endpoint`, `jwks_uri`, `token_endpoint`) must be HTTPS.
- `client_id` is a non-empty string.
- `deployment_id` must be non-empty, at most 255 characters, ASCII-only, and is case-sensitive.

## StorageAdapter Callbacks

These are the 4 required callbacks:

1. **`get_registration(issuer, client_id)`** — `client_id` can be `nil` when the platform
   omits it from the login request. You must handle both cases.
2. **`get_deployment(registration, deployment_id)`** — called after JWT verification.
   `deployment_id` is case-sensitive.
3. **`store_nonce(nonce, registration)`** — persist the nonce for later verification.
4. **`validate_nonce(nonce, registration)`** — atomically check and consume the nonce.
   Must prevent replay attacks. Use an atomic `DELETE ... WHERE` or `INSERT ... ON CONFLICT`
   pattern to avoid race conditions.

Return types:
- `get_registration/2`: `{:ok, Registerable.t()} | {:error, :not_found}` — any struct implementing `Ltix.Registerable`
- `get_deployment/2`: `{:ok, Deployable.t()} | {:error, :not_found}` — any struct implementing `Ltix.Deployable`
- `store_nonce/2`: `:ok`
- `validate_nonce/2`: `:ok | {:error, :nonce_already_used | :nonce_not_found}`

**Nonce is consumed on callback.** `handle_callback/3` consumes the nonce as part of
validation. If the callback fails for a non-security reason (e.g., `DeploymentNotFound`),
you cannot retry `handle_callback/3` with the same params — the nonce is already gone.
Handle recoverable errors (like auto-creating a deployment) in the storage adapter itself,
not by retrying the callback.

## Error Handling

Errors use the Splode framework with three classes:

- `:invalid` — bad input, missing claims, malformed JWT (HTTP 400)
- `:security` — bad signature, expired token, nonce replay (HTTP 401/403)
- `:unknown` — network errors, unexpected failures (HTTP 500)

Most errors carry a `.spec_ref` field pointing to the violated spec passage. Match on
specific error modules for targeted handling, or fall back to `.class` for broad categories:

```elixir
case Ltix.handle_callback(params, state) do
  {:ok, context} -> # success
  {:error, %Ltix.Errors.Invalid.DeploymentNotFound{}} -> # auto-create or onboard
  {:error, error} ->
    case Ltix.Errors.class(error) do
      :security -> # 401
      :invalid -> # 400
      :unknown -> # 500
    end
end
```

## Roles

- `Role.instructor?/1`, `Role.learner?/1`, `Role.teaching_assistant?/1` etc. check
  **context roles only** (course-level).
- For institution or system roles, use `Role.has_role?/4`.
- Platform granularity varies wildly:
  - Canvas: sends sub-roles (e.g., `Instructor#TeachingAssistant`)
  - Moodle: only `Instructor` or `Learner` (no sub-roles)
  - Others: varies by admin configuration
- **Design for the lowest common denominator** — only reliably expect Instructor vs Learner
  across all platforms.

## Cross-Origin & Iframe Considerations

LTI launches are cross-origin POSTs (platform domain to tool domain), often inside an
iframe:

- Phoenix defaults to `SameSite=Lax`, which blocks cross-origin POST cookies.
  Set `same_site: "None"` and `secure: true` in your endpoint session config.
- HTTPS is mandatory in both production and development (`mix phx.gen.cert` for dev certs).
- LTI tools are typically embedded in an iframe by the platform. Set a
  `Content-Security-Policy` header (`frame-ancestors 'self' *`) on LTI routes to allow
  this. The platform domains should be scoped down in production.
- The login endpoint should accept both GET and POST — the LTI spec allows either.
- **Never store `%LaunchContext{}` in the session.** The registration struct
  may contain `tool_jwk` (private key material). Extract only the fields
  you need (e.g., `subject`, `roles`, `context.id`).

## Service Availability

Advantage Service endpoints (grading, roster, deep linking) are optional per-launch. The
platform decides what to include based on tool configuration. **Always** check for
`ServiceNotAvailable` before assuming a service is present:

```elixir
case Ltix.GradeService.authenticate(context) do
  {:ok, client} -> # service available
  {:error, %Ltix.Errors.Invalid.ServiceNotAvailable{}} -> # gracefully degrade
end
```

## Optional Configuration

- `:allow_anonymous` — allow launches without a `sub` claim (default: `false`)
- `:json_library` — auto-detected (`JSON` on Elixir 1.18+/OTP 27+, else `Jason`)
- `:req_options` — default HTTP options for all outgoing requests
- `:jwks_cache` — module implementing `Ltix.JWT.KeySet.Cache` (default: ETS-based)
- Custom claim/role parsers under the `Ltix.LaunchClaims` config key

## Finding Documentation

Use the `usage_rules.docs` and `usage_rules.search_docs` mix tasks:

```
mix usage_rules.docs Ltix.GradeService
mix usage_rules.docs Ltix.GradeService.Score.new/1
mix usage_rules.search_docs "line items" -p ltix
mix usage_rules.search_docs "storage adapter" -p ltix
```

Hexdocs can serve raw markdown, which is much easier to read than HTML. Fetch module
docs and guides directly:

```
# Module docs
https://hexdocs.pm/ltix/Ltix.GradeService.md
https://hexdocs.pm/ltix/Ltix.StorageAdapter.md

# Guides
https://hexdocs.pm/ltix/getting-started.md
https://hexdocs.pm/ltix/storage-adapters.md
https://hexdocs.pm/ltix/error-handling.md
https://hexdocs.pm/ltix/advantage-services.md
https://hexdocs.pm/ltix/deep-linking.md
https://hexdocs.pm/ltix/grade-service.md
https://hexdocs.pm/ltix/memberships-service.md
https://hexdocs.pm/ltix/working-with-roles.md
https://hexdocs.pm/ltix/jwk-management.md

# Cookbooks
https://hexdocs.pm/ltix/testing-lti-launches.md
https://hexdocs.pm/ltix/score-construction.md
https://hexdocs.pm/ltix/building-content-items.md
https://hexdocs.pm/ltix/token-caching-and-reuse.md
https://hexdocs.pm/ltix/auto-create-deployments.md
https://hexdocs.pm/ltix/background-grade-sync.md
```

Use the `.md` URLs with `curl` or web fetch tools for detailed reference when the mix
tasks don't give enough context.

## Skills

Ltix ships two pre-built skills for common integration tasks. These are step-by-step
guides with collaboration checkpoints — they prompt you to ask the user about app-specific
decisions before writing code.

- **`implement-storage-adapter`** — implement `Ltix.StorageAdapter` with Ecto schemas,
  nonce management, and deployment policy decisions
- **`add-lti-launch`** — wire up LTI 1.3 launch endpoints in a Phoenix app (routes,
  session config, CSRF pipeline, controller skeleton)
