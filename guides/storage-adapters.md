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
| `validate_nonce/3` | Launch validation | Record a nonce as used, and reject one already used |
| `key_id/1` | Service authentication and deep linking responses | Return the ID of the key that signs for a registration |
| `sign/3` | Service authentication and deep linking responses | Sign a message with that key |

`key_id/1` and `sign/3` are optional. A tool that only handles launches doesn't need them.

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
      token_endpoint: record.token_endpoint
    })
  end
end
```

> #### Ambiguous issuer-only lookups {: .warning}
>
> If you support multiple registrations from the same issuer (different client_ids), an issuer-only lookup is ambiguous. A launch succeeds only for the registration the login found, so returning the first match fails launches for the others. Return `{:error, :not_found}` to require the platform to include `client_id`, as the example above does.

## Deployment lookups

```elixir
@callback get_deployment(registration :: Registration.t(), deployment_id :: String.t()) ::
            {:ok, Deployable.t()} | {:error, :not_found | term()}
```

Return any struct that implements `Ltix.Deployable`. Like registrations,
your original struct is preserved in the `Ltix.LaunchContext`.

The `registration` parameter is the struct your `get_registration/2` returned. The `deployment_id` is case-sensitive and assigned by the platform.

```elixir
def get_deployment(%PlatformRegistration{id: registration_id}, deployment_id) do
  case Repo.get_by(PlatformDeployment,
         registration_id: registration_id,
         deployment_id: deployment_id
       ) do
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

Nonces prevent replayed launches. After Ltix verifies an ID token, it calls `validate_nonce/3` with the token's nonce and the time the token expires. Record the nonce as used and return `:ok`, or return `{:error, :nonce_already_used}` if it's already recorded. Logins don't write anything to storage.

Recording has to be atomic, so only one of two launches with the same nonce succeeds. Keep each record until `expires_at`, then delete it.

### In-memory (development)

```elixir
use Agent

def start_link(_opts) do
  Agent.start_link(fn -> MapSet.new() end, name: __MODULE__)
end

@impl true
def validate_nonce(nonce, _registration, _expires_at) do
  Agent.get_and_update(__MODULE__, fn used ->
    if MapSet.member?(used, nonce),
      do: {{:error, :nonce_already_used}, used},
      else: {:ok, MapSet.put(used, nonce)}
  end)
end
```

### Ecto (production)

A nonce table keyed by the nonce.

```elixir
# Migration
create table(:lti_nonces, primary_key: false) do
  add :nonce, :string, primary_key: true
  add :expires_at, :utc_datetime, null: false
end
```

```elixir
@impl true
def validate_nonce(nonce, _registration, expires_at) do
  case Repo.insert_all(LtiNonce, [%{nonce: nonce, expires_at: expires_at}], on_conflict: :nothing) do
    {1, _} -> :ok
    {0, _} -> {:error, :nonce_already_used}
  end
end
```

The insert is atomic. If two requests race with the same nonce, only one of them inserts a row.

> #### Nonce expiry {: .tip}
>
> Add a periodic cleanup job that deletes nonces past their `expires_at`.
>
> ```elixir
> Repo.delete_all(from n in LtiNonce, where: n.expires_at < ^DateTime.utc_now())
> ```

## Signing

Ltix signs two things for your tool, the token requests for Advantage services and deep linking responses. It builds each JWT and asks your adapter for the signature, so your private key stays wherever you keep it.

Both callbacks receive the registration struct you gave Ltix, either from `get_registration/2` during a launch or as an argument to a function like `Ltix.OAuth.authenticate/2`. `key_id/1` returns the ID of the key that signs for it. Platforms use that ID to find the public key in your [key set](jwk-management.md#serving-a-jwks-endpoint). `sign/3` gets the same ID back with the message to sign.

For keys stored in your database, `Ltix.JWK.sign/2` produces the signature.

```elixir
@impl true
def key_id(%PlatformRegistration{signing_key_id: signing_key_id}) do
  {:ok, Repo.get!(SigningKey, signing_key_id).kid}
end

@impl true
def sign(_registration, key_id, message) do
  key = Repo.get_by!(SigningKey, kid: key_id)
  Ltix.JWK.sign(Ltix.JWK.new!(private_key_pem: key.private_key_pem, kid: key.kid), message)
end
```

For a key held in a key management service, call the service from `sign/3` and return `{:ok, signature}` with its RS256 (RSASSA-PKCS1-v1_5 with SHA-256) signature of the message.

Calling a service or building a deep linking response with an adapter that lacks these callbacks returns `Ltix.Errors.Unknown.StorageError`.

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
  def get_deployment(%PlatformRegistration{id: registration_id}, deployment_id) do
    case Repo.get_by(PlatformDeployment,
           registration_id: registration_id,
           deployment_id: deployment_id
         ) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  @impl true
  def validate_nonce(nonce, _registration, expires_at) do
    case Repo.insert_all(LtiNonce, [%{nonce: nonce, expires_at: expires_at}], on_conflict: :nothing) do
      {1, _} -> :ok
      {0, _} -> {:error, :nonce_already_used}
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
      token_endpoint: record.token_endpoint
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
