---
name: add-lti-launch
description: "Use this skill when adding LTI 1.3 launch support to a Phoenix application. Covers route setup, session handling, HTTPS configuration, and the full OIDC login-to-launch flow, with collaboration checkpoints for app-specific decisions."
---

# Add LTI Launch to a Phoenix App

This skill walks through wiring up LTI 1.3 launch endpoints in a Phoenix application.

## Prerequisites

- Ltix is installed as a dependency
- A storage adapter is implemented (see the `implement-storage-adapter` skill)
- `config :ltix, storage_adapter: MyApp.Lti.StorageAdapter` is set
- `Ltix.JWT.KeySet.EtsCache` is started in the supervision tree (see Step 1)

## Before You Start — Survey the User

These decisions are app-specific and affect security, UX, and architecture. **Enter plan
mode** (or use a tool that asks the user questions) to gather answers before writing any
code. Explore the codebase first to pre-fill what you can infer (existing router
structure, session config, endpoint setup), then ask about the rest:

1. **Route paths**: Where should the LTI endpoints live? (e.g., `/lti/login` and
   `/lti/launch`, or nested under an existing scope?) Check the existing router for
   conventions.

2. **CSRF strategy**: Phoenix's default CSRF protection blocks cross-origin POSTs. The
   LTI spec uses nonces for replay protection instead. The recommended approach is two
   pipelines:
   - `:lti_launch` — no CSRF protection, for the login and launch POST endpoints
   - `:lti` — with CSRF protection, for post-launch routes that need it

3. **Iframe strategy**: Most LTI tools render inside the platform's iframe. Three
   approaches exist:
   - **Full iframe** (most common): set `same_site: "None"` and `secure: true` on
     your session cookie in the endpoint. Your entire app works in the iframe with a
     single session cookie. This is the simplest path.
   - **New tab launches**: set `target` to `_blank` in the platform's tool
     configuration. The launch opens a new browser tab where cookies are first-party,
     so no `SameSite` changes are needed.
   - **Split rendering**: serve a lightweight iframe view for the launch, then link out
     to the full app in a new tab for deeper interaction. Lets you keep `SameSite=Lax`
     on most routes.

   The examples below assume the iframe approach.

4. **Post-launch behavior**: What should happen after a successful launch?
   - Redirect to a specific page based on `target_link_uri`?
   - Create a local user session? Map to an existing user?
   - Store claims for later use? Which ones?
   - The controller's launch logic is entirely product-specific.

5. **Deep linking**: Does the app need to support deep linking (content selection)?
   If yes, where should the content picker UI live?

6. **Error rendering**: Should launch errors render a user-friendly error page, return
   JSON, or something else?

## Step 1: Supervision Tree

Ltix caches platform public keys in ETS so it doesn't re-fetch them on every launch.
The cache is backed by a GenServer that must be started in your supervision tree:

```elixir
# lib/my_app/application.ex
children = [
  # ... your existing children (Repo, Endpoint, etc.)
  Ltix.JWT.KeySet.EtsCache
]
```

If you already use Cachex, you can use `Ltix.JWT.KeySet.CachexCache` instead. See its
docs for setup instructions.

## Step 2: HTTPS & Session Configuration

LTI launches are cross-origin POSTs inside an iframe. Session cookies must be configured
for this.

**Confirm with the user** before modifying the endpoint session config — this change
affects all routes:

```elixir
# lib/my_app_web/endpoint.ex — update the session plug
plug Plug.Session,
  store: :cookie,
  key: "_my_app_key",
  signing_salt: "...",
  same_site: "None", # <-- Change from "Lax" to "None"
  secure: true # <-- Add this line
```

Without `same_site: "None"`, the browser silently drops the session cookie inside the
iframe and the state check fails. This is the most common source of "launch just
silently fails" issues.

For development, HTTPS is required. If your user isn't using a reverse proxy that handles TLS (like Caddy),
they'll need to set up a self-signed certificate and configure the Phoenix endpoint to use it:

```elixir
# config/dev.exs — generate certs with: mix phx.gen.cert
config :my_app, MyAppWeb.Endpoint,
  https: [
    port: 4001,
    cipher_suite: :strong,
    keyfile: "priv/cert/selfsigned_key.pem",
    certfile: "priv/cert/selfsigned.pem"
  ]
```

You can generate self-signed certs with `mix phx.gen.cert`.

**Dev tip**: Have the user visit `https://localhost:4001` and accept the self-signed
certificate warning before attempting LTI launches. The platform's redirect will fail
if the cert is not trusted by the browser.

## Step 3: Routes

Two pipelines handle the different security requirements. `:lti_launch` omits CSRF
protection for the platform-to-tool POST endpoints. `:lti` adds CSRF protection for
post-launch routes where the user is interacting with the tool directly.

```elixir
# lib/my_app_web/router.ex
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :lti_launch do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    # Override the default CSP to allow iframe embedding. Adjust this if you want
    # to restrict which platforms can embed your tool.
    plug :put_secure_browser_headers, %{
      "content-security-policy" => "base-uri 'self'; frame-ancestors 'self' https:;"
    }
    # plug :protect_from_forgery <--- Omit this plug during the launch flow
    # since platforms POST directly to your tool.
    plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
  end

  pipeline :lti do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :put_secure_browser_headers, %{
      "content-security-policy" => "base-uri 'self'; frame-ancestors 'self' https:;"
    }
    plug :protect_from_forgery
    plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
  end

  scope "/lti", MyAppWeb do
    pipe_through :lti_launch

    post "/login", LtiController, :login
    post "/launch", LtiController, :launch
    get "/jwks", LtiController, :jwks
  end

  scope "/lti", MyAppWeb do
    # Post-launch routes that require CSRF protection
    pipe_through :lti

    live "/dashboard", DashboardLive
  end

  # ... your other routes
end
```

Two things to note:

- `protect_from_forgery` is omitted in `:lti_launch` because platforms POST directly to
  your tool. The LTI specification provides CSRF protection through `state` and `nonce`
  parameters, which Ltix validates for you.
- `put_secure_browser_headers` overrides the default CSP to set
  `frame-ancestors 'self' https:`, allowing any HTTPS origin to embed the tool. Phoenix
  defaults to `frame-ancestors 'self'`, which blocks iframe embedding.

## Step 4: Controller

The login action is mostly mechanical. The launch action's success path is where the
app-specific decisions from "Before You Start" come in:

```elixir
defmodule MyAppWeb.LtiController do
  use MyAppWeb, :controller

  alias MyApp.Lti

  def login(conn, params) do
    launch_url = url(conn, ~p"/lti/launch")

    case Ltix.handle_login(params, launch_url) do
      {:ok, %{redirect_uri: redirect_uri, state: state}} ->
        conn
        |> put_session(:lti_state, state)
        |> redirect(external: redirect_uri)

      {:error, error} ->
        conn
        |> put_status(Ltix.Errors.status_code(error))
        |> render(:error, message: Exception.message(error))
    end
  end

  def launch(conn, params) do
    state = get_session(conn, :lti_state)

    case Ltix.handle_callback(params, state) do
      {:ok, context} ->
        conn
        |> delete_session(:lti_state)
        |> handle_launch(context)

      {:error, error} ->
        conn
        |> put_status(Ltix.Errors.status_code(error))
        |> render(:error, message: Exception.message(error))
    end
  end

  def jwks(conn, _params) do
    keys =
      Lti.list_active_jwks()
      |> Enum.map(fn key ->
        {:ok, jwk} = Ltix.JWK.new(private_key_pem: key.private_key_pem, kid: key.kid)
        jwk
      end)

    json(conn, Ltix.JWK.to_jwks(keys))
  end

  # TODO: This is a skeleton — fill in based on the app's needs.
  # What session data to store, where to redirect, whether to create
  # a local user, etc. are all product decisions.
  #
  # context.registration is whatever your storage adapter returned
  # (e.g., your Ecto schema), so you can access database IDs and
  # custom fields directly.
  defp handle_launch(conn, context) do
    case context.claims.message_type do
      "LtiDeepLinkingRequest" ->
        # Show content picker UI — ask user where this lives
        raise "Deep linking UI not yet implemented"

      "LtiResourceLinkRequest" ->
        user = Lti.create_user!(context)
        course = Lti.create_course!(context)

        conn
        |> put_session(:user_id, user.id)
        |> put_session(:course_id, course.id)
        |> redirect(to: ~p"/lti/dashboard")
    end
  end
end
```

Key points about the controller:

- **`Ltix.Errors.status_code/1`** returns the HTTP status code for any Ltix error
  (400 for invalid, 401 for security, 500 for unknown). Use this instead of manually
  mapping error classes.
- **`context.registration`** is whatever your `get_registration/2` callback returned
  (your Ecto schema), not the internal `Ltix.Registration`. Access your own fields
  directly (e.g., `context.registration.id`).
- **`context.deployment`** is similarly your original struct from `get_deployment/2`.
- **Delete `lti_state` from session** after a successful launch to prevent replay.
- **Never store `%LaunchContext{}` in the session.** It contains the full
  `%Registration{}`, which includes `tool_jwk` — private key material. Store only the
  fields you need (e.g., `user_id`, `course_id`).
- **The JWKS endpoint** reconstructs `%Ltix.JWK{}` structs from your stored
  `private_key_pem` + `kid` via `Ltix.JWK.new/1`. `Ltix.JWK.to_jwks/1` strips private
  key material automatically — safe to pass private keys directly.

## Step 5: Test Setup

```elixir
# config/test.exs
config :ltix, storage_adapter: Ltix.Test.StorageAdapter
```

Example controller test — adapt route paths and assertions to match the app:

```elixir
defmodule MyAppWeb.LtiControllerTest do
  use MyAppWeb.ConnCase

  setup do
    %{platform: Ltix.Test.setup_platform!()}
  end

  test "full OIDC launch flow", %{conn: conn, platform: platform} do
    # Step 1: Login initiation
    conn = post(conn, ~p"/lti/login", Ltix.Test.login_params(platform))
    assert redirected_to(conn, 302)

    state = get_session(conn, :lti_state)
    nonce = Ltix.Test.extract_nonce(redirected_to(conn, 302))

    # Step 2: Launch callback
    conn =
      conn
      |> recycle()
      |> Plug.Test.init_test_session(%{lti_state: state})
      |> post(~p"/lti/launch",
        Ltix.Test.launch_params(platform,
          nonce: nonce,
          state: state,
          roles: [:instructor]
        )
      )

    # Adapt this assertion to match the app's post-launch behavior
    assert redirected_to(conn, 302)
  end
end
```

## Technical Constraints

These are non-negotiable requirements from the LTI spec:

- **`Ltix.JWT.KeySet.EtsCache` must be in the supervision tree.** It's a GenServer that
  owns the ETS table for caching platform public keys. Without it, launch validation
  will fail.
- **State goes in the session**, not in query params or cookies. Store during login,
  retrieve during launch, delete after successful launch.
- **Both login and launch endpoints are POST routes.** The platform sends form-encoded POSTs, not GETs.
- **HTTPS is mandatory** in both production and development.
- **`same_site: "None"` and `secure: true`** are required for session cookies to survive
  cross-origin redirects in iframes.
- **Delete `lti_state` from session** after a successful launch to prevent replay.
- **Never store `%LaunchContext{}` in the session.** It contains the full
  `%Registration{}`, which includes `tool_jwk` — private key material. Store only the
  fields you need (e.g., `subject`, `roles`, `context.id`).
