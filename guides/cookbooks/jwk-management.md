# Managing JWKs with Ecto

This recipe sets up database-backed JWK storage with a dedicated table,
a JWKS controller, and a key rotation function. If you haven't read
the [JWK Management](../jwk-management.md) guide yet, start there for
background on key pairs, JWKS endpoints, and rotation.

## Migration

A dedicated table keeps key management separate from registration
logic and makes rotation straightforward:

```elixir
create table(:lti_jwks) do
  add :private_jwk, :binary, null: false
  add :active, :boolean, default: true
  timestamps()
end

alter table(:platform_registrations) do
  add :jwk_id, references(:lti_jwks), null: false
end
```

> #### Encrypt private keys at rest {: .warning}
>
> The `private_jwk` column holds secret key material. Use
> [Cloak](https://hexdocs.pm/cloak_ecto) or your database's native
> encryption to encrypt it at rest.

## Creating registrations with keys

Generate a key pair when creating a registration, and store only the
private key:

```elixir
defmodule MyApp.Lti do
  def create_registration(attrs) do
    {private, _public} = Ltix.JWK.generate_key_pair()

    jwk =
      Repo.insert!(%LtiJwk{
        private_jwk: serialize(private)
      })

    %PlatformRegistration{}
    |> PlatformRegistration.changeset(Map.put(attrs, :jwk_id, jwk.id))
    |> Repo.insert()
  end

  defp serialize(jwk) do
    jwk |> JOSE.JWK.to_map() |> elem(1) |> Jason.encode!()
  end

  defp deserialize(json) do
    json |> Jason.decode!() |> JOSE.JWK.from_map()
  end
end
```

Your storage adapter preloads the key and deserializes it:

```elixir
defp to_registration(record) do
  %Ltix.Registration{
    issuer: record.issuer,
    client_id: record.client_id,
    auth_endpoint: record.auth_endpoint,
    jwks_uri: record.jwks_uri,
    token_endpoint: record.token_endpoint,
    tool_jwk: deserialize(record.jwk.private_jwk)
  }
end
```

## JWKS controller

Serve all active public keys. `to_jwks/1` derives public halves from
private keys automatically:

```elixir
defmodule MyAppWeb.JwksController do
  use MyAppWeb, :controller

  import Ecto.Query
  alias MyApp.Repo
  alias MyApp.Lti.LtiJwk

  def index(conn, _params) do
    keys =
      from(j in LtiJwk, where: j.active == true)
      |> Repo.all()
      |> Enum.map(fn jwk ->
        jwk.private_jwk |> Jason.decode!() |> JOSE.JWK.from_map()
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
  {new_private, _public} = Ltix.JWK.generate_key_pair()

  new_jwk =
    Repo.insert!(%LtiJwk{
      private_jwk: serialize(new_private)
    })

  Repo.get!(PlatformRegistration, registration_id)
  |> PlatformRegistration.changeset(%{jwk_id: new_jwk.id})
  |> Repo.update!()
end
```

The old key stays `active: true`, so the JWKS endpoint continues
serving it. After platforms have refreshed their cache (24-48 hours
is typical), mark it inactive:

```elixir
Repo.update!(LtiJwk.changeset(old_jwk, %{active: false}))
```
