# Getting Started

This guide shows you how to add LTI 1.3 launch support to a Phoenix application. By the end, your application will handle launches from Canvas, Moodle, Blackboard, or any other LTI 1.3 platform. You'll also have a clear list of what's left to get it production-ready.

You'll need an existing Phoenix application with Ecto. If you'd like to understand the protocol before starting, read [LTI Advantage Concepts](concepts.md) first.

## Installation

### Add the dependency

```elixir
# mix.exs
defp deps do
  [
    {:ltix, "~> 0.2"}
  ]
end
```

Run `mix deps.get` to fetch the package.

### Start the key set cache

Ltix verifies launches with each platform's public keys, which it gets from a key set cache. Add the key set cache to your supervision tree.

```elixir
# lib/my_app/application.ex
children = [
  # ... your existing children (Repo, Endpoint, etc.)
  Ltix.JWT.KeySet
]
```

### Set up key encryption

Your tool signs with private keys that you'll store in the database. Encrypt them there, so a database dump or a read-only breach doesn't expose your keys.

Use the encryption your application already has, or a key management service. If you have neither, we recommend [Cloak](https://cloak-ecto.hexdocs.pm). Follow its [install guide](https://cloak-ecto.hexdocs.pm/install.html) to set up a vault and a binary field type. This guide calls that type `MyApp.Encrypted.Binary`.

## Database schema

You need tables for four LTI concerns (signing keys, registrations, deployments, and replay-prevention tokens) plus application tables for users and courses. All the LTI schemas are under a `MyApp.Lti` context.

### Migration

```elixir
# priv/repo/migrations/XXXXXXXXXXXXXX_create_lti_tables.exs
defmodule MyApp.Repo.Migrations.CreateLtiTables do
  use Ecto.Migration

  def change do
    create table(:lti_jwks) do
      add :kid, :string, null: false
      add :public_key_pem, :text, null: false
      add :private_key_pem, :binary, null: false
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

    create table(:lti_nonces, primary_key: false) do
      add :nonce, :string, primary_key: true
      add :expires_at, :utc_datetime, null: false
    end

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
    field :kid, :string
    field :public_key_pem, :string
    field :private_key_pem, MyApp.Encrypted.Binary, redact: true
    field :active, :boolean, default: true
    timestamps()
  end
end
```

The private key is encrypted in the database and left out of `inspect`. If you encrypt with something other than Cloak, use its field type in place of `MyApp.Encrypted.Binary`. The public key is stored next to it, so serving your key set never reads a private key.

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
    Ltix.Registration.new(%{
      issuer: registration.issuer,
      client_id: registration.client_id,
      auth_endpoint: registration.auth_endpoint,
      jwks_uri: registration.jwks_uri,
      token_endpoint: registration.token_endpoint
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

  @primary_key {:nonce, :string, autogenerate: false}
  schema "lti_nonces" do
    field :expires_at, :utc_datetime
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

The `MyApp.Lti` context module handles persistence for launch data and key management.

```elixir
# lib/my_app/lti.ex
defmodule MyApp.Lti do
  alias MyApp.{Course, Repo, User}
  alias MyApp.Lti.{Deployment, Jwk, Nonce, Registration}

  import Ecto.Query

  def create_user!(%Ltix.Launch{claims: claims, source_registration: registration}) do
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

  # A launch from outside a course has no context claim.
  def create_course!(%Ltix.Launch{claims: %{context: nil}}), do: nil

  def create_course!(%Ltix.Launch{claims: %{context: context}, source_registration: registration}) do
    attrs = %{
      context_id: context.id,
      registration_id: registration.id,
      title: context.title
    }

    %Course{}
    |> Course.changeset(attrs)
    |> Repo.insert!(
      on_conflict: {:replace, [:title, :updated_at]},
      conflict_target: [:context_id, :registration_id],
      returning: true
    )
  end

  def create_jwk! do
    jwk = Ltix.JWK.generate()

    # Ecto's debug log prints query parameters, and the key is one of them.
    Repo.insert!(
      %Jwk{
        kid: jwk.kid,
        public_key_pem: jwk.public_key_pem,
        private_key_pem: jwk.private_key_pem
      },
      log: false
    )
  end

  def list_public_jwks do
    keys = Repo.all(from j in Jwk, where: j.active == true, select: {j.kid, j.public_key_pem})
    Enum.map(keys, fn {kid, pem} -> Ltix.JWK.new!(public_key_pem: pem, kid: kid) end)
  end

  # The platform left out client_id, so look up by issuer alone. An issuer
  # with several registrations is ambiguous and needs the client_id.
  def get_registration(issuer, nil) do
    case Repo.all(from r in Registration, where: r.issuer == ^issuer) do
      [registration] -> {:ok, registration}
      _none_or_several -> {:error, :not_found}
    end
  end

  def get_registration(issuer, client_id) do
    case Repo.get_by(Registration, issuer: issuer, client_id: client_id) do
      nil -> {:error, :not_found}
      registration -> {:ok, registration}
    end
  end

  def get_deployment(%Registration{id: registration_id}, deployment_id) do
    case Repo.get_by(Deployment, registration_id: registration_id, deployment_id: deployment_id) do
      nil -> {:error, :not_found}
      deployment -> {:ok, deployment}
    end
  end

  def validate_nonce(nonce, expires_at) do
    case Repo.insert_all(Nonce, [%{nonce: nonce, expires_at: expires_at}], on_conflict: :nothing) do
      {1, _} -> :ok
      {0, _} -> {:error, :nonce_already_used}
    end
  end

  def signing_key_id(%Registration{jwk_id: jwk_id}) do
    {:ok, Repo.get!(Jwk, jwk_id).kid}
  end

  def sign(key_id, message) do
    case Repo.get_by(Jwk, kid: key_id, active: true) do
      nil -> {:error, :unknown_key}
      jwk -> Ltix.JWK.sign(Ltix.JWK.new!(private_key_pem: jwk.private_key_pem, kid: jwk.kid), message)
    end
  end
end
```

### Multitenancy

Where you draw tenant boundaries depends on your application. Two approaches are common.

- **Tenant per registration** - each issuer and `client_id` pair is a tenant. This works well for cloud-hosted platforms like Canvas Cloud or Schoology, where many institutions share a common issuer URL but each institution gets its own `client_id`. The registration is your natural tenant boundary.

- **Tenant per deployment** - a single registration can have multiple deployments (for example, a tool installed across departments). If you need isolation within a single institution, use the deployment as your tenant boundary instead.

The examples in this guide tenant on registration for simplicity.

## Storage adapter

Ltix needs your application to look up registrations and deployments, to record used nonces (one-time values that prevent replayed launches), and to sign what your tool sends to platforms. You provide these through the `Ltix.StorageAdapter` behaviour.

```elixir
# lib/my_app/lti/storage.ex
defmodule MyApp.Lti.Storage do
  @behaviour Ltix.StorageAdapter

  alias MyApp.Lti

  @impl true
  def get_registration(issuer, client_id, _opts), do: Lti.get_registration(issuer, client_id)

  @impl true
  def get_deployment(registration, deployment_id, _opts), do: Lti.get_deployment(registration, deployment_id)

  @impl true
  def validate_nonce(nonce, _registration, expires_at, _opts), do: Lti.validate_nonce(nonce, expires_at)

  @impl true
  def key_id(registration, _opts), do: Lti.signing_key_id(registration)

  @impl true
  def sign(_registration, key_id, message, _opts), do: Lti.sign(key_id, message)
end
```

The storage adapter is a thin wrapper that delegates to your context module, where the actual queries are.

`key_id/2` and `sign/4` are optional. Ltix calls them to sign access token requests for Advantage services and Deep Linking responses, so a tool that only handles launches can leave them out.

> #### Nil client ID {: .tip}
>
> Older versions of some platforms may omit `client_id` from the login request, in which case `get_registration/3` receives `nil` as the second argument. The issuer-only clause above handles that. See [Storage Adapters](storage-adapters.md) for details.

For more on nonce expiry, custom structs, and per-call adapter overrides, see [Storage Adapters](storage-adapters.md).

## Configuration

Set which storage adapter Ltix uses.

```elixir
# config/config.exs
config :ltix,
  storage_adapter: MyApp.Lti.Storage
```

To override settings for a single call, pass options to the call. `Ltix.handle_login/3` takes `:storage_adapter`, `:storage_adapter_options`, and `:plugins`. `Ltix.handle_callback/3` takes `:storage_adapter`, `:storage_adapter_options`, `:allow_anonymous`, `:max_token_age`, `:local_network_access`, `:req_options`, `:key_set`, `:clock_skew`, and `:plugins`. See `Ltix.handle_login/3` and `Ltix.handle_callback/3` for what each option does.

## Registering a platform

Before your tool can accept launches, you need to exchange configuration with the platform. The 1EdTech specs leave this as an out-of-band process. The platform gives you its URLs and a client ID, and you give it your tool's launch URL and public key endpoint. [LTI Dynamic Registration](https://www.imsglobal.org/spec/lti-dr/v1p0) automates this exchange, but Ltix does not currently support it.

How you handle new registrations in your application is entirely up to you. Some tools render a registration page when a launch arrives from an unrecognized issuer/client_id pair. Others have an administrator UI. For this guide, we'll seed the data through IEx.

### Generate a signing key

Your tool needs at least one RSA signing key to get started. Open IEx and generate one.

```
$ iex -S mix

iex> alias MyApp.{Lti, Repo}

iex> jwk = Lti.create_jwk!()
```

For key rotation in production, see [JWK Management](jwk-management.md).

### Add a registration

Each platform you connect to needs a registration and at least one deployment. Construct an `Ltix.Registration` before persisting to validate that all the fields are correct and the launch will work.

```
iex> attrs = %{
...>   issuer: "https://canvas.example.edu",
...>   client_id: "10000000000042",
...>   auth_endpoint: "https://canvas.example.edu/api/lti/authorize_redirect",
...>   jwks_uri: "https://canvas.example.edu/api/lti/security/jwks",
...>   token_endpoint: "https://canvas.example.edu/login/oauth2/token"
...> }

iex> {:ok, _} = Ltix.Registration.new(attrs)
```

Once it passes validation, persist it.

```
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

The exact URLs and IDs depend on your platform. Check your platform's LTI developer documentation for where to find them.

## Phoenix setup

### Routes and pipeline

LTI launches differ from normal browser requests in two ways.

1. Platforms POST directly to your tool, so CSRF protection must be disabled on LTI routes.
2. Launches typically happen inside an iframe on the platform, so session cookies need `SameSite=None`, `Secure`, and `Partitioned` to work in the third-party context.

### Iframe strategy

Most LTI tools render inside the platform's iframe. If that's your plan, configure `SameSite=None` and `Partitioned` on your session cookie in the endpoint so it applies to all routes.

```elixir
# lib/my_app_web/endpoint.ex

# Change your existing Plug.Session to:
plug Plug.Session,
  store: :cookie,
  key: "_my_app_key",
  signing_salt: "your-salt",
  same_site: "None",
  secure: true,
  extra: "Partitioned"
```

This is the simplest approach. Your entire application works in the iframe with a single session cookie.

`Partitioned` gives the cookie a separate jar for each platform site that embeds your tool. Browsers that block third-party cookies still accept a partitioned one, so the session works inside the iframe in current versions of Chrome, Firefox, and Safari.

> #### Iframe sessions {: .warning}
>
> Without `same_site: "None"`, the browser silently drops the session cookie inside the iframe and your state check fails. This is the most common source of "launch just silently fails" issues.
>
> `SameSite=None` requires `secure: true`, which means HTTPS. You'll need HTTPS in development too (for example, with `mix phx.gen.cert`). Also set the endpoint's `:url` to the HTTPS URL, because the controller builds the launch URL from it.
>
> A partitioned cookie is only sent inside that platform's iframe. If your tool opens itself in a new tab after the launch, the tab starts without the session.

Three other approaches exist if rendering everything in an iframe doesn't fit your application.

- **New tab launches** - set `target` to `_blank` in the platform's tool configuration. The launch opens a new browser tab, where browsers that block third-party cookies still accept yours. The platform still sends the launch as a cross-site POST, and browsers leave `SameSite=Lax` cookies off those, so the cookie that holds the login state still needs `SameSite=None`. This works well for applications with complex navigation that doesn't fit an iframe.

- **Split rendering** - serve a lightweight iframe view for the launch, then link out to the full application in a new tab for deeper interaction. This lets you keep `SameSite=Lax` on most routes while only the LTI endpoints use `SameSite=None`.

- **Platform storage** - keep the login state in the platform's window, for browsers that block your cookie during the launch. See [Keeping Login State in Platform Storage](cookbooks/platform-storage.md).

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

    get "/login", LtiController, :login
    post "/login", LtiController, :login
    post "/launch", LtiController, :launch
  end

  # Platforms fetch your key set as JSON, so it needs no browser pipeline.
  scope "/lti", MyAppWeb do
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

Note two things about these pipelines.

- `protect_from_forgery` is omitted in the `:lti_launch` pipeline because platforms POST directly to your tool. The LTI specification provides for CSRF protection through the `state` and `nonce` parameters, which Ltix validates for you. Past the launch, we recommend enabling Phoenix's CSRF protection. This is done in the `:lti` pipeline in the example above, but you can organize your routes and pipelines however it makes sense for your application.
- `put_secure_browser_headers` overrides the default CSP to set `frame-ancestors 'self' https:`, allowing any HTTPS origin to embed the tool. Phoenix defaults to `frame-ancestors 'self'`, which blocks iframe embedding. If your tool has each platform's origin, you could restrict `frame-ancestors` per tenant after launch, but the login endpoint (and registration endpoint, if you implement dynamic registration) must remain open. Whether the extra complexity is worth it depends on your threat model.

### Controller

```elixir
# lib/my_app_web/controllers/lti_controller.ex
defmodule MyAppWeb.LtiController do
  use MyAppWeb, :controller

  alias MyApp.Lti

  require Logger

  def login(conn, params) do
    launch_url = url(conn, ~p"/lti/launch")

    case Ltix.handle_login(params, launch_url) do
      {:ok, %{redirect_uri: redirect_uri, state: state}} ->
        conn
        |> put_session(:lti_state, state)
        |> redirect(external: redirect_uri)

      {:error, error} ->
        launch_failed(conn, error)
    end
  end

  def launch(conn, params) do
    state = get_session(conn, :lti_state)

    case Ltix.handle_callback(params, state) do
      {:ok, launch} ->
        user = Lti.create_user!(launch)
        course = Lti.create_course!(launch)

        conn
        |> delete_session(:lti_state)
        |> put_session(:user_id, user.id)
        |> render(:launch, launch: launch, user: user, course: course)

      {:error, error} ->
        launch_failed(conn, error)
    end
  end

  def jwks(conn, _params) do
    json(conn, Ltix.JWK.to_jwks(Lti.list_public_jwks()))
  end

  # Error messages can include URLs and claim values, so they go to the
  # log, and the user sees a general message.
  defp launch_failed(conn, error) do
    Logger.warning("LTI launch failed: #{Exception.message(error)}")

    conn
    |> put_status(Ltix.Errors.status_code(error))
    |> render(:error, message: "The launch could not be completed.")
  end
end
```

The view module and templates follow.

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
<p :if={@course}>Course: {@course.title}</p>
<p :if={Ltix.Role.instructor?(@launch.claims.roles)}>You're an instructor in this course.</p>
```

```heex
<%!-- lib/my_app_web/controllers/lti_html/error.html.heex --%>
<h1>Launch failed</h1>
<p>{@message}</p>
```

The create-on-launch pattern shown here is common. It extracts the user and course from the launch data, persists them, and sets up a session.

This particular setup aligns with the platform-centric approach described in the [Best Practices for LTI Assessment Tools](https://standards.1edtech.org/lti/guides/assessment/assessment-guide#account-binding). If user accounts in your tool are separate from platform accounts (such as in a standalone SaaS product), you might instead use a join table to link platform users to your internal accounts. Use whatever account binding strategy works best for your application.

For structured error matching, such as showing different messages for security errors and invalid configuration, see [Error Handling](error-handling.md).

## Public key endpoint

The `jwks` action in the controller above serves your tool's public keys as a key set. When you register your tool with a platform, give it this URL (for example, `https://yourtool.com/lti/jwks`). The platform fetches your public keys from here to verify the access token requests your tool signs for Advantage service calls, such as grades and rosters, and its Deep Linking responses.

The endpoint serves the public keys stored with each signing key, so it never reads a private key. Include multiple keys during rotation so platforms can verify with either the current or previous key. See [JWK Management](jwk-management.md) for rotation strategies.

## Next steps

You now have a working LTI launch. Here's what to do next before going to production.

- **Nonce cleanup** - the nonces table grows with every launch. Add a periodic job, for example with Oban, that deletes nonces past their `expires_at`. See [Storage Adapters](storage-adapters.md) for an example.

- **Key rotation** - signing keys should be rotated periodically. Serve both the old and new key from your public key endpoint during the transition. See [JWK Management](jwk-management.md).

- **Hardening** - CSRF protection after the launch, authorization from roles, redirect checks, and key handling. See [Hardening Your Tool](hardening.md).

- **Error handling** - the controller above shows one general message. Match on error classes to show users more helpful messages and choose log levels. See [Error Handling](error-handling.md).

- **Role-based authorization** - decide what instructors, learners, and teaching assistants can do in your tool. See [Working with Roles](working-with-roles.md).

- **Grades and roster** - send scores back to the platform's gradebook and fetch class lists. See [Advantage Services](advantage-services.md).

- **Tests** - Ltix provides test helpers that simulate the full launch flow without calling a real platform. See [Testing LTI Launches](cookbooks/testing-lti-launches.md).
