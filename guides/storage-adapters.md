# Storage Adapters

Ltix doesn't assume your database, ORM, or persistence strategy. Your
application owns all storage and provides lookups through the
`Ltix.StorageAdapter` behaviour. This guide covers what each callback
does, how to build a production-ready implementation with Ecto, and
common pitfalls.

## Callback overview

| Callback | When it's called | What it does |
|---|---|---|
| `get_registration/2` | Login initiation and launch validation | Look up a platform by issuer and optional client_id |
| `get_deployment/2` | Launch validation | Look up a deployment by registration and deployment_id |
| `store_nonce/2` | Login initiation | Persist a nonce for later verification |
| `validate_nonce/2` | Launch validation | Verify a nonce was issued by us, then consume it |

When storage fails, return `{:error, reason}` from any callback. The login or launch then returns `{:error, %Ltix.Errors.Unknown.StorageError{}}`, whose `result` is what the callback returned. A `reason` that is already an Ltix error is returned unchanged. Any other unexpected return value is also reported as a `StorageError`.

## Registration lookups

```elixir
@callback get_registration(issuer :: String.t(), client_id :: String.t() | nil) ::
            {:ok, Registerable.t()} | {:error, :not_found | term()}
```

Return any struct that implements `Ltix.Registerable`. The library
extracts the `Ltix.Registration` it needs via the protocol, and
your original struct is preserved in the `Ltix.LaunchContext` — so
you can access your own fields (database IDs, tenant info, etc.)
after a successful launch without an extra query.

Ltix calls `get_registration/2` during login initiation with the login
request's issuer and client_id, and again during launch validation
with the ID Token's issuer and audience.
The `client_id` may be `nil` — some platforms don't include it in the
login initiation request. Your adapter must handle both cases:

```elixir
def get_registration(issuer, nil) do
  case Repo.all(from r in PlatformRegistration, where: r.issuer == ^issuer) do
    [record] -> {:ok, record}
    _none_or_several -> {:error, :not_found}
  end
end

def get_registration(issuer, client_id) do
  case Repo.get_by(PlatformRegistration, issuer: issuer, client_id: client_id) do
    nil -> {:error, :not_found}
    record -> {:ok, record}
  end
end
```

Your Ecto schema implements `Ltix.Registerable` to map its fields:

```elixir
defimpl Ltix.Registerable, for: MyApp.Lti.PlatformRegistration do
  def to_registration(record) do
    Ltix.Registration.new(%{
      issuer: record.issuer,
      client_id: record.client_id,
      auth_endpoint: record.auth_endpoint,
      jwks_uri: record.jwks_uri,
      token_endpoint: record.token_endpoint,
      tool_jwk: record.tool_jwk
    })
  end
end
```

> #### Ambiguous issuer-only lookups {: .warning}
>
> If you support multiple registrations from the same issuer (different
> client_ids), an issuer-only lookup is ambiguous. You can either return
> the first match or return `{:error, :not_found}` and require the
> platform to include `client_id`, as the example above does.

## Deployment lookups

```elixir
@callback get_deployment(registration :: Registration.t(), deployment_id :: String.t()) ::
            {:ok, Deployable.t()} | {:error, :not_found | term()}
```

Return any struct that implements `Ltix.Deployable`. Like registrations,
your original struct is preserved in the `Ltix.LaunchContext`.

The `registration` parameter is the resolved `Ltix.Registration` (not
your custom struct). The `deployment_id` is case-sensitive and assigned
by the platform:

```elixir
def get_deployment(%Ltix.Registration{issuer: issuer, client_id: client_id}, deployment_id) do
  query =
    from d in PlatformDeployment,
      join: r in PlatformRegistration,
      on: d.registration_id == r.id,
      where: r.issuer == ^issuer and r.client_id == ^client_id,
      where: d.deployment_id == ^deployment_id

  case Repo.one(query) do
    nil -> {:error, :not_found}
    record -> {:ok, record}
  end
end
```

```elixir
defimpl Ltix.Deployable, for: MyApp.Lti.PlatformDeployment do
  def to_deployment(record) do
    Ltix.Deployment.new(record.deployment_id)
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
  changeset = LtiNonce.changeset(%LtiNonce{}, %{nonce: nonce, issuer: issuer})

  case Repo.insert(changeset) do
    {:ok, _nonce} -> :ok
    {:error, changeset} -> {:error, changeset}
  end
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
    case Repo.all(from r in PlatformRegistration, where: r.issuer == ^issuer) do
      [record] -> {:ok, record}
      _none_or_several -> {:error, :not_found}
    end
  end

  def get_registration(issuer, client_id) do
    case Repo.get_by(PlatformRegistration, issuer: issuer, client_id: client_id) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
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
      record -> {:ok, record}
    end
  end

  @impl true
  def store_nonce(nonce, %Ltix.Registration{issuer: issuer}) do
    case Repo.insert(%LtiNonce{nonce: nonce, issuer: issuer}) do
      {:ok, _nonce} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
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
end
```

The protocol implementations live on your Ecto schemas:

```elixir
defimpl Ltix.Registerable, for: MyApp.Lti.PlatformRegistration do
  def to_registration(record) do
    Ltix.Registration.new(%{
      issuer: record.issuer,
      client_id: record.client_id,
      auth_endpoint: record.auth_endpoint,
      jwks_uri: record.jwks_uri,
      token_endpoint: record.token_endpoint,
      tool_jwk: record.tool_jwk
    })
  end
end

defimpl Ltix.Deployable, for: MyApp.Lti.PlatformDeployment do
  def to_deployment(record) do
    Ltix.Deployment.new(record.deployment_id)
  end
end
```

After a successful launch, `context.registration` is your
`%PlatformRegistration{}` and `context.deployment` is your
`%PlatformDeployment{}` — access your own fields directly:

```elixir
context.registration.id          #=> 42
context.registration.tenant_id   #=> 7
context.deployment.id            #=> 99
```

## Testing your adapter

Use `Ltix.Test.assert_storage_adapter!/2` to check registration and deployment lookups, returned records, and nonce replay prevention. It returns `:ok` or raises `ExUnit.AssertionError` with the failing contract check.

Pass factories that persist the supplied registration and deployment details and return your application structs. Run against isolated test storage and clean up through your normal test setup.

```elixir
test "storage adapter satisfies the contract" do
  parent = self()

  assert :ok = Ltix.Test.assert_storage_adapter!(MyApp.LtiStorage,
    registration: fn registration ->
      MyApp.Lti.create_registration!(Map.from_struct(registration))
    end,
    deployment: fn deployment, registration ->
      MyApp.Lti.create_deployment!(%{
        deployment_id: deployment.deployment_id,
        registration_id: registration.id
      })
    end,
    prepare_process: fn ->
      Ecto.Adapters.SQL.Sandbox.allow(MyApp.Repo, parent, self())
    end
  )
end
```

Preserve the lookup identifiers supplied to your factories. If lookups preload associations or change metadata, pass `registration_identity: & &1.id` and `deployment_identity: & &1.id`, or projections suited to your records.

Omit `:prepare_process` when your adapter needs neither database sandbox access nor process-local setup. For adapters that [auto-create deployments](auto-create-deployments.md), pass `auto_create_deployments: true` and return distinct storage identities to check deployment ownership. See `Ltix.Test.assert_storage_adapter!/2` for all options.

## Per-call override

You can bypass the configured adapter for a specific call by passing
`:storage_adapter` in opts:

```elixir
Ltix.handle_login(params, launch_url, storage_adapter: MyApp.TestStorage)
```

This is useful in tests or when different routes use different storage
backends.
