---
name: implement-storage-adapter
description: "Use this skill when implementing an Ltix.StorageAdapter for an LTI 1.3 tool application. Guides you through the three required callbacks with collaboration checkpoints for schema design and storage strategy decisions."
---

# Implement a Storage Adapter

This skill walks through implementing the `Ltix.StorageAdapter` behaviour, which is the
primary integration point between Ltix and your application's database.

## Overview

The storage adapter has 3 callbacks:

| Callback | Called During | Returns |
|---|---|---|
| `get_registration/2` | Login initiation and callback validation | `{:ok, Registerable.t()} \| {:error, :not_found \| term()}` |
| `get_deployment/2` | Callback validation | `{:ok, Deployable.t()} \| {:error, :not_found \| term()}` |
| `validate_nonce/3` | Callback validation, after the ID token is verified | `:ok \| {:error, :nonce_already_used \| term()}` |

Two more callbacks are optional. Implement them when the tool calls Advantage services
or builds deep linking responses:

| Callback | Called During | Returns |
|---|---|---|
| `key_id/1` | Service authentication and deep linking responses | `{:ok, String.t()} \| {:error, term()}` |
| `sign/3` | Service authentication and deep linking responses | `{:ok, binary()} \| {:error, term()}` |

Return `{:error, reason}` from any callback when storage fails. Ltix returns it as `Ltix.Errors.Unknown.StorageError`.

`get_registration/2` and `get_deployment/2` can return any struct that implements
the `Ltix.Registerable` or `Ltix.Deployable` protocol. This means you return your
own Ecto schemas directly and the library extracts what it needs via the protocol.
Your original struct is preserved in the `Ltix.LaunchContext` after a successful
launch, so you can access your own fields (database IDs, tenant info, etc.) without
an extra query.

## Before You Start — Survey the User

These decisions are app-specific. **Enter plan mode** (or use a tool that asks the user
questions) to gather answers before writing any code. Explore the codebase first to
pre-fill what you can infer (storage layer, naming conventions, existing schemas), then
ask about the rest:

1. **Storage layer**: Ecto with Postgres? Ecto with SQLite? Something else entirely
   (Mnesia, Redis, ETS)? The patterns below assume Ecto + Postgres but the behaviour
   is storage-agnostic. Check what the project is already using.

2. **Account binding model**: How does the tool think about users?
   - **Platform-centric**: users only access the tool through a single platform. The
     tool relies entirely on the platform's user identity. If the user is removed from
     the platform, they lose access to the tool. Simplest model — a `users` table keyed
     on `(lti_sub, registration_id)` with no separate login.
   - **Tool-centric**: users have their own tool account that exists independently of
     any platform. Platform identities are *bound* to the tool account (often on first
     launch). A single tool user may be linked to multiple platforms and may also have
     a direct login. Requires a join table between tool accounts and platform identities.
   - **Hybrid**: different roles get different treatment. For example, content creators
     get tool-centric accounts (they need to log in directly), while learners are
     platform-centric (they only arrive via LTI launch).

   This decision shapes whether you need a `users` table at all, what it looks like,
   and how the launch callback creates or resolves users. Ask the user which model
   fits their product.

3. **Existing schema**: Does the app already have tables for LMS platforms, courses, or
   users? The LTI tables may need to relate to existing models.

4. **Context module**: Phoenix apps typically group related functionality under a context
   module. Suggest `MyApp.Lti` as the context (with the storage adapter at
   `MyApp.Lti.StorageAdapter` and schemas at `MyApp.Lti.Registration`, etc.). Ask
   the user if this fits their project structure, or if they'd prefer a different
   grouping.

5. **Table/module naming**: What naming convention does the project use? (e.g.,
   `lti_registrations` vs `platforms`, `MyApp.Lti.Registration` vs `MyApp.LtiStorage`)

6. **JWK strategy**: One tool key pair shared across all registrations, or one per
   registration? Per-registration allows independent rotation but adds complexity.
   Either way, keys are stored as `private_key_pem` (text) and `kid` (string) columns,
   and reconstructed into `%Ltix.JWK{}` structs via `Ltix.JWK.new/1`. A key held in a
   key management service can sign from `sign/3` without ever being stored in the app.

7. **Deployment policy**: Should new deployments be auto-created on first launch (upsert),
   or require manual registration? Auto-create is simpler but the user may want an admin
   approval flow.

8. **Nonce cleanup**: Each launch records its nonce until the token expires. How should
   expired records be deleted — periodic Oban job, a database trigger, manual pruning?

## Step 1: Database Schema

Present this to the user for review — table names, column types, and indices depend on
their answers above.

Example Ecto migration (Postgres):

```elixir
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

    create table(:lti_nonces, primary_key: false) do
      add :nonce, :string, primary_key: true
      add :expires_at, :utc_datetime, null: false
    end
  end
end
```

Adapt based on the user's schema decisions — they may want additional columns (e.g.,
`name` on registrations, foreign keys to their own `courses` or `organizations` tables).

## Step 2: Ecto Schemas with Protocol Implementations

Each Ecto schema implements the corresponding Ltix protocol so the storage adapter can
return your structs directly. The library extracts the `Ltix.Registration` or
`Ltix.Deployment` it needs via the protocol.

### JWK Schema

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

### Registration Schema

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

The `defimpl Ltix.Registerable` block tells Ltix how to extract a validated
`Ltix.Registration` from your Ecto struct. The registration holds no key. Ltix asks the
storage adapter to sign through `key_id/1` and `sign/3`.

### Deployment Schema

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

### Nonce Schema

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

## Step 3: Context Module

The context module handles the actual database queries. The storage adapter delegates
to these functions.

```elixir
# lib/my_app/lti.ex
defmodule MyApp.Lti do
  alias MyApp.Lti.{Deployment, Jwk, Nonce, Registration}
  alias MyApp.Repo

  import Ecto.Query

  def list_active_jwks do
    Repo.all(from j in Jwk, where: j.active == true)
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

  # The ID of the key that signs for a registration. Platforms use it to find
  # the public key in the tool's key set.
  def signing_key_id(%Registration{jwk_id: jwk_id}) do
    {:ok, Repo.get!(Jwk, jwk_id).kid}
  end

  def sign(key_id, message) do
    case Repo.get_by(Jwk, kid: key_id) do
      nil -> {:error, :unknown_key}
      jwk -> Ltix.JWK.sign(Ltix.JWK.new!(private_key_pem: jwk.private_key_pem, kid: jwk.kid), message)
    end
  end

  def get_deployment(%Registration{id: registration_id}, deployment_id) do
    case Repo.get_by(Deployment, registration_id: registration_id, deployment_id: deployment_id) do
      nil -> {:error, :not_found}
      deployment -> {:ok, deployment}
    end
  end

  def validate_nonce(nonce, expires_at) do
    # Atomic insert: if two requests race with the same nonce, only one
    # inserts a row and succeeds.
    case Repo.insert_all(Nonce, [%{nonce: nonce, expires_at: expires_at}], on_conflict: :nothing) do
      {1, _} -> :ok
      {0, _} -> {:error, :nonce_already_used}
    end
  end
end
```

Note that `get_deployment/2` receives the struct `get_registration/2` returned, so it
pattern-matches on your Ecto schema. The nonce and signing callbacks receive it too.

## Step 4: Storage Adapter Module

The storage adapter itself is a thin wrapper that delegates to the context module:

```elixir
# lib/my_app/lti/storage_adapter.ex
defmodule MyApp.Lti.StorageAdapter do
  @behaviour Ltix.StorageAdapter

  alias MyApp.Lti

  @impl true
  def get_registration(issuer, client_id), do: Lti.get_registration(issuer, client_id)

  @impl true
  def get_deployment(registration, deployment_id), do: Lti.get_deployment(registration, deployment_id)

  @impl true
  def validate_nonce(nonce, _registration, expires_at), do: Lti.validate_nonce(nonce, expires_at)

  @impl true
  def key_id(registration), do: Lti.signing_key_id(registration)

  @impl true
  def sign(_registration, key_id, message), do: Lti.sign(key_id, message)
end
```

## Step 5: Configure

```elixir
# config/config.exs
config :ltix, storage_adapter: MyApp.Lti.StorageAdapter

# config/test.exs — use the in-memory adapter and Req.Test stubs for tests
config :ltix,
  storage_adapter: Ltix.Test.StorageAdapter,
  req_options: [plug: {Req.Test, :ltix}]
```

Start the in-memory adapter with your test platforms in each test that launches.

```elixir
setup do
  platform = Ltix.Test.setup_platform!()
  {:ok, pid} = Ltix.Test.StorageAdapter.start_link(platforms: [platform])
  Ltix.Test.StorageAdapter.set_pid(pid)

  %{platform: platform}
end
```

## Technical Constraints

These are non-negotiable requirements from the LTI spec and library:

- **`client_id` can be nil** in `get_registration/2` when the platform omits it from the
  login request. The implementation must query by issuer alone in that case.

- **Nonce recording must be atomic.** The `INSERT ... ON CONFLICT DO NOTHING` pattern ensures
  that concurrent requests with the same nonce can't both succeed. A two-step "read then
  insert" approach has a race condition.

- **The signing key is private key material.** Store `private_key_pem` (text) and `kid`
  (string) columns. `sign/3` reconstructs them into `%Ltix.JWK{}` via `Ltix.JWK.new/1` and
  signs with `Ltix.JWK.sign/2`. Treat them with the same care as any secret.

- **`sign/3` signs with the key `key_id/1` named.** Look the key up by the `key_id`
  argument, so a rotation between the two calls can't sign with a different key.

- **`deployment_id` is case-sensitive** and at most 255 ASCII characters.

- **`get_deployment/2`, `validate_nonce/3`, `key_id/1`, and `sign/3` receive your own
  registration struct**, the one `get_registration/2` returned or the one you passed to
  the function that needed a signature. `Ltix.OAuth.Client.registration` holds it too.

## Optional Patterns (Discuss with User First)

**Auto-creating deployments** — upsert in `get_deployment/2`:

```elixir
Repo.insert(%MyApp.Lti.Deployment{registration_id: reg_id, deployment_id: deployment_id},
  on_conflict: :nothing,
  conflict_target: [:registration_id, :deployment_id]
)
```

This is safe because `get_deployment/2` is called after JWT signature verification — the
`deployment_id` is already trusted. But the user may prefer a manual approval step.

**Nonce cleanup** — periodic job to remove expired nonces:

```elixir
Repo.delete_all(from n in MyApp.Lti.Nonce, where: n.expires_at < ^DateTime.utc_now())
```

Ask the user how they want to schedule this (Oban, Quantum, manual GenServer, etc.).

## Step 6: Test the Callbacks

Unit-test each storage adapter callback directly. These verify that your queries,
protocol implementations, and nonce handling work correctly:

```elixir
defmodule MyApp.Lti.StorageAdapterTest do
  use MyApp.DataCase

  alias MyApp.Lti.StorageAdapter

  setup do
    tool_jwk = Ltix.JWK.generate()

    jwk = Repo.insert!(%MyApp.Lti.Jwk{
      private_key_pem: tool_jwk.private_key_pem,
      kid: tool_jwk.kid
    })

    registration = Repo.insert!(%MyApp.Lti.Registration{
      issuer: "https://platform.example.com",
      client_id: "client-123",
      auth_endpoint: "https://platform.example.com/auth",
      jwks_uri: "https://platform.example.com/jwks",
      token_endpoint: "https://platform.example.com/token",
      jwk_id: jwk.id
    })

    deployment = Repo.insert!(%MyApp.Lti.Deployment{
      deployment_id: "deployment-001",
      registration_id: registration.id
    })

    %{jwk: jwk, registration: registration, deployment: deployment}
  end

  describe "get_registration/2" do
    test "finds by issuer and client_id", %{registration: registration} do
      assert {:ok, found} = StorageAdapter.get_registration(
        registration.issuer, registration.client_id
      )
      assert found.id == registration.id
    end

    test "finds by issuer alone when client_id is nil", %{registration: registration} do
      assert {:ok, found} = StorageAdapter.get_registration(registration.issuer, nil)
      assert found.id == registration.id
    end

    test "returns :not_found for unknown issuer" do
      assert {:error, :not_found} = StorageAdapter.get_registration(
        "https://unknown.example.com", "client-123"
      )
    end

    test "Registerable protocol produces a valid Ltix.Registration", %{registration: registration} do
      {:ok, found} = StorageAdapter.get_registration(
        registration.issuer, registration.client_id
      )
      {:ok, %Ltix.Registration{} = resolved} = Ltix.Registerable.to_registration(found)
      assert resolved.issuer == registration.issuer
    end
  end

  describe "signing" do
    test "signs with the registration's key", %{jwk: jwk, registration: registration} do
      assert {:ok, key_id} = StorageAdapter.key_id(registration)
      assert key_id == jwk.kid
      assert {:ok, signature} = StorageAdapter.sign(registration, key_id, "message")
      assert is_binary(signature)
    end
  end

  describe "get_deployment/2" do
    test "finds by registration and deployment_id", %{registration: registration, deployment: deployment} do
      assert {:ok, found_dep} =
               StorageAdapter.get_deployment(registration, deployment.deployment_id)

      assert found_dep.id == deployment.id
    end
  end

  describe "nonce lifecycle" do
    test "accepts a nonce once", %{registration: registration} do
      expires_at = DateTime.add(DateTime.utc_now(:second), 300)

      assert :ok = StorageAdapter.validate_nonce("test-nonce", registration, expires_at)

      assert {:error, :nonce_already_used} =
               StorageAdapter.validate_nonce("test-nonce", registration, expires_at)
    end
  end
end
```

For a full end-to-end test through your controller routes, see the
[Testing LTI Launches](https://hexdocs.pm/ltix/testing-lti-launches.md) cookbook.
