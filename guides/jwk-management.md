# JWK Management

Every Advantage service call requires a signed JWT assertion, which
means your tool needs an RSA key pair. This guide covers generating
key pairs, serving a JWKS endpoint, and rotating keys.

> #### Leaked keys let attackers impersonate your tool {: .warning}
>
> Your private key signs the OAuth assertions that prove your tool's
> identity to platforms. If an attacker obtains it, they can request
> access tokens and call platform APIs as your tool, accessing roster
> data, posting grades, or reading course content. Never commit key
> material to version control, log it, or expose it via API responses.

## Generating key pairs

```elixir
{private, _public} = Ltix.JWK.generate_key_pair()
```

The private key goes into your registration as `tool_jwk`. You only
need to store the private key. `Ltix.JWK.to_jwks/1` derives the
public half automatically when serving your JWKS endpoint.

The spec recommends a separate key per registration so you can rotate
them independently and limit blast radius if one is compromised.

## Serving a JWKS endpoint

Platforms fetch your public keys to verify your tool's signed
assertions. You provide the JWKS endpoint URL during tool
registration.

Each key has a unique `kid`, so platforms match signatures to the
correct key automatically. Pass your private keys to `to_jwks/1` and
it returns a JWKS map with only the public halves:

```elixir
Ltix.JWK.to_jwks([private_key_1, private_key_2])
#=> %{"keys" => [%{"kty" => "RSA", "kid" => "...", "n" => "...", ...}, ...]}
```

Private material is stripped automatically, so it's safe to pass
private keys directly.

For tools with a single registration, you can hard-code a single key.
For tools managing multiple registrations, see the
[Managing JWKs with Ecto](cookbooks/jwk-management.md) cookbook for a
database-backed approach with key rotation.

## Key rotation

When you rotate a key, your JWKS endpoint must continue serving the
old public key until platforms have refreshed their cache. A typical
overlap period is 24-48 hours.

The rotation sequence:

1. Generate a new key pair
2. Start using the new key for signing
3. Serve both old and new public keys from your JWKS endpoint
4. After the overlap period, stop serving the old key

During the overlap, `to_jwks/1` accepts a list, so serving both keys
is straightforward:

```elixir
Ltix.JWK.to_jwks([old_private, new_private])
```

## Next steps

- [Managing JWKs with Ecto](cookbooks/jwk-management.md): database
  storage, JWKS controller, and automated rotation
- [Advantage Services](advantage-services.md): how keys are used
  in service authentication
- [Storage Adapters](storage-adapters.md): where registrations
  (and their keys) are stored
- `Ltix.JWK`: API reference
