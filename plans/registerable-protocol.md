# Registerable & Deployable Protocols

**Scope**: Introduce `Ltix.Registerable` and `Ltix.Deployable` protocols so
that host apps can return their own structs from `StorageAdapter` callbacks.
The library extracts `Registration` and `Deployment` data via protocol
dispatch; `LaunchContext` holds the user's original structs.

**Motivation**: Today the user must manually construct `%Registration{}` and
`%Deployment{}` in their storage adapter, which is error-prone. After launch,
`LaunchContext` holds only Ltix's internal structs — the user's own data (DB
IDs, tenant associations, etc.) is lost, forcing an extra query to reconnect
with their records.

**Design decisions**:

- Two protocols (`Registerable`, `Deployable`), not one combined protocol —
  they operate on different structs from different callbacks.
- `LaunchContext.registration` and `.deployment` hold the user's original
  structs (whatever implements the protocol). Ltix calls the protocol
  internally whenever it needs `Registration.t()` or `Deployment.t()`.
- Identity implementations for `Ltix.Registration` and `Ltix.Deployment`
  keep test helpers and internal code working without wrapping.
- `StorageAdapter` callback return types become protocol-typed.
- The nonce callbacks (`store_nonce`, `validate_nonce`) still receive
  `Registration.t()` — the library resolves the protocol before calling them.
  This avoids forcing users to implement `Registerable` just to handle nonces.
- `OAuth.Client` stores `Registration.t()` (resolved), not the user's struct.
  OAuth is an internal concern; the user's struct doesn't belong there.

---

## Phase 1 — Protocols and Identity Implementations

Define the protocols and implement them for the existing Ltix structs.

### 1.1 `Ltix.Registerable` protocol

Create `lib/ltix/registerable.ex`:

```elixir
defprotocol Ltix.Registerable do
  @spec to_registration(t()) :: {:ok, Ltix.Registration.t()} | {:error, Exception.t()}
  def to_registration(source)
end
```

- Single function: `to_registration/1`
- Returns `{:ok, Registration.t()} | {:error, Exception.t()}`
- Validation happens inside the implementation (typically via `Registration.new/1`)

### 1.2 `Ltix.Deployable` protocol

Create `lib/ltix/deployable.ex`:

```elixir
defprotocol Ltix.Deployable do
  @spec to_deployment(t()) :: {:ok, Ltix.Deployment.t()} | {:error, Exception.t()}
  def to_deployment(source)
end
```

### 1.3 Identity implementations

Implement protocols for `Registration` and `Deployment` — identity transform
(wraps self in `{:ok, self}`).

In `lib/ltix/registration.ex`:

```elixir
defimpl Ltix.Registerable, for: Ltix.Registration do
  def to_registration(reg), do: {:ok, reg}
end
```

In `lib/ltix/deployment.ex`:

```elixir
defimpl Ltix.Deployable, for: Ltix.Deployment do
  def to_deployment(dep), do: {:ok, dep}
end
```

### 1.4 Tests

- `Registerable.to_registration(%Registration{})` returns `{:ok, reg}`
- `Deployable.to_deployment(%Deployment{})` returns `{:ok, dep}`
- Protocol raises for unimplemented types

### 1.5 Docs

- `@moduledoc` on each protocol with example of implementing for a custom struct
- Follow the `ContentItem` protocol doc style

---

## Phase 2 — Update StorageAdapter

Change callback return types to accept any `Registerable`/`Deployable`
implementor.

### 2.1 `get_registration/2`

```elixir
# Before
@callback get_registration(issuer :: String.t(), client_id :: String.t() | nil) ::
            {:ok, Registration.t()} | {:error, :not_found}

# After
@callback get_registration(issuer :: String.t(), client_id :: String.t() | nil) ::
            {:ok, Registerable.t()} | {:error, :not_found}
```

### 2.2 `get_deployment/2`

The first argument changes too — it now receives whatever the user returned
from `get_registration`, after Ltix has resolved the protocol internally.
But to keep things simple, the callback still receives `Registration.t()` —
the library resolves the protocol before calling `get_deployment`.

```elixir
# Before
@callback get_deployment(registration :: Registration.t(), deployment_id :: String.t()) ::
            {:ok, Deployment.t()} | {:error, :not_found}

# After
@callback get_deployment(registration :: Registration.t(), deployment_id :: String.t()) ::
            {:ok, Deployable.t()} | {:error, :not_found}
```

### 2.3 `store_nonce/2` and `validate_nonce/2`

No change — these still receive `Registration.t()`. The library resolves the
protocol before calling them.

### 2.4 Update `@moduledoc` and `@doc`

Update docs to reference the protocols and show an example of a custom struct.

---

## Phase 3 — Update OIDC Flow

Wire the protocols into login initiation and callback handling.

### 3.1 `LoginInitiation.call/3`

After `get_registration` returns, resolve the protocol:

```elixir
{:ok, user_registration} <- lookup_registration(params, callback_module),
{:ok, registration} <- Registerable.to_registration(user_registration),
```

Then use `registration` (the resolved `Registration.t()`) for nonce storage
and auth request building, same as today.

### 3.2 `Callback.call/4`

After `get_registration` returns, resolve the protocol. After
`get_deployment` returns, resolve that too. Build `LaunchContext` with the
user's original structs:

```elixir
{:ok, user_registration} <- lookup_registration(iss, client_id, callback_module),
{:ok, registration} <- Registerable.to_registration(user_registration),
{:ok, raw_claims} <- Token.verify(id_token, registration, opts),
:ok <- validate_nonce(raw_claims, registration, callback_module),
...
{:ok, user_deployment} <- lookup_deployment(raw_claims, registration, callback_module),
{:ok, _deployment} <- Deployable.to_deployment(user_deployment),
{:ok, claims} <- LaunchClaims.from_json(raw_claims, parsers: claim_parsers) do
  {:ok, %LaunchContext{
    claims: claims,
    registration: user_registration,
    deployment: user_deployment
  }}
end
```

Note: the resolved `Registration.t()` is used for JWT verification, nonce
validation, and deployment lookup. The user's original struct goes into the
`LaunchContext`.

### 3.3 Tests

- Existing OIDC tests continue to pass (they use `Registration` and
  `Deployment` directly, which have identity implementations)
- Add tests verifying the flow works with custom structs implementing the
  protocols

---

## Phase 4 — Update LaunchContext

### 4.1 Struct and typespec

```elixir
# Before
@type t :: %__MODULE__{
        claims: LaunchClaims.t(),
        registration: Registration.t(),
        deployment: Deployment.t()
      }

# After
@type t :: %__MODULE__{
        claims: LaunchClaims.t(),
        registration: Registerable.t(),
        deployment: Deployable.t()
      }
```

### 4.2 `@moduledoc`

Update field descriptions to explain that `registration` and `deployment`
hold whatever the storage adapter returned, and that users can access their
own fields directly.

---

## Phase 5 — Update Advantage Services

The Advantage services (`MembershipsService`, `GradeService`, `DeepLinking`)
access `context.registration` to get `Registration.t()` fields. They now
need to resolve the protocol first.

### 5.1 `MembershipsService.authenticate/2` and `GradeService.authenticate/2`

When called with a `LaunchContext`:

```elixir
def authenticate(%LaunchContext{} = context, opts) do
  with {:ok, registration} <- Registerable.to_registration(context.registration),
       ... do
    OAuth.authenticate(registration, ...)
  end
end
```

The `%Registration{}` pattern match overload stays as-is (user can still
pass a raw `Registration` for direct use).

### 5.2 `DeepLinking.build_response/3`

Resolve the protocol at the top of the function:

```elixir
with {:ok, registration} <- Registerable.to_registration(context.registration),
     {:ok, deployment} <- Deployable.to_deployment(context.deployment),
     ... do
  # use `registration` and `deployment` for JWT building
end
```

### 5.3 `OAuth.Client`

`OAuth.Client.registration` stays as `Registration.t()`. When built from
`OAuth.authenticate/2`, it already receives a resolved `Registration.t()`.
When built from `Client.from_access_token/2`, the user passes a
`Registration.t()` directly (Advantage services are an internal concern).

No changes needed.

### 5.4 Tests

- Existing Advantage service tests pass unchanged (identity impls)
- Add integration tests with custom protocol implementations

---

## Phase 6 — Update Test Helpers

### 6.1 `Ltix.Test`

`setup_platform!/1` and related helpers produce `Registration.t()` and
`Deployment.t()` — these already implement the protocols via Phase 1.
No functional changes needed.

### 6.2 `Ltix.Test.StorageAdapter`

The in-memory test adapter stores `Registration.t()` and `Deployment.t()`.
It continues to work unchanged — the identity implementations satisfy the
protocol.

### 6.3 Add custom-struct test helpers

Add a test support module with sample custom structs that implement the
protocols, for use in protocol-specific tests.

---

## Phase 7 — Documentation

### 7.1 Protocol `@moduledoc`s

Each protocol gets a `@moduledoc` showing:
- What it does and why
- A complete implementation example
- How it fits into the launch flow

### 7.2 Update `StorageAdapter` docs

Show the "before and after" — returning `Registration.t()` still works,
but now users can return their own structs.

### 7.3 Update `LaunchContext` docs

Explain that `context.registration` is whatever the storage adapter returned,
with examples of accessing custom fields.
