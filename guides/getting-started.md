# Getting Started

This guide walks you through adding LTI 1.3 launch support to a Phoenix
application. By the end, your app will handle launches from Canvas,
Moodle, Blackboard, or any other LTI 1.3 platform. You'll also have a
clear list of what's left to get it production-ready.

You'll need an existing Phoenix app with Ecto. If you'd like to
understand the protocol before diving in, read [LTI Advantage
Concepts](concepts.md) first.

## Installation

### Add the dependency

```elixir
# mix.exs
defp deps do
  [
    {:ltix, "~> 0.1"}
  ]
end
```

Run `mix deps.get` to fetch the package.

### Start the key cache

Ltix caches platform public keys in ETS so it doesn't re-fetch them on
every launch. Add the cache to your supervision tree:

```elixir
# lib/my_app/application.ex
children = [
  # ... your existing children (Repo, Endpoint, etc.)
  Ltix.JWT.KeySet.EtsCache
]
```

> #### Cachex alternative {: .tip}
>
> If you already use Cachex, you can use `Ltix.JWT.KeySet.CachexCache`
> instead. See `Ltix.JWT.KeySet.CachexCache` for setup instructions.

## Database schema

You need tables for four LTI concerns (signing keys, registrations,
deployments, and replay-prevention tokens) plus application tables for
users and courses. All the LTI schemas live under a `MyApp.Lti` context.

### Migration

```elixir
# priv/repo/migrations/XXXXXXXXXXXXXX_create_lti_tables.exs
defmodule MyApp.Repo.Migrations.CreateLtiTables do
  use Ecto.Migration

  def change do
    create table(:lti_jwks) do
      add :private_key_pem, :text, null: false
      add :kid, :string, null: false
      add :active, :boolean, default: true, null: false
      timestamps()
    end

    create unique_index(:lti_jwks, [:kid])

    create table(:lti_registrations) do
      add :issuer, :string, null: false
      add :client_id, :string, null: false
      add :auth_endpoint, :string, null: false
      add :jwks_uri, :string, null: false
      add :token_endpoint, :string
      add :jwk_id, references(:lti_jwks), null: false
      timestamps()
    end

    create unique_index(:lti_registrations, [:issuer, :client_id])

    create table(:lti_deployments) do
      add :deployment_id, :string, null: false
      add :registration_id, references(:lti_registrations), null: false
      timestamps()
    end

    create unique_index(:lti_deployments, [:deployment_id, :registration_id])

    create table(:lti_nonces) do
      add :nonce, :string, null: false
      add :issuer, :string, null: false
      timestamps(updated_at: false)
    end

    create unique_index(:lti_nonces, [:nonce, :issuer])

    create table(:users) do
      add :lti_sub, :string, null: false
      add :name, :string
      add :email, :string
      add :registration_id, references(:lti_registrations), null: false
      timestamps()
    end

    create unique_index(:users, [:lti_sub, :registration_id])

    create table(:courses) do
      add :context_id, :string, null: false
      add :title, :string
      add :registration_id, references(:lti_registrations), null: false
      timestamps()
    end

    create unique_index(:courses, [:context_id, :registration_id])
  end
end
```

Run `mix ecto.migrate`.

### Schemas

```elixir
# lib/my_app/lti/jwk.ex
defmodule MyApp.Lti.Jwk do
  use Ecto.Schema

  schema "lti_jwks" do
    field :private_key_pem, :string
    field :kid, :string
    field :active, :boolean, default: true
    timestamps()
  end
end
```

```elixir
# lib/my_app/lti/registration.ex
defmodule MyApp.Lti.Registration do
  use Ecto.Schema

  schema "lti_registrations" do
    field :issuer, :string
    field :client_id, :string
    field :auth_endpoint, :string
    field :jwks_uri, :string
    field :token_endpoint, :string
    belongs_to :jwk, MyApp.Lti.Jwk
    has_many :deployments, MyApp.Lti.Deployment
    timestamps()
  end
end

defimpl Ltix.Registerable, for: MyApp.Lti.Registration do
  def to_registration(registration) do
    {:ok, tool_jwk} =
      Ltix.JWK.new(
        private_key_pem: registration.jwk.private_key_pem,
        kid: registration.jwk.kid
      )

    Ltix.Registration.new(%{
      issuer: registration.issuer,
      client_id: registration.client_id,
      auth_endpoint: registration.auth_endpoint,
      jwks_uri: registration.jwks_uri,
      token_endpoint: registration.token_endpoint,
      tool_jwk: tool_jwk
    })
  end
end
```

```elixir
# lib/my_app/lti/deployment.ex
defmodule MyApp.Lti.Deployment do
  use Ecto.Schema

  schema "lti_deployments" do
    field :deployment_id, :string
    belongs_to :registration, MyApp.Lti.Registration
    timestamps()
  end
end

defimpl Ltix.Deployable, for: MyApp.Lti.Deployment do
  def to_deployment(deployment) do
    Ltix.Deployment.new(deployment.deployment_id)
  end
end
```

```elixir
# lib/my_app/lti/nonce.ex
defmodule MyApp.Lti.Nonce do
  use Ecto.Schema

  schema "lti_nonces" do
    field :nonce, :string
    field :issuer, :string
    timestamps(updated_at: false)
  end
end
```

```elixir
# lib/my_app/user.ex
defmodule MyApp.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :lti_sub, :string
    field :name, :string
    field :email, :string
    belongs_to :registration, MyApp.Lti.Registration
    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:lti_sub, :name, :email, :registration_id])
    |> validate_required([:lti_sub, :registration_id])
    |> unique_constraint([:lti_sub, :registration_id])
  end
end
```

```elixir
# lib/my_app/course.ex
defmodule MyApp.Course do
  use Ecto.Schema
  import Ecto.Changeset

  schema "courses" do
    field :context_id, :string
    field :title, :string
    belongs_to :registration, MyApp.Lti.Registration
    timestamps()
  end

  def changeset(course, attrs) do
    course
    |> cast(attrs, [:context_id, :title, :registration_id])
    |> validate_required([:context_id, :registration_id])
    |> unique_constraint([:context_id, :registration_id])
  end
end
```

### Context module

The `MyApp.Lti` context module handles persistence for launch data and
key management:

```elixir
# lib/my_app/lti.ex
defmodule MyApp.Lti do
  alias MyApp.{Course, Repo, User}
  alias MyApp.Lti.{Deployment, Jwk, Nonce, Registration}

  import Ecto.Query

  def create_user!(%Ltix.LaunchContext{claims: claims, registration: registration}) do
    attrs = %{
      lti_sub: claims.subject,
      registration_id: registration.id,
      name: claims.name,
      email: claims.email
    }

    %User{}
    |> User.changeset(attrs)
    |> Repo.insert!(
      on_conflict: {:replace, [:name, :email, :updated_at]},
      conflict_target: [:lti_sub, :registration_id],
      returning: true
    )
  end

  def create_course!(%Ltix.LaunchContext{claims: claims, registration: registration}) do
    attrs = %{
      context_id: claims.context.id,
      registration_id: registration.id,
      title: claims.context.title
    }

    %Course{}
    |> Course.changeset(attrs)
    |> Repo.insert!(
      on_conflict: {:replace, [:title, :updated_at]},
      conflict_target: [:context_id, :registration_id],
      returning: true
    )
  end

  def list_active_jwks do
    Repo.all(from j in Jwk, where: j.active == true)
  end

  def get_registration(issuer, client_id) do
    registration =
      Repo.get_by(Registration, issuer: issuer, client_id: client_id)
      |> Repo.preload(:jwk)

    case registration do
      nil -> {:error, :not_found}
      registration -> {:ok, registration}
    end
  end

  def get_deployment(%Ltix.Registration{issuer: issuer, client_id: client_id}, deployment_id) do
    query =
      from d in Deployment,
        join: r in Registration,
        on: d.registration_id == r.id,
        where: r.issuer == ^issuer and r.client_id == ^client_id,
        where: d.deployment_id == ^deployment_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      deployment -> {:ok, deployment}
    end
  end

  def store_nonce(nonce, %Ltix.Registration{issuer: issuer}) do
    Repo.insert!(%Nonce{nonce: nonce, issuer: issuer})
    :ok
  end

  def validate_nonce(nonce, %Ltix.Registration{issuer: issuer}) do
    case Repo.delete_all(
           from n in Nonce,
             where: n.nonce == ^nonce and n.issuer == ^issuer
         ) do
      {1, _} -> :ok
      {0, _} -> {:error, :nonce_not_found}
    end
  end
end
```

### Multitenancy

Where you draw tenant boundaries depends on your application. Two
common approaches:

- **Tenant per registration**: each platform + `client_id` pair is a
  tenant. This works well for cloud-hosted platforms like Canvas Cloud
  or Schoology, where many institutions share a common issuer URL but
  each institution gets its own `client_id`. The registration is your
  natural tenant boundary.

- **Tenant per deployment**: a single registration can have multiple
  deployments (e.g., a tool installed across departments). If you need
  isolation within a single institution, use the deployment as your
  tenant boundary instead.

The examples in this guide tenant on registration for simplicity.

## Storage adapter

Ltix needs your application to look up registrations and deployments,
and to manage nonces (one-time tokens that prevent replay attacks). You
provide these through the `Ltix.StorageAdapter` behaviour.

```elixir
# lib/my_app/lti/storage.ex
defmodule MyApp.Lti.Storage do
  @behaviour Ltix.StorageAdapter

  alias MyApp.Lti

  @impl true
  def get_registration(issuer, client_id), do: Lti.get_registration(issuer, client_id)

  @impl true
  def get_deployment(registration, deployment_id), do: Lti.get_deployment(registration, deployment_id)

  @impl true
  def store_nonce(nonce, registration), do: Lti.store_nonce(nonce, registration)

  @impl true
  def validate_nonce(nonce, registration), do: Lti.validate_nonce(nonce, registration)
end
```

The storage adapter is a thin wrapper that delegates to your context
module, where the actual queries live.

> #### Nil client_id {: .tip}
>
> Older versions of some platforms may omit `client_id` from the login
> request, in which case `get_registration/2` receives `nil` as the
> second argument. If you need to support this, add a function head
> that looks up by issuer alone. See
> [Storage Adapters](storage-adapters.md) for details.

For more on nonce expiry, custom structs, and per-call adapter
overrides, see [Storage Adapters](storage-adapters.md).

## Configuration

Tell Ltix which storage adapter to use:

```elixir
# config/config.exs
config :ltix,
  storage_adapter: MyApp.Lti.Storage
```

All configuration can also be passed or overridden per-call via opts.
See `Ltix` for the full list of options.

## Registering a platform

Before your tool can accept launches, you need to exchange configuration
with the platform. The 1EdTech specs leave this as an out-of-band
process: the platform gives you its URLs and a client ID, and you give
it your tool's launch URL and public key endpoint.
[LTI Dynamic Registration](https://www.imsglobal.org/spec/lti-dr/v1p0)
automates this exchange, but Ltix does not currently support it.

How you handle new registrations in your app is entirely up to you.
Some tools render a registration page when a launch arrives from an
unrecognized issuer/client_id pair. Others have an admin UI. For this
guide, we'll seed the data through IEx.

### Generate a signing key

Your tool needs at least one RSA signing key to get started. Open IEx
and generate one:

```
$ iex -S mix

iex> alias MyApp.{Lti, Repo}

iex> tool_jwk = Ltix.JWK.generate()

iex> Repo.insert!(%Lti.Jwk{
...>   private_key_pem: tool_jwk.private_key_pem,
...>   kid: tool_jwk.kid
...> })
```

For key rotation in production, see [JWK Management](jwk-management.md).

### Add a registration

Each platform you connect to needs a registration and at least one
deployment. Construct an `Ltix.Registration` before persisting to
validate that all the fields are correct and the launch will work:

```
iex> attrs = %{
...>   issuer: "https://canvas.example.edu",
...>   client_id: "10000000000042",
...>   auth_endpoint: "https://canvas.example.edu/api/lti/authorize_redirect",
...>   jwks_uri: "https://canvas.example.edu/api/lti/security/jwks",
...>   token_endpoint: "https://canvas.example.edu/login/oauth2/token",
...>   tool_jwk: tool_jwk
...> }

iex> {:ok, _} = Ltix.Registration.new(attrs)
```

Once it passes validation, persist it:

```
iex> [jwk] = Repo.all(Lti.Jwk)

iex> registration = Repo.insert!(%Lti.Registration{
...>   issuer: "https://canvas.example.edu",
...>   client_id: "10000000000042",
...>   auth_endpoint: "https://canvas.example.edu/api/lti/authorize_redirect",
...>   jwks_uri: "https://canvas.example.edu/api/lti/security/jwks",
...>   token_endpoint: "https://canvas.example.edu/login/oauth2/token",
...>   jwk_id: jwk.id
...> })

iex> Repo.insert!(%Lti.Deployment{
...>   deployment_id: "1",
...>   registration_id: registration.id
...> })
```

The exact URLs and IDs depend on your platform. Check your platform's
LTI developer documentation for where to find them.

## Phoenix setup

### Routes and pipeline

LTI launches differ from normal browser requests in two ways:

1. Platforms POST directly to your tool, so CSRF protection must be
   disabled on LTI routes.
2. Launches typically happen inside an iframe on the platform, so
   session cookies need `SameSite=None` and `Secure` to work in
   the third-party context.

### Iframe strategy

Most LTI tools render inside the platform's iframe. If that's your
plan, configure `SameSite=None` on your session cookie in the
endpoint so it applies to all routes:

```elixir
# lib/my_app_web/endpoint.ex

# Change your existing Plug.Session to:
plug Plug.Session,
  store: :cookie,
  key: "_my_app_key",
  signing_salt: "your-salt",
  same_site: "None",
  secure: true
```

This is the simplest path. Your entire app works in the iframe with a
single session cookie.

> #### Iframe sessions {: .warning}
>
> Without `same_site: "None"`, the browser silently drops the session
> cookie inside the iframe and your state check fails. This is the
> most common source of "launch just silently fails" issues.
>
> `SameSite=None` requires `secure: true`, which means HTTPS. You'll
> need HTTPS in development too (e.g., via `mix phx.gen.cert`).

Two other approaches exist if rendering everything in an iframe doesn't
fit your app:

- **New tab launches**: set `target` to `_blank` in the platform's tool
  configuration. The launch opens a new browser tab where cookies are
  first-party, so no `SameSite` changes are needed. This works well for
  apps with complex navigation that doesn't fit an iframe.

- **Split rendering**: serve a lightweight iframe view for the launch,
  then link out to the full app in a new tab for deeper interaction.
  This lets you keep `SameSite=Lax` on most routes while only the LTI
  endpoints use `SameSite=None`.

The examples below assume the iframe approach.

### Routes

```elixir
# lib/my_app_web/router.ex
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :lti_launch do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    # Override the default CSP to allow embedding. Adjust this if you want
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
    # Post-launch routes that require CSRF protection can go here with a different pipeline
    pipe_through :lti

    live "/dashboard", DashboardLive
  end

  # ... your other routes
end
```

Two things to note about these pipelines:

- `protect_from_forgery` is omitted in the `:lti_launch` pipeline
  because platforms POST directly to your tool. The LTI specification
  provides for CSRF protection through the `state` and `nonce`
  parameters, which Ltix validates for you. Past the launch, we
  recommend enabling Phoenix's CSRF protection. This is done in the
  `:lti` pipeline in the example above, but you can organize your
  routes and pipelines however it makes sense for your app.
- `put_secure_browser_headers` overrides the default CSP to set
  `frame-ancestors 'self' https:`, allowing any HTTPS origin to embed the
  tool. Phoenix defaults to `frame-ancestors 'self'`, which blocks
  iframe embedding. If your tool knows each platform's origin, you
  could restrict `frame-ancestors` per tenant after launch, but the
  login endpoint (and registration endpoint, if you implement dynamic
  registration) must remain open. Whether the extra complexity is
  worth it depends on your threat model.

### Controller

```elixir
# lib/my_app_web/controllers/lti_controller.ex
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
        user = Lti.create_user!(context)
        course = Lti.create_course!(context)

        conn
        |> delete_session(:lti_state)
        |> put_session(:user_id, user.id)
        |> put_session(:course_id, course.id)
        |> render(:launch, context: context, user: user, course: course)

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
end
```

The view module and templates:

```elixir
# lib/my_app_web/controllers/lti_html.ex
defmodule MyAppWeb.LtiHTML do
  use MyAppWeb, :html

  embed_templates "lti_html/*"
end
```

```heex
<%!-- lib/my_app_web/controllers/lti_html/launch.html.heex --%>
<h1>Welcome, {@user.name}</h1>
<p>Course: {@course.title}</p>
<ul>
  <li :for={role <- @context.claims.roles}>{role.name}</li>
</ul>
```

```heex
<%!-- lib/my_app_web/controllers/lti_html/error.html.heex --%>
<h1>Launch failed</h1>
<p>{@message}</p>
```

The create-on-launch pattern shown here is common: extract the user
and course from the launch data, persist them, and set up a session.

This particular setup aligns with the platform-centric approach described in the
[Best Practices for LTI Assessment Tools](https://www.imsglobal.org/spec/lti/v1p3/impl-assess#account-binding).
If user accounts in your tool are separate from platform accounts (such as in
a standalone SaaS product), you might instead use a join table to link platform
users to your internal accounts. Use whatever account binding strategy works best
for your app.

For structured error matching (e.g., showing different messages for
security errors vs. invalid configuration), see
[Error Handling](error-handling.md).

## Public key endpoint

The `jwks` action in the controller above serves your tool's public
keys as a JSON Web Key Set (JWKS). When you register your tool with a
platform, give it this URL (e.g., `https://yourtool.com/lti/jwks`).
The platform fetches your public keys from here to verify signed
requests from your tool during Advantage service calls (grades, roster,
etc.).

`Ltix.JWK.to_jwks/1` strips private key material, so only public keys
are included in the response. Include multiple keys during
rotation so platforms can verify with either the current or previous
key. See [JWK Management](jwk-management.md) for rotation strategies.

## Next steps

You now have a working LTI launch. Here's what to tackle next on the
way to production:

- **Nonce cleanup**: the nonces table grows with every launch. Add a
  periodic job (e.g., Oban) that deletes nonces older than a few
  minutes. See [Storage Adapters](storage-adapters.md) for an example.

- **Key rotation**: signing keys should be rotated periodically.
  Serve both the old and new key from your public key endpoint during
  the transition. See [JWK Management](jwk-management.md).

- **Error handling**: the controller above returns raw error messages.
  Match on error classes to show users meaningful messages and log
  details for debugging. See [Error Handling](error-handling.md).

- **Role-based authorization**: decide what instructors, learners,
  and TAs can do in your tool. See
  [Working with Roles](working-with-roles.md).

- **Grades and roster**: send scores back to the LMS gradebook
  and fetch class lists. See
  [Advantage Services](advantage-services.md).

- **Tests**: Ltix provides test helpers that simulate the full
  launch flow without hitting a real platform. See
  [Testing LTI Launches](testing-lti-launches.md).
