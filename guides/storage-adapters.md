# Storage Adapters

Ltix doesn't assume your database, ORM, or persistence strategy. Your
application owns all storage and provides lookups through the
`Ltix.StorageAdapter` behaviour. This guide covers what each callback
does, how to build a production-ready implementation with Ecto, and
common pitfalls.

## Callback overview

| Callback | When it's called | What it does |
|---|---|---|
| `get_registration/2` | Login initiation | Look up a platform by issuer and optional client_id |
| `get_deployment/2` | Launch validation | Look up a deployment by registration and deployment_id |
| `store_nonce/2` | Login initiation | Persist a nonce for later verification |
| `validate_nonce/2` | Launch validation | Verify a nonce was issued by us, then consume it |

## Registration lookups

```elixir
@callback get_registration(issuer :: String.t(), client_id :: String.t() | nil) ::
            {:ok, Registration.t()} | {:error, :not_found}
```

The `client_id` may be `nil` — some platforms don't include it in the
login initiation request. Your adapter must handle both cases:

```elixir
def get_registration(issuer, nil) do
  case Repo.get_by(PlatformRegistration, issuer: issuer) do
    nil -> {:error, :not_found}
    record -> {:ok, to_ltix_registration(record)}
  end
end

def get_registration(issuer, client_id) do
  case Repo.get_by(PlatformRegistration, issuer: issuer, client_id: client_id) do
    nil -> {:error, :not_found}
    record -> {:ok, to_ltix_registration(record)}
  end
end

defp to_ltix_registration(record) do
  %Ltix.Registration{
    issuer: record.issuer,
    client_id: record.client_id,
    auth_endpoint: record.auth_endpoint,
    jwks_uri: record.jwks_uri,
    token_endpoint: record.token_endpoint
  }
end
```

> #### Ambiguous issuer-only lookups {: .warning}
>
> If you support multiple registrations from the same issuer (different
> client_ids), an issuer-only lookup is ambiguous. You can either return
> the first match or return `{:error, :not_found}` and require the
> platform to include `client_id`.

## Deployment lookups

```elixir
@callback get_deployment(registration :: Registration.t(), deployment_id :: String.t()) ::
            {:ok, Deployment.t()} | {:error, :not_found}
```

A deployment is scoped to a registration. The `deployment_id` is
case-sensitive and assigned by the platform:

```elixir
def get_deployment(%Ltix.Registration{} = reg, deployment_id) do
  case Repo.get_by(PlatformDeployment,
         registration_id: reg_id(reg),
         deployment_id: deployment_id
       ) do
    nil -> {:error, :not_found}
    record -> {:ok, %Ltix.Deployment{deployment_id: record.deployment_id}}
  end
end
```

## Nonce management

Nonces prevent replay attacks. The flow is:

1. During login, Ltix generates a random nonce and calls `store_nonce/2`
2. During launch validation, Ltix extracts the nonce from the JWT and
   calls `validate_nonce/2`
3. Your adapter must check the nonce exists and consume it atomically

### In-memory (development)

```elixir
use Agent

def start_link(_opts) do
  Agent.start_link(fn -> MapSet.new() end, name: __MODULE__)
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
```

### Ecto (production)

A nonce table with atomic consume-on-validate:

```elixir
# Migration
create table(:lti_nonces) do
  add :nonce, :string, null: false
  add :issuer, :string, null: false
  timestamps(updated_at: false)
end

create unique_index(:lti_nonces, [:nonce, :issuer])
```

```elixir
@impl true
def store_nonce(nonce, %Ltix.Registration{issuer: issuer}) do
  %LtiNonce{}
  |> LtiNonce.changeset(%{nonce: nonce, issuer: issuer})
  |> Repo.insert!()

  :ok
end

@impl true
def validate_nonce(nonce, %Ltix.Registration{issuer: issuer}) do
  case Repo.delete_all(
         from n in LtiNonce,
           where: n.nonce == ^nonce and n.issuer == ^issuer
       ) do
    {1, _} -> :ok
    {0, _} -> {:error, :nonce_not_found}
  end
end
```

The `DELETE ... WHERE` is atomic — if two requests race with the same
nonce, only one will delete a row and succeed.

> #### Nonce expiry {: .tip}
>
> Nonces accumulate if launches fail before reaching the callback.
> Add a periodic cleanup job that deletes nonces older than a few
> minutes. The `inserted_at` timestamp makes this straightforward:
>
> ```elixir
> from(n in LtiNonce, where: n.inserted_at < ago(5, "minute"))
> |> Repo.delete_all()
> ```

## Putting it together

A complete Ecto-backed adapter:

```elixir
defmodule MyApp.LtiStorage do
  @behaviour Ltix.StorageAdapter

  import Ecto.Query
  alias MyApp.Repo
  alias MyApp.Lti.{LtiNonce, PlatformDeployment, PlatformRegistration}

  @impl true
  def get_registration(issuer, nil) do
    case Repo.get_by(PlatformRegistration, issuer: issuer) do
      nil -> {:error, :not_found}
      record -> {:ok, to_registration(record)}
    end
  end

  def get_registration(issuer, client_id) do
    case Repo.get_by(PlatformRegistration, issuer: issuer, client_id: client_id) do
      nil -> {:error, :not_found}
      record -> {:ok, to_registration(record)}
    end
  end

  @impl true
  def get_deployment(%Ltix.Registration{issuer: issuer, client_id: client_id}, deployment_id) do
    query =
      from d in PlatformDeployment,
        join: r in PlatformRegistration,
        on: d.registration_id == r.id,
        where: r.issuer == ^issuer and r.client_id == ^client_id,
        where: d.deployment_id == ^deployment_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      record -> {:ok, %Ltix.Deployment{deployment_id: record.deployment_id}}
    end
  end

  @impl true
  def store_nonce(nonce, %Ltix.Registration{issuer: issuer}) do
    Repo.insert!(%LtiNonce{nonce: nonce, issuer: issuer})
    :ok
  end

  @impl true
  def validate_nonce(nonce, %Ltix.Registration{issuer: issuer}) do
    case Repo.delete_all(
           from n in LtiNonce,
             where: n.nonce == ^nonce and n.issuer == ^issuer
         ) do
      {1, _} -> :ok
      {0, _} -> {:error, :nonce_not_found}
    end
  end

  defp to_registration(record) do
    %Ltix.Registration{
      issuer: record.issuer,
      client_id: record.client_id,
      auth_endpoint: record.auth_endpoint,
      jwks_uri: record.jwks_uri,
      token_endpoint: record.token_endpoint
    }
  end
end
```

## Per-call override

You can bypass the configured adapter for a specific call by passing
`:storage_adapter` in opts:

```elixir
Ltix.handle_login(params, launch_url, storage_adapter: MyApp.TestStorage)
```

This is useful in tests or when different routes use different storage
backends.
