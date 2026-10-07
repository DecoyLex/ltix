# JWK Management

Requesting an access token for Advantage services requires a signed
JWT assertion, which means your tool needs an RSA key pair. This guide
covers generating keys, serving a JWKS endpoint, and rotating keys.

> #### Leaked keys let attackers impersonate your tool {: .warning}
>
> Your private key signs the OAuth assertions that prove your tool's
> identity to platforms. If an attacker obtains it, they can request
> access tokens and call platform APIs as your tool, accessing roster
> data, posting grades, or reading course content. Never commit key
> material to version control, log it, or expose it via API responses.

## Generating a key

```elixir
jwk = Ltix.JWK.generate()
```

Store `kid`, `public_key_pem`, and `private_key_pem` in your database or
config, and encrypt the private key wherever you keep it. To reconstruct the
struct later, pass `kid` and one of the keys to `Ltix.JWK.new/1` or
`Ltix.JWK.new!/1`. A missing, invalid, or unknown field returns an
`Ltix.Errors.Invalid.InvalidField` error, and several bad fields are
returned together in an `Ltix.Errors.Invalid` error.

Use a separate key per registration so you can rotate them
independently.

## Signing with a key

Ltix never stores your private key. When it needs a signature, it calls your storage adapter's `c:Ltix.StorageAdapter.key_id/1` and `c:Ltix.StorageAdapter.sign/3` callbacks. `Ltix.JWK.sign/2` produces the signature for a key your application has.

```elixir
@impl true
def key_id(_registration), do: {:ok, current_jwk().kid}

@impl true
def sign(_registration, key_id, message) do
  case Enum.find(active_jwks(), &(&1.kid == key_id)) do
    nil -> {:error, :unknown_key}
    jwk -> Ltix.JWK.sign(jwk, message)
  end
end
```

`sign/3` signs with the key that has the given ID and returns an error for an ID it doesn't have. A request that starts before a rotation still gets a signature from the key whose ID is in its JWT header.

A key in a key management service does not have to be exported. Call the service from `sign/3` and return its RS256 signature, and build the JWK for your key set endpoint from the public key the service returns. See [Storage Adapters](storage-adapters.md#signing).

## Serving a JWKS endpoint

Platforms fetch your public keys to verify your tool's signed
assertions. You provide the JWKS endpoint URL during tool
registration.

Each key has a unique `kid`, so platforms match signatures to the
correct key automatically. Serve the endpoint with `to_jwks/1`, which
returns a JWKS map with only the public keys.

```elixir
def jwks(conn, _params) do
  json(conn, Ltix.JWK.to_jwks(MyApp.Lti.list_public_jwks()))
end
```

A JWK built from a public key is enough for this. Store each key's
`public_key_pem` and build the JWKs for the endpoint from that.

```elixir
Ltix.JWK.new!(public_key_pem: key.public_key_pem, kid: key.kid)
```

`Ltix.JWK.new/1` also takes a public key as a DER binary or a JWK map,
which are the formats key management services return.

For tools with a single registration, you can hard-code a single key.
For tools managing multiple registrations, see the
[Managing JWKs with Ecto](cookbooks/managing-jwks-with-ecto.md) cookbook for a
database-backed approach with key rotation.

## Key rotation

When you rotate a key, your JWKS endpoint must continue serving the
old public key until platforms have refreshed their cache. A typical
overlap period is 24-48 hours.

The rotation sequence has four steps.

1. Generate a new key
2. Start using the new key for signing
3. Serve both old and new public keys from your JWKS endpoint
4. After the overlap period, stop serving the old key

During the overlap, `to_jwks/1` accepts a list, so serving both keys
is straightforward.

```elixir
Ltix.JWK.to_jwks([old_jwk, new_jwk])
```

## Next steps

- [Managing JWKs with Ecto](cookbooks/managing-jwks-with-ecto.md) - database
  storage, JWKS controller, and automated rotation
- [Advantage Services](advantage-services.md) - how keys are used
  in service authentication
- [Storage Adapters](storage-adapters.md) - the callbacks that sign
  with your keys
- `Ltix.JWK` - API reference
