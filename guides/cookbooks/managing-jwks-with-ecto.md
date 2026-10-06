# Managing JWKs with Ecto

This recipe sets up database-backed JWK storage with a dedicated table,
a JWKS controller, and a key rotation function. If you haven't read
the [JWK Management](../jwk-management.md) guide yet, start there for
background on key pairs, JWKS endpoints, and rotation.

## Migration

A dedicated table keeps key management separate from registration
logic and makes rotation straightforward. Since `Ltix.JWK` stores the
private key as a PEM string and the kid as a plain string, you only
need text columns:

```elixir
create table(:lti_keys) do
  add :private_key_pem, :text, null: false
  add :kid, :string, null: false
  add :active, :boolean, default: true
  timestamps()
end

alter table(:platform_registrations) do
  add :key_id, references(:lti_keys), null: false
end
```

> #### Encrypt private keys at rest {: .warning}
>
> The `private_key_pem` column holds secret key material. Use
> [Cloak](https://hexdocs.pm/cloak_ecto) or your database's native
> encryption to encrypt it at rest.

## Creating registrations with keys

Generate a key when creating a registration:

```elixir
defmodule MyApp.Lti do
  def create_registration(attrs) do
    jwk = Ltix.JWK.generate()

    key =
      Repo.insert!(%LtiKey{
        private_key_pem: jwk.private_key_pem,
        kid: jwk.kid
      })

    %PlatformRegistration{}
    |> PlatformRegistration.changeset(Map.put(attrs, :key_id, key.id))
    |> Repo.insert()
  end
end
```

No serialization functions needed — PEM strings and kids are stored
directly.

## Signing

Your storage adapter signs with the registration's key through the `key_id/1` and `sign/3` callbacks:

```elixir
@impl true
def key_id(%PlatformRegistration{key_id: key_id}) do
  {:ok, Repo.get!(LtiKey, key_id).kid}
end

@impl true
def sign(_registration, key_id, message) do
  case Repo.get_by(LtiKey, kid: key_id) do
    nil -> {:error, :unknown_key}
    key -> Ltix.JWK.sign(Ltix.JWK.new!(private_key_pem: key.private_key_pem, kid: key.kid), message)
  end
end
```

`sign/3` looks the key up by the ID `key_id/1` returned, so a request that starts before a rotation still signs with the key whose ID is in its JWT header.

## JWKS controller

Serve all active public keys. `to_jwks/1` derives public halves from
private keys automatically:

```elixir
defmodule MyAppWeb.JwksController do
  use MyAppWeb, :controller

  import Ecto.Query
  alias MyApp.Repo
  alias MyApp.Lti.LtiKey

  def index(conn, _params) do
    keys =
      from(k in LtiKey, where: k.active == true)
      |> Repo.all()
      |> Enum.map(fn key ->
        %Ltix.JWK{private_key_pem: key.private_key_pem, kid: key.kid}
      end)

    conn
    |> put_resp_content_type("application/json")
    |> json(Ltix.JWK.to_jwks(keys))
  end
end
```

```elixir
# router.ex
get "/.well-known/jwks.json", JwksController, :index
```

> #### Cache the JWKS response {: .tip}
>
> Platforms may fetch your JWKS endpoint frequently. Consider caching
> the response in ETS or with a cache header rather than querying the
> database on each request.

## Key rotation

Create a new key row, point the registration at it, and leave the
old key active so platforms can still verify during the overlap
period:

```elixir
def rotate_key(registration_id) do
  jwk = Ltix.JWK.generate()

  new_key =
    Repo.insert!(%LtiKey{
      private_key_pem: jwk.private_key_pem,
      kid: jwk.kid
    })

  Repo.get!(PlatformRegistration, registration_id)
  |> PlatformRegistration.changeset(%{key_id: new_key.id})
  |> Repo.update!()
end
```

The old key stays `active: true`, so the JWKS endpoint continues
serving it. After platforms have refreshed their cache (24-48 hours
is typical), mark it inactive:

```elixir
Repo.update!(LtiKey.changeset(old_key, %{active: false}))
```
