# Managing JWKs with Ecto

This recipe sets up database-backed JWK storage with a dedicated table,
a key set controller, and a key rotation function. If you haven't read
the [JWK Management](../jwk-management.md) guide yet, start there for
background on signing keys, key set endpoints, and rotation.

## Migration

A dedicated table keeps key management separate from registration logic and makes rotation straightforward. Each row has the key ID, the public key your key set endpoint serves, and the private key, encrypted.

```elixir
create table(:lti_keys) do
  add :kid, :string, null: false
  add :public_key_pem, :text, null: false
  add :private_key_pem, :binary, null: false
  add :active, :boolean, default: true
  timestamps()
end

create unique_index(:lti_keys, [:kid])

alter table(:platform_registrations) do
  add :key_id, references(:lti_keys), null: false
end
```

## Schema

The private key is encrypted at rest and left out of `inspect`. `MyApp.Encrypted.Binary` here is a [Cloak](https://cloak-ecto.hexdocs.pm) field type, set up in [Getting Started](../getting-started.md#set-up-key-encryption). Any encrypted field type works in its place.

```elixir
defmodule MyApp.Lti.LtiKey do
  use Ecto.Schema

  schema "lti_keys" do
    field :kid, :string
    field :public_key_pem, :string
    field :private_key_pem, MyApp.Encrypted.Binary, redact: true
    field :active, :boolean, default: true
    timestamps()
  end
end
```

## Creating registrations with keys

Generate a key when creating a registration.

```elixir
defmodule MyApp.Lti do
  def create_registration(attrs) do
    key = create_key!()

    %PlatformRegistration{}
    |> PlatformRegistration.changeset(Map.put(attrs, :key_id, key.id))
    |> Repo.insert()
  end

  def create_key! do
    jwk = Ltix.JWK.generate()

    # Ecto's debug log prints query parameters, and the key is one of them.
    Repo.insert!(
      %LtiKey{
        kid: jwk.kid,
        public_key_pem: jwk.public_key_pem,
        private_key_pem: jwk.private_key_pem
      },
      log: false
    )
  end
end
```

## Signing

Your storage adapter signs with the registration's key through the `key_id/2` and `sign/4` callbacks.

```elixir
@impl true
def key_id(%PlatformRegistration{key_id: key_id}, _opts) do
  {:ok, Repo.get!(LtiKey, key_id).kid}
end

@impl true
def sign(_registration, key_id, message, _opts) do
  case Repo.get_by(LtiKey, kid: key_id, active: true) do
    nil -> {:error, :unknown_key}
    key -> Ltix.JWK.sign(Ltix.JWK.new!(private_key_pem: key.private_key_pem, kid: key.kid), message)
  end
end
```

`sign/4` looks the key up by the ID `key_id/2` returned, so a request that starts before a rotation still signs with the key whose ID is in its JWT header.

## Key set controller

Serve the public key of every active key. The query selects only the public column, so the endpoint never reads a private key.

```elixir
defmodule MyAppWeb.JwksController do
  use MyAppWeb, :controller

  import Ecto.Query
  alias MyApp.Repo
  alias MyApp.Lti.LtiKey

  def index(conn, _params) do
    keys = Repo.all(from k in LtiKey, where: k.active == true, select: {k.kid, k.public_key_pem})
    jwks = Enum.map(keys, fn {kid, pem} -> Ltix.JWK.new!(public_key_pem: pem, kid: kid) end)

    json(conn, Ltix.JWK.to_jwks(jwks))
  end
end
```

```elixir
# router.ex
get "/.well-known/jwks.json", JwksController, :index
```

> #### Cache the key set response {: .tip}
>
> Platforms may fetch your key set endpoint frequently. Consider caching
> the response in ETS or with a cache header.

## Key rotation

Create a new key row, set it as the registration's key, and leave the
old key active so platforms can still verify during the overlap
period.

```elixir
def rotate_key(registration_id) do
  new_key = create_key!()

  Repo.get!(PlatformRegistration, registration_id)
  |> PlatformRegistration.changeset(%{key_id: new_key.id})
  |> Repo.update!()
end
```

The old key stays `active: true`, so the key set endpoint continues
serving it. After platforms have refreshed their cache (24-48 hours
is typical), mark it inactive.

```elixir
Repo.update!(LtiKey.changeset(old_key, %{active: false}))
```
