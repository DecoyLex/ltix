# Getting Started

This guide walks through integrating Ltix into a Phoenix application,
from installation to a working LTI 1.3 launch. By the end you'll have
a tool that accepts launches from any LTI 1.3 platform.

A complete working example lives in `examples/phoenix_example/`.

## Installation

Add `:ltix` to your dependencies:

```elixir
# mix.exs
defp deps do
  [
    {:ltix, "~> 0.1"}
  ]
end
```

Then configure the storage adapter:

```elixir
# config/config.exs
config :ltix, storage_adapter: MyApp.LtiStorage
```

## Implement a storage adapter

Ltix is storage-agnostic. Your app provides lookups and nonce management
by implementing the `Ltix.StorageAdapter` behaviour. There are four
callbacks:

| Callback | Called during | Purpose |
|---|---|---|
| `get_registration/2` | Login initiation | Look up a platform by issuer (and optional client_id) |
| `get_deployment/2` | Launch validation | Look up a deployment by registration + deployment_id |
| `store_nonce/2` | Login initiation | Persist a nonce for later verification |
| `validate_nonce/2` | Launch validation | Verify a nonce was issued by us and consume it |

Here's a minimal in-memory implementation using an Agent:

```elixir
defmodule MyApp.LtiStorage do
  @behaviour Ltix.StorageAdapter

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> MapSet.new() end, name: __MODULE__)
  end

  @impl true
  def get_registration(issuer, _client_id) do
    # Look up the registration by issuer.
    # In production, query your database here.
    case MyApp.Registrations.get_by_issuer(issuer) do
      nil -> {:error, :not_found}
      reg -> {:ok, reg}
    end
  end

  @impl true
  def get_deployment(registration, deployment_id) do
    case MyApp.Deployments.get(registration, deployment_id) do
      nil -> {:error, :not_found}
      dep -> {:ok, dep}
    end
  end

  @impl true
  def store_nonce(nonce, _registration) do
    Agent.update(__MODULE__, &MapSet.put(&1, nonce))
    :ok
  end

  @impl true
  def validate_nonce(nonce, _registration) do
    Agent.get_and_update(__MODULE__, fn nonces ->
      if MapSet.member?(nonces, nonce) do
        {:ok, MapSet.delete(nonces, nonce)}
      else
        {{:error, :nonce_not_found}, nonces}
      end
    end)
  end
end
```

Start the Agent in your supervision tree:

```elixir
# lib/my_app/application.ex
children = [
  MyApp.LtiStorage,
  # ...
]
```

> #### Production {: .warning}
>
> The in-memory Agent is fine for development. In production, store
> nonces in your database with a TTL so they expire automatically.
> The `validate_nonce/2` callback must atomically check and consume
> the nonce to prevent replay attacks.

Registrations are created out-of-band when a platform administrator
sets up your tool. Each registration carries the platform's issuer,
client_id, and endpoint URLs. See `Ltix.Registration` for the full
struct.

## Add routes

LTI launches are a two-step redirect flow. The platform POSTs to your
login endpoint, your tool redirects to the platform for authentication,
and the platform POSTs back to your launch endpoint. Both endpoints
receive cross-origin form POSTs, so they need a pipeline **without**
CSRF protection:

```elixir
# lib/my_app_web/router.ex

pipeline :lti do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
end

scope "/lti", MyAppWeb do
  pipe_through :lti

  post "/login", LtiController, :login
  post "/launch", LtiController, :launch
end
```

The standard `:browser` pipeline includes `:protect_from_forgery`, which
would reject the platform's POSTs. The `:lti` pipeline omits it — this
is safe because the OIDC state parameter provides CSRF protection
instead.

## Wire the controller

The controller has two actions that map directly to the two Ltix
entry points:

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

      {:error, reason} ->
        conn
        |> put_status(400)
        |> text("Login initiation failed: #{Exception.message(reason)}")
    end
  end

  def launch(conn, params) do
    state = get_session(conn, :lti_state)

    case Ltix.handle_callback(params, state) do
      {:ok, context} ->
        conn
        |> delete_session(:lti_state)
        |> render(:launch, context: context)

      {:error, reason} ->
        conn
        |> put_status(401)
        |> text("Launch validation failed: #{Exception.message(reason)}")
    end
  end
end
```

**Login** calls `Ltix.handle_login/3` with the platform's POST params
and your launch URL. It returns a redirect URI and a state value.
Store the state in the session and redirect the user to the platform.

**Launch** retrieves the state from the session and passes it to
`Ltix.handle_callback/3` along with the platform's POST params. On
success you get a `%Ltix.LaunchContext{}` containing the validated
claims, registration, and deployment. Clean up the session state after
use.

The `context.claims` struct gives you everything about the launch:

```elixir
context.claims.subject          # user ID
context.claims.name             # display name
context.claims.roles            # [%Role{type: :context, name: :learner, ...}, ...]
context.claims.context          # %Context{id: "course-1", title: "Intro to Elixir"}
context.claims.resource_link    # %ResourceLink{id: "link-1", title: "Assignment 1"}
context.claims.target_link_uri  # where the user intended to go
```

See `Ltix.LaunchClaims` for the full list of fields.

## Configure the session for cross-origin POSTs

LTI launches are cross-origin — the platform at one domain POSTs to
your tool at another. By default, Phoenix sets `SameSite=Lax` on
session cookies, which means the browser won't include the cookie on
cross-origin POSTs. The state stored during login will be lost by the
time the launch arrives.

Set `SameSite=None` and `Secure=true` in your endpoint:

```elixir
# lib/my_app_web/endpoint.ex

@session_options [
  store: :cookie,
  key: "_my_app_key",
  signing_salt: "...",
  same_site: "None",
  secure: true
]
```

`SameSite=None` requires `Secure`, which requires HTTPS — see the next
section.

## Enable TLS

LTI requires HTTPS on all tool endpoints. For development, generate a
self-signed certificate:

```bash
mix phx.gen.cert
```

Then configure your endpoint to use HTTPS:

```elixir
# config/dev.exs
config :my_app, MyAppWeb.Endpoint,
  https: [
    ip: {127, 0, 0, 1},
    port: 4000,
    cipher_suite: :strong,
    keyfile: "priv/cert/selfsigned_key.pem",
    certfile: "priv/cert/selfsigned.pem"
  ]
```

Your browser will warn about the self-signed certificate — accept it
before attempting a launch so the platform's redirect doesn't fail
silently.

## Test with the IMS Reference Implementation

The [IMS LTI Reference Implementation](https://lti-ri.imsglobal.org)
provides a test platform you can launch from. Here's how to wire it up.

### Create a platform

1. Go to [Manage Platforms](https://lti-ri.imsglobal.org/platforms) and
   click **Add Platform**
2. Fill in a name, client ID (e.g. `my-tool`), and audience
3. Generate keys at [Generate Keys](https://lti-ri.imsglobal.org/keygen)
   and paste the public and private keys into the platform form
4. Save the platform

### Add a deployment

1. View your platform and click **Platform Keys**
2. Click **Add Platform Key**, give it a name and a deployment ID
   (e.g. `1`)
3. Save — note the **well-known/jwks URL** on this page

### Configure your storage adapter

Copy the values from the RI platform page into your storage adapter.
You need:

| RI Platform field | Storage field |
|---|---|
| Issuer (shown on platform page) | `Registration` `:issuer` |
| Client ID (what you entered) | `Registration` `:client_id` |
| OIDC Auth URL | `Registration` `:auth_endpoint` |
| well-known/jwks URL (from Platform Keys) | `Registration` `:jwks_uri` |
| Deployment ID (from Platform Keys) | `Deployment` `:deployment_id` |

### Add a resource link

1. View your platform and click **Resource Links**
2. Fill in the form with:
   - **Tool link url:** `https://localhost:4000/lti/launch`
   - **Login initiation url:** `https://localhost:4000/lti/login`
3. Save

### Add a course

1. View your platform and click **Courses**
2. Fill in a course name and save

### Launch

1. View your platform and click **Resource Links**
2. Click **Select User for Launch**, then **Launch with New User**
3. Scroll down and click **Perform Launch**

If everything is configured correctly, you'll see your launch page
with the parsed launch data — user info, roles, context, and resource
link.

## Next steps

- `Ltix.StorageAdapter` — full callback documentation
- `Ltix.LaunchContext` — what a successful launch returns
- `Ltix.LaunchClaims` — all available claim fields
- `Ltix.LaunchClaims.Role` — role parsing and predicates
- `examples/phoenix_example/` — complete working Phoenix app
