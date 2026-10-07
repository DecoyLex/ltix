# Upgrading to 0.2

Ltix 0.2 has 60 breaking changes. Each section of this guide describes the changes to one part of Ltix and what to change in your tool.

For every tool, read the sections on login and launch, the storage adapter, launch claims, the key set, and errors, platform requests, and tests. If your tool calls Advantage services or builds deep linking responses, also read the section on Advantage services.

Ltix 0.2 requires Elixir 1.17 or later.

```elixir
# mix.exs
{:ltix, "~> 0.2"}
```

Compile with `mix compile --warnings-as-errors` while you upgrade. Without it, a storage adapter with the 0.1 callbacks compiles with only warnings.

## Login and launch

### Ltix rejects a token from a different login

In 0.1, Ltix checked that the `state` parameter matched the state in the session, and that your adapter had stored the token's nonce. It did not check that the nonce and the state came from the same login. Ltix accepted the token of one login with the state of another, and the two logins could be for different users or different registrations.

In 0.2, Ltix computes the nonce at login from the state and the registration that `get_registration/3` returned. At launch, it computes the nonce again from the state in the session and the registration for the token, and returns `NonceNotFound` when the token's nonce is different.

A login that 0.1 handled has a random nonce, which 0.2 cannot compute from the state, so its launch returns `NonceNotFound`. A user who logged in before you deployed and launches after has to launch again from the platform.

#### What to change

Some platforms send no `client_id` in the login request. If your `get_registration/3` returns the issuer's first registration when `client_id` is `nil`, Ltix computes the nonce from that registration, and a launch for any of the issuer's other registrations returns `NonceNotFound`. When `client_id` is `nil` and the issuer has more than one registration, return the one that has the deployment in `opts[:deployment_id]`, or return `{:error, :not_found}`.

### Ltix rejects a token an hour after its `iat`

In 0.1, Ltix accepted a token until its `exp`, and set no maximum on `exp`. To detect a replay, your adapter had to store the nonce until then.

In 0.2, Ltix accepts a token until its `exp` or an hour after its `iat`, whichever is earlier. After that, a launch returns `TokenExpired`. A launch returns `MissingClaim` when its token has no `iat`.

#### What to change

Check that your platforms send `iat`. To change the limit, set `config :ltix, max_token_age: seconds`, or pass `:max_token_age` to `Ltix.handle_callback/3`.

#### Keep the old behavior

Set `max_token_age: :infinity`. Ltix then accepts a token until its `exp`. A token still has to have `iat`.

### Ltix rejects a token with `iat` or `nbf` in the future

In 0.1, Ltix did not check whether `iat` was in the future, and ignored `nbf`.

In 0.2, a launch returns `TokenNotYetValid` when its token's `iat` or `nbf` is more than 5 seconds in the future. A launch returns `InvalidClaim` when its token's `nbf` is not a number.

#### What to change

Keep your servers' clocks synchronized. If a platform's clock runs ahead of yours, pass a larger `:clock_skew`, in seconds, to `Ltix.handle_callback/3`.

### Ltix rejects an `aud` list with other audiences

In 0.1, Ltix accepted an `aud` list that included your `client_id` and other values.

In 0.2, `Ltix.handle_callback/3` returns `AudienceMismatch` for an `aud` list that includes any value other than your `client_id`.

#### What to change

Launch from each of your platforms, and check that `Ltix.handle_callback/3` returns `{:ok, context}`.

### Functions raise for an unknown option

In 0.1, functions ignored unknown options. Ltix ignored a misspelled option such as `allow_anonymus: true` and reported no error.

In 0.2, every function raises `Ltix.Errors.Invalid.InvalidOption` for an unknown option or an invalid option value.

#### What to change

Run your tests and fix each call that raises.

```elixir
# 0.1
Ltix.handle_callback(params, state, allow_anonymus: true)
#=> {:error, %Ltix.Errors.Invalid.MissingClaim{claim: "sub"}}

# 0.2
Ltix.handle_callback(params, state, allow_anonymus: true)
#=> ** (Ltix.Errors.Invalid.InvalidOption) Option :allow_anonymus is unknown
```

## Storage adapter

### `Ltix.StorageAdapter`

| 0.1 | 0.2 |
|---|---|
| `get_registration/2` | `get_registration/3` |
| `get_deployment/2` | `get_deployment/3` |
| `store_nonce/2` | removed |
| `validate_nonce/2` | `validate_nonce/4` |

### `Ltix.Registration`

The `tool_jwk` field is removed.

### `Ltix.JWK`

| 0.1 | 0.2 |
|---|---|
| `generate_key_pair/1`, which returned two `JOSE.JWK` structs | `generate/1`, which returns one `Ltix.JWK` |
| `to_jwks/1` with a list of `JOSE.JWK` structs | `to_jwks/1` with one `Ltix.JWK` or a list of them |

### Storage adapter callbacks receive your registration and `opts`

In 0.1, Ltix converted the struct your `get_registration/2` returned to an `Ltix.Registration`, and passed that to `get_deployment/2`, `store_nonce/2`, and `validate_nonce/2`. Your adapter had to query for its own record again on every launch. Ltix called each callback with the issuer, client ID, or deployment ID, and you could not pass a callback any other value.

In 0.2, Ltix passes `get_deployment/3` and `validate_nonce/4` the struct your `get_registration/3` returned. Every callback has `opts` as its last argument. `opts` is the keyword list you pass as `:storage_adapter_options` to `Ltix.handle_login/3`, `Ltix.handle_callback/3`, and the service functions, and `[]` when you pass none. In `get_registration/3`, Ltix adds `:deployment_id` to `opts` when the platform sent a deployment ID. Ltix has not verified that ID.

#### What to change

Add `opts` to every callback, and match on your own struct in `get_deployment/3` and `validate_nonce/4`.

```elixir
# 0.1
@impl true
def get_registration(issuer, client_id) do
  fetch(PlatformRegistration, issuer: issuer, client_id: client_id)
end

@impl true
def get_deployment(%Ltix.Registration{issuer: issuer, client_id: client_id}, deployment_id) do
  registration = Repo.get_by!(PlatformRegistration, issuer: issuer, client_id: client_id)
  fetch(PlatformDeployment, registration_id: registration.id, deployment_id: deployment_id)
end

# 0.2
@impl true
def get_registration(issuer, client_id, _opts) do
  fetch(PlatformRegistration, issuer: issuer, client_id: client_id)
end

@impl true
def get_deployment(%PlatformRegistration{id: registration_id}, deployment_id, _opts) do
  fetch(PlatformDeployment, registration_id: registration_id, deployment_id: deployment_id)
end
```

See [Storage Adapters](storage-adapters.md) for a complete adapter and how to use `opts`.

### Your adapter records a nonce at launch

In 0.1, Ltix called `store_nonce/2` on every login, before it had verified anything. Anyone who knew the issuer of one of your registrations could add rows to your nonce table without limit.

In 0.2, Ltix stores nothing at login. At launch, it calls `validate_nonce/4` after it has verified the token and compared the token's nonce with the one it computes from the session's state.

#### What to change

Delete `store_nonce/2`. In `validate_nonce/4`, insert the nonce and return `:ok`. Return `{:error, :nonce_already_used}` when the table already has the nonce. `expires_at` is when Ltix stops accepting the token, which is its `exp` or `max_token_age` after its `iat`, whichever is earlier. Delete rows whose `expires_at` has passed.

```elixir
# 0.1
@impl true
def store_nonce(nonce, _registration) do
  Repo.insert!(%LtiNonce{nonce: nonce})
  :ok
end

@impl true
def validate_nonce(nonce, _registration) do
  case Repo.delete_all(from n in LtiNonce, where: n.nonce == ^nonce) do
    {1, _} -> :ok
    {0, _} -> {:error, :nonce_not_found}
  end
end

# 0.2
@impl true
def validate_nonce(nonce, _registration, expires_at, _opts) do
  case Repo.insert_all(LtiNonce, [%{nonce: nonce, expires_at: expires_at}], on_conflict: :nothing) do
    {1, _} -> :ok
    {0, _} -> {:error, :nonce_already_used}
  end
end
```

Empty the nonce table, add `expires_at`, and add a unique index on the nonce. With the index, `insert_all/3` returns `{0, _}` for a nonce the table already has.

```elixir
def change do
  execute "DELETE FROM lti_nonces", "DELETE FROM lti_nonces"

  alter table(:lti_nonces) do
    add :expires_at, :utc_datetime, null: false
  end

  create unique_index(:lti_nonces, [:nonce])
end
```

### Logins and launches return `StorageError` for a storage failure

In 0.1, Ltix raised `CaseClauseError` when a callback returned a value it did not expect, such as `{:error, :timeout}`. It also accepted a deployment from `get_deployment/2` whose `deployment_id` was different from the one in the token.

In 0.2, the login or launch returns `Ltix.Errors.Unknown.StorageError` in both cases. Its `result` field has the value your callback returned.

#### What to change

Return `{:error, reason}` from a callback when storage fails, and handle `StorageError` where you handle launch errors.

### Registrations have no signing key

In 0.1, the registration's `tool_jwk` field had your private key. Every `Ltix.LaunchContext` and `Ltix.OAuth.Client` includes the registration, so in 0.1 each one included the key. If you stored a launch context in a Phoenix cookie session, Phoenix sent the key to the browser, because a cookie session is signed and unencrypted by default. Anyone with the key could act as your tool.

In 0.2, `Ltix.Registration` has no `tool_jwk` field, and `Ltix.Registration.new/1` returns `InvalidField` when you pass it.

#### What to change

Delete `tool_jwk` from your `Ltix.Registerable` implementation.

```elixir
# 0.1
Ltix.Registration.new(%{
  issuer: record.issuer,
  client_id: record.client_id,
  auth_endpoint: record.auth_endpoint,
  jwks_uri: record.jwks_uri,
  token_endpoint: record.token_endpoint,
  tool_jwk: record.tool_jwk
})

# 0.2
Ltix.Registration.new(%{
  issuer: record.issuer,
  client_id: record.client_id,
  auth_endpoint: record.auth_endpoint,
  jwks_uri: record.jwks_uri,
  token_endpoint: record.token_endpoint
})
```

### Your storage adapter signs each JWT

In 0.1, Ltix signed with the key in the registration. Your application loaded the private key on every login and launch and kept it unencrypted in memory, even if you stored it in a key management service.

In 0.2, Ltix builds each JWT and calls your adapter for the signature.

#### What to change

Add `key_id/2` and `sign/4` to your adapter if your tool calls Advantage services or builds deep linking responses.

- In `key_id/2`, return `{:ok, kid}` for the key to sign with. Ltix puts the `kid` in the JWT header, and the platform uses it to find the public key in your key set.
- In `sign/4`, sign `message` with the key that has `key_id`. Return `{:error, reason}` when you have no key with that ID.

Ltix passes both callbacks the registration struct you gave it. When you call `authenticate/2` with a registration, pass the struct your `get_registration/3` returns. In 0.1, `authenticate/2` took an `Ltix.Registration`.

A key is an `Ltix.JWK` struct with `kid`, `public_key_pem`, and `private_key_pem`. `Ltix.JWK.new/1` builds one from a PEM, a DER binary, or a JWK map, and the private key is optional. If you followed the 0.1 JWK Management cookbook, you stored each key as JWK JSON. Decode the JSON and pass the map as `:private_jwk`. The `Ltix.JWK` has the `kid` from the JSON. Keep each key's `kid`, because platforms cache your key set. `to_jwks/1` accepts keys that have no private key.

```elixir
# 0.1
{private, _public} = Ltix.JWK.generate_key_pair()

def to_registration(record) do
  tool_jwk = record.private_jwk |> JSON.decode!() |> JOSE.JWK.from_map()
  Ltix.Registration.new(%{issuer: record.issuer, ..., tool_jwk: tool_jwk})
end

def jwks(conn, _params) do
  json(conn, Ltix.JWK.to_jwks(MyApp.Lti.list_private_jwks()))
end

# 0.2
jwk = Ltix.JWK.generate()

@impl true
def key_id(%PlatformRegistration{} = registration, _opts) do
  {:ok, MyApp.Lti.signing_key(registration).kid}
end

@impl true
def sign(_registration, key_id, message, _opts) do
  case MyApp.Lti.get_key(key_id) do
    nil -> {:error, :unknown_key}
    key -> Ltix.JWK.sign(Ltix.JWK.new!(private_jwk: JSON.decode!(key.private_jwk)), message)
  end
end

def jwks(conn, _params) do
  json(conn, Ltix.JWK.to_jwks(MyApp.Lti.list_public_jwks()))
end
```

See [JWK Management](jwk-management.md) for storing and rotating signing keys.

`generate/1` creates 4096-bit keys by default. 0.1 created 2048-bit keys.

#### Keep the old behavior

Pass `key_size: 2048` to `generate/1`, or set `config :ltix, default_key_size: 2048`.

## Launch claims

### `Ltix.LaunchClaims`

| 0.1 | 0.2 |
|---|---|
| `Ltix.LaunchClaims.AgsEndpoint` | `Ltix.LaunchClaims.AGSEndpoint` |
| `Ltix.LaunchClaims.Lis` | `Ltix.LaunchClaims.LIS` |
| `AgsEndpoint.scope` | `AGSEndpoint.scopes` |
| `AgsEndpoint.lineitems` | `AGSEndpoint.line_items` |
| `AgsEndpoint.lineitem` | `AGSEndpoint.line_item` |
| `Lis.person_sourcedid` | `LIS.person_source_id` |
| `Lis.course_offering_sourcedid` | `LIS.course_offering_source_id` |
| `Lis.course_section_sourcedid` | `LIS.course_section_source_id` |
| `DeepLinkingSettings.accept_lineitem` | `DeepLinkingSettings.accept_line_item` |

### Ltix checks the type of each claim

In 0.1, Ltix did not check the type of a claim. When a platform sent a number as `name`, `context.claims.name` was that number.

In 0.2, `Ltix.handle_callback/3` returns `InvalidClaim` when a required claim has the wrong type. It sets an optional claim that has the wrong type to `nil`.

#### What to change

Launch from each of your platforms. Check that `Ltix.handle_callback/3` returns `{:ok, context}` and that the claims your tool reads are not `nil`.

### `Role.administrator?/1` returns `true` for an institution administrator

In 0.1, `Role.administrator?/1` returned `true` for a course administrator and `false` for an institution administrator. `Role.from_atom(:administrator)` returned an institution administrator, so `Role.administrator?([Role.from_atom(:administrator)])` returned `false`.

In 0.2, `administrator?/1` returns `true` for an institution administrator, and `context_administrator?/1` returns `true` for a course administrator.

#### What to change

Call `Role.context_administrator?/1` where your code checks for a course administrator.

```elixir
# 0.1
Role.administrator?(context.claims.roles)

# 0.2
Role.context_administrator?(context.claims.roles)
```

## Key set

### `Ltix.JWT.KeySet`

`Ltix.JWT.KeySet.Cache`, `Ltix.JWT.KeySet.EtsCache`, `Ltix.JWT.KeySet.CachexCache`, and the `:jwks_cache` setting are removed. `get_key/3` returns an `Ltix.JWK`. In 0.1 it returned a `JOSE.JWK`.

### Your application starts the key set

In 0.1, when a token's key ID was not among a platform's cached keys, Ltix deleted the cached keys and fetched them again. Ltix reads the key ID before it checks the signature, so it did this for forged tokens too. Anyone could post forged launches, and Ltix sent the platform one request for each.

In 0.2, `Ltix.JWT.KeySet` is a process that fetches each key set URL at most once every 30 seconds on each node. A launch raises `KeySetNotStarted` when the process is not running.

#### What to change

Add `Ltix.JWT.KeySet` to your supervision tree. If you configured `:jwks_cache` in 0.1, delete the setting, the cache module, and any Cachex child you started for it.

```elixir
# 0.1
children = [
  MyApp.Repo,
  MyAppWeb.Endpoint
]

# 0.2
children = [
  MyApp.Repo,
  Ltix.JWT.KeySet,
  MyAppWeb.Endpoint
]
```

## Advantage services

### `Ltix.GradeService`

| 0.1 | 0.2 |
|---|---|
| `get_results/2` | `list_results/2` |
| `delete_line_item(client, line_item)` | `delete_line_item(client, line_item: line_item)` |
| `Score.to_json/1` | `Score.to_map/1` |
| `LineItem.to_json/1` | `LineItem.to_map/1` |

### `Ltix.MembershipsService`

| 0.1 | 0.2 |
|---|---|
| `get_members/2` | `list_members/2` |
| `Member.lis_person_sourcedid` | `Member.lis_person_source_id` |
| `Member.lti11_legacy_user_id` | `Member.lti_1_1_legacy_user_id` |

### `Ltix.DeepLinking`

| 0.1 | 0.2 |
|---|---|
| `Ltix.DeepLinking.ContentItem.LtiResourceLink` | `Ltix.DeepLinking.ContentItem.LTIResourceLink` |
| `Ltix.DeepLinking.ContentItem.HtmlFragment` | `Ltix.DeepLinking.ContentItem.HTMLFragment` |
| `build_response/3` with `:msg` | `build_response/3` with `:message` |
| `ContentItem.to_json/1` | `ContentItem.to_map/1` |
| `ContentItem.item_type/1` | removed |

### `Ltix.OAuth.Client`

| 0.1 | 0.2 |
|---|---|
| `client.access_token` | `client.token.access_token` |
| `client.expires_at` | `client.token.expires_at` |
| `client.scopes` | `client.token.granted_scopes` |
| `refresh/1`, which always requested a token | `force_refresh/1` |

`AccessToken.granted_scopes` is a `MapSet`. In 0.1 it was a list.

### `AGSEndpoint.new/1` requires the scopes

In 0.1, you built a grade endpoint outside a launch as an `%AgsEndpoint{}` struct. When you left out `scope`, Ltix requested a token with no scopes, and `post_score/3` returned `ScopeMismatch`.

In 0.2, `AGSEndpoint.new/1` returns `InvalidField` when you leave out `:scopes`. `MembershipsEndpoint.new/1` returns `{:ok, endpoint}`. In 0.1 it returned the endpoint.

#### What to change

Build endpoints with `AGSEndpoint.new/1` and `MembershipsEndpoint.new/1`. Save `context.claims.ags_endpoint.scopes` from the launch when you save its URLs.

```elixir
# 0.1
endpoint = %AgsEndpoint{lineitems: url, scope: scopes}
memberships = MembershipsEndpoint.new(memberships_url)

# 0.2
endpoint = AGSEndpoint.new!(line_items: url, scopes: scopes)
memberships = MembershipsEndpoint.new!(memberships_url)
```

### Dates are `DateTime` values

In 0.1, dates in content items, line items, and score submissions were strings. Ltix did not check that a string was an ISO 8601 date before it sent the string to the platform.

In 0.2, each of these fields takes a `DateTime`, and Ltix sends it as an ISO 8601 string. The constructor returns `InvalidField` for a string.

#### What to change

Pass a `DateTime` for line item start and end dates, the times in a score's `:submission`, a file content item's `expires_at`, and a resource link's `:available` and `:submission` windows.

```elixir
# 0.1
Score.new(user_id: id, submission: %{submitted_at: "2026-03-01T12:00:00Z"}, ...)

# 0.2
Score.new(user_id: id, submission: %{submitted_at: ~U[2026-03-01 12:00:00Z]}, ...)
```

### List functions return an error above 10,000 entries

In 0.1, `get_results/2` and `list_line_items/2` fetched every page into one list, with no limit on its size.

In 0.2, `list_results/2` and `list_line_items/2` return `CollectionTooLarge` above 10,000 entries. `get_members/2` had that limit in 0.1.

#### What to change

Stream a large collection with `stream_line_items/2` or `stream_results/2`.

#### Keep the old behavior

Pass `max_results: :infinity` to `list_results/2`, or `max_line_items: :infinity` to `list_line_items/2`.

### `delete_line_item/2` takes the line item as an option

In 0.1, a line item was an option to `post_score/3` and the second argument of `delete_line_item/3`. `delete_line_item/3` raised `FunctionClauseError` for a line item without an `id`.

In 0.2, `delete_line_item/2` takes the `:line_item` option, and returns `MissingLineItemId` for a line item without an `id`.

#### What to change

Pass the line item as `:line_item`.

```elixir
# 0.1
:ok = GradeService.delete_line_item(client, line_item)

# 0.2
:ok = GradeService.delete_line_item(client, line_item: line_item)
```

### `from_access_token/2` and `with_endpoints/2` accept a token with fewer scopes than you requested

A platform can grant fewer scopes than you request. In 0.1, `authenticate/2` accepted a token with fewer scopes, and `from_access_token/2` and `with_endpoints/2` returned `ScopeMismatch` for the same token. You could not rebuild a client from a token that `authenticate/2` had accepted and you had cached.

In 0.2, `authenticate/2`, `from_access_token/2`, and `with_endpoints/2` all accept a token with fewer scopes. Each service call returns `ScopeMismatch` when the token does not have the scope for that call.

#### What to change

If your code handled `ScopeMismatch` from `from_access_token/2` or `with_endpoints/2`, handle it from the service calls.

#### Keep the old behavior

Pass `require_all_scopes: true` to `authenticate/2`, `from_access_token/2`, or `with_endpoints/3`. The function returns `ScopeMismatch` for a token with fewer scopes.

### `access_token`, `expires_at`, and `scopes` are removed from `Ltix.OAuth.Client`

In 0.1, `Ltix.OAuth.Client` had `access_token`, `expires_at`, and `scopes` fields, with values copied from the `AccessToken`. To cache the token, you had to build an `AccessToken` from those fields.

In 0.2, the three fields are removed, and `client.token` is the `AccessToken`.

#### What to change

Read the values from `client.token`, and cache `client.token`. To store it in a database or an external cache, store `AccessToken.to_map(client.token)` and read it with `AccessToken.from_map/1`.

```elixir
# 0.1
client.access_token
client.expires_at
client.scopes

# 0.2
client.token.access_token
client.token.expires_at
client.token.granted_scopes
```

### `refresh/1` returns the client unchanged until its token has expired

In 0.1, `refresh/1` requested a token every time you called it.

In 0.2, `refresh/1` returns the client unchanged when its token has not expired. `force_refresh/1` requests a token every time.

#### What to change

Call `force_refresh/1` where you need a new token before the current one expires.

```elixir
# 0.1
client = Client.refresh!(client)

# 0.2
client = Client.force_refresh!(client)
```

### `build_response/3` checks more of the platform's settings

In 0.1, `build_response/3` checked items against the platform's `accept_types`, `accept_multiple`, and `accept_lineitem` settings. It did not check `accept_presentation_document_targets` or `accept_media_types`. It also checked an item's type before it merged the item's `extensions`, so `extensions: %{"type" => "image"}` replaced the type after the check.

In 0.2, `build_response/3` also returns `PresentationTargetNotAccepted` for an item that `accept_presentation_document_targets` excludes, and `MediaTypeNotAccepted` for one that `accept_media_types` excludes. A content item constructor returns `InvalidField` for an extension key that has the name of a standard field. `build_response/3` reads each item's type from the map that `to_map/1` returns, and the `Ltix.DeepLinking.ContentItem` protocol has no `item_type/1`.

#### What to change

Rename `:msg` to `:message`. In your own `Ltix.DeepLinking.ContentItem` implementations, rename `to_json/1` to `to_map/1` and delete `item_type/1`.

```elixir
# 0.1
DeepLinking.build_response(context, items, msg: "Saved")

defimpl Ltix.DeepLinking.ContentItem, for: MyApp.ProctoredExam do
  def item_type(_item), do: "https://myapp.example.com/proctored_exam"
  def to_json(item), do: %{"type" => "https://myapp.example.com/proctored_exam", "id" => item.id}
end

# 0.2
DeepLinking.build_response(context, items, message: "Saved")

defimpl Ltix.DeepLinking.ContentItem, for: MyApp.ProctoredExam do
  def to_map(item), do: %{"type" => "https://myapp.example.com/proctored_exam", "id" => item.id}
end
```

## Errors, platform requests, and tests

### `Ltix.Errors`

| 0.1 | 0.2 |
|---|---|
| `Ltix.Errors.Invalid.InvalidJson` | `Ltix.Errors.Invalid.InvalidJSON` |
| `Ltix.Errors.Invalid.RosterTooLarge` | `Ltix.Errors.Invalid.CollectionTooLarge` |
| `ScopeMismatch` with a `scope` string | `ScopeMismatch` with a `scopes` list |

See [Error Handling](error-handling.md) for every error and its fields.

### Every expected failure is an Ltix error

0.1 had two problems.

- Some functions returned a `%Zoi.ParseError{}`, an `ArgumentError`, a `Req` exception, or a string. Code that matched on Ltix errors did not match these.
- `handle_callback/3` returned a missing required claim as `%MissingClaim{}`, and a missing field inside a claim as `%Ltix.Errors.Invalid{errors: [%MissingClaim{}]}`. A match on `%MissingClaim{}` did not match the second form.

0.2 makes these changes.

- A constructor returns `Ltix.Errors.Invalid.InvalidField` for an unknown, missing, or invalid field. Each constructor has a `new!/1`.
- A function that finds one error returns it. A function that finds several returns an error class struct with them in `errors`, such as `%Ltix.Errors.Invalid{errors: [...]}`.
- A request that gets a 401 or 403 from a platform returns `Ltix.Errors.Security.AccessDenied`. In 0.1, it returned `TransportError`.

#### What to change

Update each place you match on one of these errors.

```elixir
# 0.1
{:error, %Ltix.Errors.Invalid{errors: [%Ltix.Errors.Invalid.MissingClaim{}]}} = LaunchClaims.from_json(claims)
{:error, %ArgumentError{}} = Score.new(score_given: 5, ...)
{:error, %Ltix.Errors.Invalid.MissingClaim{}} = Ltix.Deployment.new("")
{:error, %Ltix.Errors.Unknown.TransportError{status: 403}} = MembershipsService.get_members(client)
{:error, %Req.TransportError{}} = Ltix.OAuth.authenticate(registration, endpoints: endpoints)
{:error, "bad claim"} = Ltix.handle_callback(params, state, claim_parsers: parsers)

# 0.2
{:error, %Ltix.Errors.Invalid.MissingClaim{}} = LaunchClaims.from_json(claims)
{:error, %Ltix.Errors.Invalid.InvalidField{}} = Score.new(score_given: 5, ...)
{:error, %Ltix.Errors.Invalid.InvalidField{}} = Ltix.Deployment.new("")
{:error, %Ltix.Errors.Security.AccessDenied{status: 403}} = MembershipsService.list_members(client)
{:error, %Ltix.Errors.Unknown.TransportError{}} = Ltix.OAuth.authenticate(registration, endpoints: endpoints)
{:error, %Ltix.Errors.Invalid.InvalidClaim{}} = Ltix.handle_callback(params, state, claim_parsers: parsers)
```

### Ltix sends requests only to public HTTPS addresses

In 0.1, Ltix sent requests to any URL a platform supplied. A key set URL, service URL, or pagination link could be an address on your internal network, and Ltix requested it. For an `http://` service URL, Ltix sent your access token unencrypted.

In 0.2, Ltix sends requests only over HTTPS and only to public addresses. It follows a redirect or pagination link only to the scheme, host, and port of the first request. A request with `verify: :verify_none` in its `:req_options` returns an error.

#### What to change

A platform on the public internet needs no change. For a platform on your network or your machine, set `:local_network_access` in `config :ltix` or as an option to one call. With `:local`, Ltix also sends requests to private network addresses. With `:loopback`, it also sends them to loopback addresses. Ltix accepts an `http://` URL only for a private or loopback address.

```elixir
# 0.1
Ltix.handle_callback(params, state)

# 0.2, for a platform on a private network address
Ltix.handle_callback(params, state, local_network_access: :local)
```

`:finch`, `:adapter`, `:unix_socket`, and proxy settings in `:req_options` need `local_network_access: :loopback`, because Ltix cannot check the addresses they connect to.

### `Ltix.Test`

| 0.1 | 0.2 |
|---|---|
| `mint_id_token/3` | `sign_id_token/3` |
| `valid_lti_claims(overrides)` | `valid_lti_claims(platform, overrides)` |
| `login_opts/1`, `callback_opts/1` | removed |
| `generate_rsa_key_pair/0` | `Ltix.JWK.generate/1` |
| `build_jwks/1` | `Ltix.JWK.to_jwks/1` |
| `platform.private_key`, `platform.kid` | `platform.jwk` |
| `platform.jwks` | `Ltix.JWK.to_jwks(platform.jwk)` |
| `verify_deep_linking_response/2` returning `{:error, :signature_invalid}` | `verify_deep_linking_response/2` returning `{:error, %Ltix.Errors.Security.SignatureInvalid{}}` |

### Ltix calls your storage adapter in tests

In 0.1, `Ltix.Test.setup_platform!/1` started an in-memory storage adapter, and `login_opts/1` and `callback_opts/1` returned options that made Ltix call it. Ltix did not call your own adapter in tests. `valid_lti_claims/1` used a fixed issuer and client ID, so launches with its tokens failed for a platform created with a different issuer or client ID. `launch_params/2` and `build_launch_context/2` had different default roles, and each ignored some options the other accepted.

In 0.2, `setup_platform!/1` creates the platform's keys, registration, and deployment, and Ltix calls the `:storage_adapter` in your test config. `launch_params/2` and `build_launch_context/2` take the same options, default to the instructor role, and raise `InvalidOption` for an unknown option.

#### What to change

- Add `:plug` to your test dependencies and set `config :ltix, req_options: [plug: {Req.Test, :ltix}]`. Ltix then sends each request to the `Req.Test` stub named after the module that makes the request, such as `Ltix.GradeService`. Ltix ignores the `:ltix` name.
- Pass `setup_platform!/1` a `:registration` function and a `:deployment` function that create the records in your storage.
- Pass `setup_platform!/1` the key your adapter signs with as `:tool_jwk`. `verify_deep_linking_response/2` checks the signature with that key.
- Start `Ltix.JWT.KeySet` before you call `setup_platform!/1`.

```elixir
# 0.1
platform = Ltix.Test.setup_platform!()
Ltix.handle_login(params, launch_url, Ltix.Test.login_opts(platform))

claims = Ltix.Test.valid_lti_claims(%{"nonce" => nonce})
token = Ltix.Test.mint_id_token(claims, platform.private_key, kid: platform.kid)
jwks = platform.jwks

Ltix.Test.build_launch_context(platform,
  ags_endpoint: %{lineitems: url, scope: scopes},
  memberships_endpoint: %{url: memberships_url}
)

# 0.2
# config/test.exs
config :ltix, req_options: [plug: {Req.Test, :ltix}]

platform =
  Ltix.Test.setup_platform!(
    registration: fn registration ->
      MyApp.Lti.create_registration!(Map.from_struct(registration))
    end,
    deployment: fn deployment, registration ->
      MyApp.Lti.create_deployment!(%{
        deployment_id: deployment.deployment_id,
        registration_id: registration.id
      })
    end,
    tool_jwk: MyApp.Lti.create_key!()
  )

Ltix.handle_login(params, launch_url)

claims = Ltix.Test.valid_lti_claims(platform, %{"nonce" => nonce})
token = Ltix.Test.sign_id_token(claims, platform.jwk)
jwks = Ltix.JWK.to_jwks(platform.jwk)

Ltix.Test.build_launch_context(platform,
  ags_endpoint: %{line_items: url, scopes: scopes},
  memberships_endpoint: %{context_memberships_url: memberships_url}
)
```

Check your adapter with `Ltix.Test.assert_storage_adapter!/2`. See [Testing LTI Launches](cookbooks/testing-lti-launches.md).

#### Keep the old behavior

To use the in-memory adapter, set `config :ltix, storage_adapter: Ltix.Test.StorageAdapter`, start it with `Ltix.Test.StorageAdapter.start_link(platforms: [platform])`, and pass the pid to `Ltix.Test.StorageAdapter.set_pid/1` in the test process.

## Next steps

- [Storage Adapters](storage-adapters.md) for a complete adapter and how to use `opts`
- [JWK Management](jwk-management.md) for storing and rotating signing keys
- [Threat Model](threat-model.md) for the attacks Ltix defends against
- [Hardening Your Tool](hardening.md) for what your application has to do
