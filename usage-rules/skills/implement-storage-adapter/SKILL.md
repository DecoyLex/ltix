---
name: implement-storage-adapter
description: "Use this skill when implementing an Ltix.StorageAdapter for an LTI 1.3 tool application. Guides you through the four required callbacks with collaboration checkpoints for schema design and storage strategy decisions."
---

# Implement a Storage Adapter

This skill walks through implementing the `Ltix.StorageAdapter` behaviour, which is the
primary integration point between Ltix and your application's database.

## Overview

The storage adapter has 4 callbacks:

| Callback | Called During | Returns |
|---|---|---|
| `get_registration/2` | Login initiation | `{:ok, %Registration{}} \| {:error, :not_found}` |
| `get_deployment/2` | Callback validation | `{:ok, %Deployment{}} \| {:error, :not_found}` |
| `store_nonce/2` | Login initiation | `:ok` |
| `validate_nonce/2` | Callback validation | `:ok \| {:error, :nonce_already_used \| :nonce_not_found}` |

## Before You Start — Ask the User

These decisions are app-specific. Clarify them before writing code:

1. **Storage layer**: Ecto with Postgres? Ecto with SQLite? Something else entirely
   (Mnesia, Redis, ETS)? The patterns below assume Ecto + Postgres but the behaviour
   is storage-agnostic. You can also check what the project is already using.

2. **Existing schema**: Does the app already have tables for LMS platforms, courses, or
   users? The LTI tables may need to relate to existing models.

3. **Context module**: Phoenix apps typically group related functionality under a context
   module. Suggest `MyApp.Lti` as the context (with the storage adapter at
   `MyApp.Lti.StorageAdapter` and schemas at `MyApp.Lti.Registration`, etc.). Ask
   the user if this fits their project structure, or if they'd prefer a different
   grouping.

4. **Table/module naming**: What naming convention does the project use? (e.g.,
   `lti_registrations` vs `platforms`, `MyApp.Lti.Registration` vs `MyApp.LtiStorage`)

5. **JWK strategy**: One tool key pair shared across all registrations, or one per
   registration? Per-registration allows independent rotation but adds complexity.
   Ask the user which approach they prefer.

6. **Deployment policy**: Should new deployments be auto-created on first launch (upsert),
   or require manual registration? Auto-create is simpler but the user may want an admin
   approval flow.

7. **Nonce cleanup**: Nonces accumulate when launches fail before reaching callback. How
   should they be cleaned up — periodic Oban job, a database trigger, manual pruning?

## Step 1: Database Schema

Present this to the user for review — table names, column types, and indices depend on
their answers above.

Example Ecto migration (Postgres):

```elixir
defmodule MyApp.Repo.Migrations.CreateLtiTables do
  use Ecto.Migration

  def change do
    create table(:lti_registrations) do
      add :issuer, :string, null: false
      add :client_id, :string, null: false
      add :auth_endpoint, :string, null: false
      add :jwks_uri, :string, null: false
      add :token_endpoint, :string, null: false
      add :tool_jwk, :map, null: false
      timestamps()
    end

    create unique_index(:lti_registrations, [:issuer, :client_id])

    create table(:lti_deployments) do
      add :deployment_id, :string, null: false
      add :registration_id, references(:lti_registrations), null: false
      timestamps()
    end

    create unique_index(:lti_deployments, [:registration_id, :deployment_id])

    create table(:lti_nonces) do
      add :nonce, :string, null: false
      add :issuer, :string, null: false
      timestamps(updated_at: false)
    end

    create unique_index(:lti_nonces, [:nonce, :issuer])
  end
end
```

Adapt based on the user's schema decisions — they may want additional columns (e.g.,
`name` on registrations, foreign keys to their own `courses` or `organizations` tables).

## Step 2: Implement the Behaviour

```elixir
defmodule MyApp.Lti.StorageAdapter do
  @behaviour Ltix.StorageAdapter

  alias Ltix.{Deployment, Registration}
  alias MyApp.Repo

  import Ecto.Query

  @impl true
  def get_registration(issuer, client_id) do
    # client_id can be nil — handle both cases
    query =
      if client_id do
        from r in "lti_registrations",
          where: r.issuer == ^issuer and r.client_id == ^client_id
      else
        from r in "lti_registrations",
          where: r.issuer == ^issuer
      end

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      record ->
        Registration.new(%{
          issuer: record.issuer,
          client_id: record.client_id,
          auth_endpoint: record.auth_endpoint,
          jwks_uri: record.jwks_uri,
          token_endpoint: record.token_endpoint,
          tool_jwk: record.tool_jwk
        })
    end
  end

  @impl true
  def get_deployment(registration, deployment_id) do
    query =
      from d in "lti_deployments",
        join: r in "lti_registrations",
          on: d.registration_id == r.id,
        where: r.issuer == ^registration.issuer
          and r.client_id == ^registration.client_id
          and d.deployment_id == ^deployment_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      _record -> Deployment.new(deployment_id)
    end
  end

  @impl true
  def store_nonce(nonce, registration) do
    Repo.insert_all("lti_nonces", [
      %{nonce: nonce, issuer: registration.issuer, inserted_at: DateTime.utc_now()}
    ])

    :ok
  end

  @impl true
  def validate_nonce(nonce, registration) do
    # Atomic delete-on-validate: if two requests race with the same nonce,
    # only one will delete a row and succeed.
    case Repo.delete_all(
           from n in "lti_nonces",
             where: n.nonce == ^nonce and n.issuer == ^registration.issuer
         ) do
      {1, _} -> :ok
      {0, _} -> {:error, :nonce_not_found}
    end
  end
end
```

## Step 3: Configure

```elixir
# config/config.exs
config :ltix, storage_adapter: MyApp.Lti.StorageAdapter

# config/test.exs — use the in-memory adapter for tests
config :ltix, storage_adapter: Ltix.Test.StorageAdapter
```

## Technical Constraints

These are non-negotiable requirements from the LTI spec and library:

- **`client_id` can be nil** in `get_registration/2` when the platform omits it from the
  login request. The implementation must query by issuer alone in that case.

- **Nonce validation must be atomic.** The `DELETE ... WHERE` pattern ensures that concurrent
  requests with the same nonce can't both succeed. A two-step "read then delete" approach
  has a race condition.

- **`tool_jwk` is private key material.** Store the full JWK map in a JSON/map column.
  This is the tool's signing key used for OAuth client assertions and deep linking responses.
  Treat it with the same care as any secret.

- **`deployment_id` is case-sensitive** and at most 255 ASCII characters.

## Optional Patterns (Discuss with User First)

**Auto-creating deployments** — upsert in `get_deployment/2`:

```elixir
Repo.insert(%LtiDeployment{registration_id: reg_id, deployment_id: deployment_id},
  on_conflict: :nothing,
  conflict_target: [:registration_id, :deployment_id]
)
```

This is safe because `get_deployment/2` is called after JWT signature verification — the
`deployment_id` is already trusted. But the user may prefer a manual approval step.

**Nonce cleanup** — periodic job to remove stale nonces:

```elixir
from(n in "lti_nonces", where: n.inserted_at < ago(5, "minute"))
|> Repo.delete_all()
```

Ask the user how they want to schedule this (Oban, Quantum, manual GenServer, etc.).
