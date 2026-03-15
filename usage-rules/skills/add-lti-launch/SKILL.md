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

## Before You Start — Ask the User

These decisions are app-specific and affect security, UX, and architecture. Clarify before
writing code:

1. **Route paths**: Where should the LTI endpoints live? (e.g., `/lti/login` and
   `/lti/launch`, or nested under an existing scope?) Check the existing router for
   conventions.

2. **CSRF strategy**: Phoenix's default CSRF protection blocks cross-origin POSTs. The
   LTI spec uses nonces for replay protection instead. Options:
   - A dedicated pipeline without `:protect_from_forgery` for LTI routes only
   - Excluding specific routes from CSRF
   Ask the user which approach they prefer — this has security implications for the rest
   of the app.

   Recommendation: Use a dedicated pipeline for *just* the LTI launch routes to minimize risk:

   ```elixir
    pipeline :lti do
      plug :accepts, ["html"]
      plug :fetch_session
      # LTI typically uses an iframe for launches, so we need to set Content-Security-Policy headers to allow that.
      # Adjust the domains as needed in collaboration with the user.
      plug :put_resp_header, "content-security-policy", "frame-ancestors 'self' *; frame-src 'self' *"
      # No CSRF plug here
    end

    scope "/lti", MyAppWeb do
      pipe_through :lti

      post "/login", LtiController, :login
      post "/launch", LtiController, :launch
    end
   ```

3. **Session cookie changes**: LTI requires `same_site: "None"` and `secure: true` on
   session cookies. This affects **all** routes in the app, not just LTI. If the app has
   non-LTI routes that depend on `SameSite=Lax`, the user may want a separate session
   configuration or a dedicated endpoint for LTI. Confirm before modifying the endpoint.

4. **Post-launch behavior**: What should happen after a successful launch?
   - Redirect to a specific page based on `target_link_uri`?
   - Create a local user session? Map to an existing user?
   - Store claims for later use? Which ones?
   - The controller's `handle_launch` logic is entirely product-specific.

5. **Deep linking**: Does the app need to support deep linking (content selection)?
   If yes, where should the content picker UI live?

6. **Error rendering**: Should launch errors render a user-friendly error page, return
   JSON, or something else? The examples below use `text/plain` as a placeholder.

7. **JWK endpoint**: Does the app need a JWKS endpoint for platforms to fetch the tool's
   public key? (Required for deep linking and some OAuth flows.) If yes, how are keys
   stored and rotated?

## Step 1: HTTPS & Session Configuration

LTI launches are cross-origin POSTs. Session cookies must be configured for this.

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

## Step 2: Routes

Adapt paths based on the user's answers. The LTI spec allows both GET and POST for the login endpoint, so
it's recommended to generate both. The launch endpoint must be POST.

```elixir
# lib/my_app_web/router.ex
scope "/lti", MyAppWeb do
  pipe_through [:lti]  # the dedicated pipeline from the CSRF step — no CSRF

  get "/login", LtiController, :login
  post "/login", LtiController, :login

  post "/launch", LtiController, :launch
end
```

## Step 3: Controller

The login action is mostly mechanical. The launch action's success path is where the
app-specific decisions from "Before You Start" come in — the `handle_launch` function
below is a **skeleton** that must be filled in based on the user's answers:

```elixir
defmodule MyAppWeb.LtiController do
  use MyAppWeb, :controller

  def login(conn, params) do
    launch_url = url(conn, ~p"/lti/launch")

    case Ltix.handle_login(params, launch_url) do
      {:ok, %{redirect_uri: redirect_uri, state: state}} ->
        conn
        |> put_session(:lti_state, state)
        |> redirect(external: redirect_uri)

      {:error, error} ->
        conn
        |> put_status(400)
        |> text("Login initiation failed: #{Exception.message(error)}")
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
        status = error_status(error)

        conn
        |> put_status(status)
        |> text("Launch failed: #{Exception.message(error)}")
    end
  end

  # TODO: This is a skeleton — fill in based on the app's needs.
  # What session data to store, where to redirect, whether to create
  # a local user, etc. are all product decisions.
  defp handle_launch(conn, context) do
    case context.claims.message_type do
      "LtiDeepLinkingRequest" ->
        # Show content picker UI — ask user where this lives
        raise "Deep linking UI not yet implemented"

      "LtiResourceLinkRequest" ->
        # Normal launch — establish session, redirect
        # What to store and where to go depends on the app
        conn
        |> put_session(:lti_user_id, context.claims.subject)
        |> redirect(to: "/")
    end
  end

  defp error_status(error) do
    case Ltix.Errors.class(error) do
      :security -> 401
      :invalid -> 400
      :unknown -> 500
    end
  end
end
```

## Step 4: JWK Endpoint (If Needed)

Only needed if the app uses deep linking or certain OAuth flows. **Ask the user** how
keys are stored before implementing this.

```elixir
# In your router
get "/lti/jwks", LtiController, :jwks

# In the controller
def jwks(conn, _params) do
  # Where do keys come from? Database? Config? Ask the user.
  private_keys = MyApp.LtiKeys.active_private_keys()
  jwks = Ltix.JWK.to_jwks(private_keys)

  conn
  |> put_resp_content_type("application/json")
  |> json(jwks)
end
```

`Ltix.JWK.to_jwks/1` strips private key material automatically — safe to pass private
keys directly.

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

- **State goes in the session**, not in query params or cookies. Store during login,
  retrieve during launch, delete after successful launch.
- **Both endpoints are POST routes.** The platform sends form-encoded POSTs, not GETs.
- **HTTPS is mandatory** in both production and development.
- **`same_site: "None"` and `secure: true`** are required for session cookies to survive
  cross-origin redirects.
- **Delete `lti_state` from session** after a successful launch to prevent replay.
- **Never store `%LaunchContext{}` in the session.** It contains the full
  `%Registration{}`, which includes `tool_jwk` — private key material. Store only the
  fields you need (e.g., `subject`, `roles`, `context.id`).
