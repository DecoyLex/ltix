# Memberships — Names and Role Provisioning Services (NRPS) v2.0 Implementation Plan

**Scope**: Tool-side NRPS v2.0 service client. Given a successful LTI 1.3
launch that includes the NRPS claim, the tool can query the platform's
membership endpoint to retrieve context (course) memberships.

**Spec references**:
- `[NRPS §X]` → LTI Names and Role Provisioning Services v2.0
  (https://www.imsglobal.org/spec/lti-nrps/v2p0/)
- `[Sec §X]` → 1EdTech Security Framework v1.0
  (https://www.imsglobal.org/spec/security/v1p0/)
- `[Core §X]` → LTI Core Specification v1.3
  (https://www.imsglobal.org/spec/lti/v1p3/)

**Prerequisites**: LTI 1.3 Core launch flow (already implemented). The NRPS
endpoint claim (`Ltix.LaunchClaims.MembershipsEndpoint`) is already parsed
from launch JWTs (currently named `NrpsEndpoint` — will be renamed).

**Approach**: TDD. Each module is developed test-first. The library remains
storage-agnostic and HTTP-client-agnostic (uses `Req` with testable stubs).
All new functions that accept keyword options use `NimbleOptions` for
validation, defaults, and documentation generation. Existing functions
will be migrated to `NimbleOptions` in a separate effort.

---

## 1. OAuth 2.0 Client Credentials Token (Shared Infrastructure)

Before the memberships service can call the platform, it needs an access
token. LTI Advantage services use the OAuth 2.0 client credentials grant
with a signed JWT assertion per [Sec §4.1].

> [Sec §4.1]: "Consumers MUST use the OAuth 2.0 Client Credentials grant
> type." The client authenticates using a JWT signed with its private key
> [Sec §4.1.1].

This module is shared infrastructure — AGS, Deep Linking response, and any
future Advantage services will also use it.

### 1.1 `Ltix.OAuth.ClientCredentials` — Token Request

**Spec basis**: [Sec §4.1] OAuth 2.0 Client Credentials grant;
[Sec §4.1.1] Using JWTs for Client Authentication.

**Responsibilities**:
1. Build a JWT assertion signed with the tool's private key [Sec §4.1.1]
2. POST to the platform's `token_endpoint` with grant_type and scope [Sec §4.1]
3. Parse the access token response (or the RFC 6749 §5.2 error response)
4. Return `{:ok, %AccessToken{}}` or `{:error, reason}`

**JWT assertion claims** [Sec §4.1.1]:

| Claim | Value | Spec |
|---|---|---|
| `iss` | Unique identifier for the tool (typically `client_id`) | [Sec §4.1.1] "A unique identifier for the entity that issued the JWT" |
| `sub` | Tool's `client_id` | [Sec §4.1.1] "client_id of the OAuth Consumer" |
| `aud` | Platform's `token_endpoint` | [Sec §4.1.1] "The authorization server MAY instruct the Consumer to use the token endpoint URL" |
| `iat` | Current time | [Sec §4.1.1] |
| `exp` | Current time + short TTL (e.g. 300s) | [Sec §4.1.1] |
| `jti` | Unique ID (UUID) | [Sec §4.1.1] "Unique token identifier" |

**JOSE header**: `{"typ": "JWT", "alg": "RS256", "kid": "<key_id>"}`.
The `kid` identifies the signing key per [Sec §6.3]. The algorithm MUST be
RS256 per [Sec §6.1].

**Token request parameters** [Sec §4.1]:

| Parameter | Value |
|---|---|
| `grant_type` | `client_credentials` |
| `client_assertion_type` | `urn:ietf:params:oauth:client-assertion-type:jwt-bearer` |
| `client_assertion` | The signed JWT |
| `scope` | Space-separated list of requested scopes |

**Token response** (RFC 6749 §5.1):
- `access_token` — REQUIRED
- `token_type` — REQUIRED (case-insensitive per RFC 6750 §4;
  accept any casing of `"bearer"`)
- `expires_in` — RECOMMENDED; if absent, default to 3600s
- `scope` — OPTIONAL if identical to what was requested; if absent,
  fall back to the requested scopes

**Error response**: Any non-2xx response is treated as an error.
If the body is JSON with an `error` field, parse it per RFC 6749 §5.2
(with optional `error_description` and `error_uri`). Otherwise,
include the raw status code and body in `TokenRequestFailed`.

```elixir
defmodule Ltix.OAuth.AccessToken do
  defstruct [:access_token, :token_type, :granted_scopes, :expires_at]

  @type t :: %__MODULE__{
    access_token: String.t(),
    token_type: String.t(),
    granted_scopes: [String.t()],   # raw scope strings from OAuth response
    expires_at: DateTime.t()
  }
end
```

`AccessToken` is public so host apps can cache it for token reuse across
contexts. See `Client.from_access_token/2` (§3.2) for how to build a
Client from a cached token.

The response's `expires_in` (seconds) is converted to an absolute
`DateTime` at parse time: `DateTime.add(DateTime.utc_now(), expires_in)`.

**Configuration**: The tool's private key comes from `registration.tool_jwk`
(see §1.2 below).

**Tests**:
- Valid token request builds correct JWT assertion [Sec §4.1.1]
- JWT assertion includes all required claims (iss, sub, aud, iat, exp, jti)
- JOSE header includes `kid` and `alg: RS256` [Sec §6.1, §6.3]
- Token request uses correct Content-Type (`application/x-www-form-urlencoded`)
- Successful response parsed into `%AccessToken{}`
- `expires_at` is a `DateTime` computed from response `expires_in` + `DateTime.utc_now()`
- Missing `expires_in` defaults to 3600s
- Missing `scope` in response falls back to requested scopes [RFC 6749 §5.1]
- `token_type` accepted case-insensitively [RFC 6749 §5.1]
- Error response with RFC 6749 JSON (`error`/`error_description`) parsed into `TokenRequestFailed`
- Non-JSON error response (e.g., HTML, plain text) still produces `TokenRequestFailed` with raw body
- Non-2xx status codes other than 400 (401, 403, 500) handled as errors
- Missing `token_endpoint` on registration returns clear error
- Scope parameter correctly space-separated

### 1.2 Tool JWK on Registration (Required)

**Spec basis**: [Sec §7.2] "A system *SHOULD NOT* use a single key pair to
secure message signing for more than one system. Therefore, systems *SHOULD*
be capable of obtaining and using many key pairs." Keys are exchanged
during registration as an out-of-band process [Sec §6].

The tool's private key belongs on `Registration` as a **required field**.
Each registration represents one tool-platform relationship, and the spec
says keys SHOULD be per-relationship. Making it required means every
Registration is Advantage-ready from day one: no surprise failures months
later when someone adds NRPS or AGS.

The exact JWK that's used is opaque to Ltix, but the host application is
expected to follow best practices for key generation and storage.

**Changes to `Ltix.Registration`**:

```elixir
defstruct [
  :issuer,
  :client_id,
  :auth_endpoint,
  :jwks_uri,
  :token_endpoint,
  :tool_jwk          # NEW — required, tool's private JWK for this registration
]
```

**Validation in `Registration.new/1`**:
- `tool_jwk` MUST be a `JOSE.JWK.t()` (or map convertible to one)
- `token_endpoint` stays optional (only needed for Advantage service calls,
  but the key is always present so the registration is ready if/when
  `token_endpoint` is added later)

**Why always required**:
- Pit of success: you can't create a Registration that's missing key
  material. When you later want Advantage services, the key is already there.
- Spec-aligned: keys are per-registration, exchanged during setup [Sec §7.2]
- Generating an RSA key pair is trivial — not a burden on the host app
- The host app still decides storage (env vars, Vault, DB) — they just
  provide the key when constructing the Registration struct

**Impact on existing code**:
- `Registration.new/1` gains a `tool_jwk` validation
- `Ltix.Test.setup_platform!/1` already generates a key pair — just needs
  to include it in the Registration
- All existing tests that construct Registrations will need to add `tool_jwk`
- OPPORTUNITY: Update existing tests to use a shared helper for building test Registrations (e.g., `Ltix.Test.build_registration/1`) to reduce duplication and ensure future-proofing against registration changes.
- `StorageAdapter` is unchanged — no new callbacks

---

## 2. Memberships Data Structures

### 2.1 `Ltix.MembershipsService.Member` — Individual Membership

**Spec basis**: [NRPS §2.1] Membership container media type;
[NRPS §2.2] Sharing of personal data.

A struct representing a single member in the roster response.

> [NRPS §2.2]: "At a minimum, the member must contain: `user_id` (as
> communicated in the LtiResourceLinkRequest under `sub`) and `roles` (an
> array of roles with values as defined in [LTI-13])."

```elixir
defstruct [
  :user_id,              # REQUIRED [NRPS §2.2] — matches `sub` in launch JWT
  :status,               # :active | :inactive | :deleted (mapped from "Active", "Inactive", "Deleted") [NRPS §2.3]
  :name,                 # Optional PII — requires platform consent [NRPS §2.2]
  :picture,              # Optional PII
  :given_name,           # Optional PII
  :family_name,          # Optional PII
  :middle_name,          # Optional PII
  :email,                # Optional PII
  :lis_person_sourcedid, # Optional SIS identifier
  :lti11_legacy_user_id, # Optional LTI 1.1 backward compat
  :message,              # Optional [LaunchClaims.t()], present for resource link queries [NRPS §3.2]
  roles: []              # REQUIRED [NRPS §2.2] — parsed into %Role{} structs
]
```

**Roles parsing**: Reuse the existing `Ltix.LaunchClaims.Role.parse_all/1`
to convert role URI strings into `%Role{}` structs, consistent with how
launch claims handle roles.

**Status** [NRPS §2.3]:
> "Each membership has a status of either `Active` or `Inactive`. If the
> status is not specified then a status of `Active` must be assumed."
>
> "When reporting differences a membership may have a status of `Deleted`."

**Decision**: Use an Elixir atom for `status` (`:active`, `:inactive`, `:deleted`) for easier pattern matching in client code.

**Tests**:
- Parse member with all fields populated
- Parse member with only required fields (user_id, roles)
- Missing `user_id` returns error
- Missing `roles` returns error
- Status defaults to `:active` when not specified [NRPS §2.3]
- Roles parsed into `%Role{}` structs (reuses existing parser)
- Unrecognized role URIs preserved (via `Role.parse_all/1` return tuple)
- Optional PII fields default to `nil` [NRPS §2.2]

### 2.2 `Ltix.MembershipsService.MembershipContainer` — Response Envelope

**Spec basis**: [NRPS §2.1] Membership container media type.

The top-level response structure from a membership query.

```elixir
defstruct [
  :id,               # URL of this membership listing
  :context,          # Context info (id required, label/title optional)
  members: []        # List of %Member{}
]

# Delegates to `members` — lets callers pipe directly into Enum/Stream
defimpl Enumerable, for: __MODULE__ do
  ...
end
```

Implements `Enumerable`, delegating to `.members`. This lets callers
pipe the container directly into `Enum`/`Stream` functions while still
having access to `.context` on the struct:

```elixir
{:ok, roster} = Ltix.MembershipsService.get_members(client)

# Metadata access
roster.context
# Iterate members directly
roster
|> Enum.filter(&(&1.status == :active))
|> Enum.map(& &1.email)

Enum.count(roster)
```

> [NRPS §2.2]: "A context parameter must be present that must contain:
> `id`: id of the context."

**Context**: Reuse `Ltix.LaunchClaims.Context.from_json/1` for parsing the
context block, which already enforces that `id` is required.

**Multi-page merge strategy** (for `get_members/2` eager fetch):
- `members` — concatenated across all pages
- `context` — taken from the first page (constant across pages)
- `id` — taken from the first page
- `next_url` is NOT exposed on the struct — it's an internal pagination
  detail, not a user concern

**Tests**:
- Parse full membership container response
- Context `id` is required [NRPS §2.2]
- Members list parsed into `%Member{}` structs
- Empty members list is valid

---

## 3. OAuth Client (`Ltix.OAuth`)

The OAuth client is shared infrastructure for all LTI Advantage services. It
acquires and holds an access token, tracks which scopes were granted, and
provides explicit refresh. Each service module (e.g., `Ltix.MembershipsService`)
implements the `AdvantageService` behaviour and provides a shorthand
`authenticate` that delegates to `Ltix.OAuth`.

### 3.1 `Ltix.AdvantageService` — Service Behaviour

Each Advantage service module implements this behaviour. `Ltix.OAuth`
calls these callbacks generically — it has no hardcoded knowledge of
specific services. This makes the system extensible to proprietary
platform extensions and experimental specs without changing Ltix.

```elixir
defmodule Ltix.AdvantageService do
  @doc "Extract the service's endpoint from launch claims."
  @callback endpoint_from_claims(LaunchClaims.t()) :: {:ok, term()} | :error

  @doc "Validate that the given value is a valid endpoint for this service."
  @callback validate_endpoint(term()) :: :ok | {:error, Ltix.Error.t()}

  @doc "Return the OAuth scope URIs available from this endpoint."
  @callback scopes(term()) :: [String.t()]
end
```

- `endpoint_from_claims/1` — extracts the service's endpoint struct from
  launch claims (e.g., `%MembershipsEndpoint{}` from the NRPS claim)
- `validate_endpoint/1` — confirms the value is the right struct type.
  Returns `{:error, %InvalidEndpoint{}}` on failure. Called by
  `OAuth.authenticate/2` at authenticate time to fail fast.
- `scopes/1` — returns the OAuth scope URIs that should be
  requested for this endpoint. For NRPS, this is always one scope (implied
  by the endpoint's presence). For AGS, the scopes come from the endpoint
  struct's `scope` field.

**Implementations**:

```elixir
# In Ltix.MembershipsService:
@behaviour Ltix.AdvantageService

@nrps_scope "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"

@impl true
def endpoint_from_claims(%LaunchClaims{memberships_endpoint: %MembershipsEndpoint{} = ep}),
  do: {:ok, ep}
def endpoint_from_claims(_), do: :error

@impl true
def validate_endpoint(%MembershipsEndpoint{}), do: :ok
def validate_endpoint(_), do: {:error, InvalidEndpoint.exception(service: __MODULE__)}

@impl true
def scopes(%MembershipsEndpoint{}), do: [@nrps_scope]

# Host app's proprietary extension — works with Ltix.OAuth out of the box:
defmodule MyApp.LTI.ProctorService do
  @behaviour Ltix.AdvantageService
  @impl true
  def endpoint_from_claims(_), do: :error  # no standard claim
  @impl true
  def validate_endpoint(%MyApp.LTI.ProctorEndpoint{}), do: :ok
  def validate_endpoint(_), do: {:error, InvalidEndpoint.exception(service: __MODULE__)}
  @impl true
  def scopes(%MyApp.LTI.ProctorEndpoint{}),
    do: ["https://example.com/scope/proctoring"]
end
```

### 3.2 `Ltix.OAuth.Client` — Authenticated Client

A public struct representing an authenticated OAuth session. Users hold
this, pass it to service functions, check expiry, and refresh it.

```elixir
defmodule Ltix.OAuth.Client do
  defstruct [:access_token, :expires_at, :scopes, :registration, :req_options,
             endpoints: %{}]

  @type t :: %__MODULE__{
    access_token: String.t(),
    expires_at: DateTime.t(),
    scopes: MapSet.t(String.t()),          # granted OAuth scope URI strings
    registration: Registration.t(),
    req_options: keyword(),
    endpoints: %{module() => term()}       # service module => endpoint struct
  }
end
```

**Predicates** (on `Client`, not `OAuth`):

```elixir
@doc "Check whether the client's token has expired (with 60s buffer)."
@spec expired?(t()) :: boolean()
def expired?(%__MODULE__{} = client)

@doc "Check whether the client was granted a specific scope."
@spec has_scope?(t(), String.t()) :: boolean()
def has_scope?(%__MODULE__{} = client, scope)

@doc "Require a specific scope, returning a ScopeMismatch error if missing."
@spec require_scope(t(), String.t()) :: :ok | {:error, Splode.Error.t()}
def require_scope(%__MODULE__{} = client, scope)

@doc "Require any one of the given scopes (for AGS functions that accept read or read/write)."
@spec require_any_scope(t(), [String.t()]) :: :ok | {:error, Splode.Error.t()}
def require_any_scope(%__MODULE__{} = client, scopes)

@doc """
Re-acquire the token using the stored registration and endpoints.

Re-derives requested scopes from endpoints via `scopes/1`, not from
previously granted scopes, so a transient partial grant doesn't
become permanent.
"""
@spec refresh(t()) :: {:ok, t()} | {:error, Exception.t()}
def refresh(%__MODULE__{} = client)
```

**Constructors** (for token reuse across contexts):

Endpoints are per-context (per-course, per-launch). The token is
per-registration. These constructors let the host app reuse a cached
token with different endpoints, avoiding redundant OAuth requests.

Both constructors validate endpoints (`validate_endpoint/1`), derive
required scopes (`scopes/1`), and verify the token's granted scopes
cover them — failing with `%ScopeMismatch{}` if not.

```elixir
@spec from_access_token(AccessToken.t(), keyword()) ::
  {:ok, t()} | {:error, Exception.t()}
def from_access_token(%AccessToken{} = token, opts)
# opts: :registration (required for refresh), :endpoints, :req_options

@spec with_endpoints(t(), %{module() => term()}) ::
  {:ok, t()} | {:error, Exception.t()}
def with_endpoints(%__MODULE__{} = client, endpoints)
```

### 3.3 Bang Variants

All functions that return `{:ok, result} | {:error, reason}` also have
bang (`!`) variants that return the unwrapped result or raise. This
applies across `OAuth`, `Client`, and service modules:

- `OAuth.authenticate!/2`
- `Client.refresh!/1`, `Client.from_access_token!/2`, `Client.with_endpoints!/2`
- `MembershipsService.authenticate!/2`, `MembershipsService.get_members!/2`

Bang variants are not listed separately in each section below — assume
they exist for every `{:ok, _} | {:error, _}` function.

### 3.4 `Ltix.OAuth` — Authentication Entry Point

**Spec basis**: [Sec §4.1] OAuth 2.0 Client Credentials grant. The spec
allows requesting multiple scopes in a single token request (space-separated),
and the response confirms the granted subset.

```elixir
# Single service from launch context (shorthand)
{:ok, client} = Ltix.MembershipsService.authenticate(launch_context)
{:ok, roster} = Ltix.MembershipsService.get_members(client)

# Single service from registration
{:ok, client} = Ltix.MembershipsService.authenticate(registration,
  endpoint: MembershipsEndpoint.new("https://...")
)

# Multiple services from registration
{:ok, client} = Ltix.OAuth.authenticate(registration,
  endpoints: %{
    Ltix.MembershipsService => MembershipsEndpoint.new("https://..."),
    Ltix.AGS => AgsEndpoint.new(line_items: "...", scope: [...])
  }
)

# Reuse token across contexts (endpoints are per-course, tokens are per-registration)
{:ok, client_b} = Client.with_endpoints(client, %{
  Ltix.MembershipsService => course_b_endpoint
})

# Or from a cached AccessToken (e.g., persisted between requests)
{:ok, client} = Client.from_access_token(cached_token,
  registration: registration,
  endpoints: %{Ltix.MembershipsService => endpoint}
)

# Check expiry and refresh explicitly
client = if Client.expired?(client), do: Client.refresh!(client), else: client
```

**`OAuth.authenticate/2` flow**:

1. For each entry in `endpoints:`, call `module.validate_endpoint(value)` —
   fail fast with `%InvalidEndpoint{}` if any are wrong
2. For each entry, call `module.scopes(value)` — collect
   all OAuth scope URI strings
3. Delegate to `ClientCredentials` to request a token with the union of
   all scopes (space-separated)
4. `ClientCredentials` returns `%AccessToken{}` with raw `granted_scopes`
5. Build `%Client{}` with granted scopes as `MapSet.t(String.t())` +
   validated endpoints

**Functions**:

```elixir
@authenticate_schema NimbleOptions.new!([
  endpoints: [
    type: {:map, :atom, :any},
    required: true,
    doc: "Map of service modules to endpoint structs (e.g., `%{Ltix.MembershipsService => endpoint}`)."
  ],
  req_options: [
    type: :keyword_list,
    default: [],
    doc: "Options passed through to `Req.request/2`."
  ]
])

@spec authenticate(Registration.t(), keyword()) ::
  {:ok, Client.t()} | {:error, Exception.t()}
def authenticate(%Registration{} = registration, opts \\ [])
```

**Tests**:
- `authenticate/2` with single-service endpoint acquires token
- `authenticate/2` with multiple endpoints sends space-separated scope string
- Scopes derived from endpoints via `scopes/1`
- Platform grants a subset of requested scopes — only granted strings in MapSet
- Invalid endpoint returns `%InvalidEndpoint{}` at authenticate time
- `Client.refresh/1` returns new client with fresh token, same registration + endpoints
- `Client.expired?/1` returns true when within 60s buffer of `expires_at`
- `Client.has_scope?/2` returns true for granted scope string, false otherwise
- `Client.require_scope/2` returns `:ok` or `{:error, %ScopeMismatch{}}`
- `Client.from_access_token/2` builds client from cached token + validates endpoints + checks scope coverage
- `Client.from_access_token/2` fails with `ScopeMismatch` when token doesn't cover endpoint scopes
- `Client.with_endpoints/2` swaps endpoints, keeps same token, validates + checks scope coverage
- `Client.with_endpoints/2` fails with `InvalidEndpoint` on wrong struct type

---

## 4. Memberships Service Client

### 4.1 `Ltix.MembershipsService` — Public API

```elixir
# From launch context — endpoint extracted from claims automatically
{:ok, client} = Ltix.MembershipsService.authenticate(launch_context)
{:ok, roster} = Ltix.MembershipsService.get_members(client)

# From registration — caller provides endpoint
{:ok, client} = Ltix.MembershipsService.authenticate(registration,
  endpoint: MembershipsEndpoint.new("https://...")
)
{:ok, roster} = Ltix.MembershipsService.get_members(client, role: :learner)

# Multi-scope from registration
{:ok, client} = Ltix.OAuth.authenticate(registration,
  endpoints: %{
    Ltix.MembershipsService => MembershipsEndpoint.new("https://..."),
    Ltix.AGS => AgsEndpoint.new(line_items: "...", scope: [...])
  }
)
{:ok, roster} = Ltix.MembershipsService.get_members(client)

# Stream for large rosters
Ltix.MembershipsService.stream_members(client) |> Enum.each(&process/1)

# Explicit refresh
if Client.expired?(client) do
  {:ok, client} = Client.refresh(client)
end
```

#### 4.1.1 `Ltix.MembershipsService.authenticate/2` — Shorthand

**Spec basis**: [NRPS §3.6.1] LTI 1.3 integration; [Sec §4.1] OAuth 2.0
Client Credentials.

> [NRPS §3.6.1.2]: Scope for access:
> `https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly`

A convenience that pattern-matches on the first argument to support both
the launch context path and the registration path:

```elixir
@context_auth_schema NimbleOptions.new!([
  req_options: [
    type: :keyword_list,
    default: [],
    doc: "Options passed through to `Req.request/2`."
  ]
])

@registration_auth_schema NimbleOptions.new!([
  endpoint: [
    type: {:struct, MembershipsEndpoint},
    required: true,
    doc: "MembershipsEndpoint struct for the service endpoint."
  ],
  req_options: [
    type: :keyword_list,
    default: [],
    doc: "Options passed through to `Req.request/2`."
  ]
])

# From launch context — extracts endpoint from claims, validates NRPS claim
@spec authenticate(LaunchContext.t(), keyword()) ::
  {:ok, Client.t()} | {:error, Exception.t()}
def authenticate(%LaunchContext{} = context, opts \\ [])

# From registration — caller provides endpoint
@spec authenticate(Registration.t(), keyword()) ::
  {:ok, Client.t()} | {:error, Exception.t()}
def authenticate(%Registration{} = registration, opts \\ [])
```

Both paths delegate to `Ltix.OAuth.authenticate/2` with the endpoint
stored in `client.endpoints[Ltix.MembershipsService]`. Service query functions
(`get_members/2`, `stream_members/2`) look up the endpoint from the
client automatically.

#### 4.1.2 `Ltix.MembershipsService.get_members/2` — Eager Fetch

Delegates to `stream_members/2`, consumes the stream, and wraps the
result in a `%MembershipContainer{}`.

```elixir
@query_schema [
  endpoint: [
    type: {:struct, MembershipsEndpoint},
    doc: "Override the endpoint stored on the client."
  ],
  role: [
    type: {:or, [:atom, :string, {:struct, Role}]},
    doc: """
    Filter by role. Accepts a role atom (e.g., `:learner`), URI string, `%Role{}` struct, or
    short name string (e.g., `"Learner"`). Atoms are resolved
    to URI strings via `Role.to_uri/1`.
    """ # [NRPS §2.4.1]
  ],
  resource_link_id: [
    type: :string,
    doc: "Query resource link membership." # [NRPS §3]
  ],
  limit: [
    type: :pos_integer,
    doc: "Page size hint. The platform may return more or fewer than requested." # [NRPS §2.4.2]
  ]
]

@get_members_schema NimbleOptions.new!(@query_schema ++ [
  max_members: [
    type: {:or, [:pos_integer, {:in, [:infinity]}]},
    default: 10_000,
    doc: """
    Safety limit for eager fetch. Returns a `RosterTooLarge` error if exceeded,
    guiding callers toward `stream_members/2`. Set to `:infinity` to disable.
    """
  ]
])

@stream_members_schema NimbleOptions.new!(@query_schema)

@spec get_members(Client.t(), keyword()) ::
  {:ok, MembershipContainer.t()} | {:error, Exception.t()}
def get_members(client, opts \\ [])
```

**Sketch implementation**:

```elixir
def get_members(%Client{} = client, opts \\ []) do
  with {:ok, opts} <- NimbleOptions.validate(opts, @get_members_schema),
       max = Keyword.get(opts, :max_members),
       stream_opts = Keyword.delete(opts, :max_members),
       {:ok, stream} <- stream_members(client, stream_opts) do
    members =
      stream
      |> Stream.take(max + 1)
      |> Enum.to_list()

    if length(members) > max do
      {:error, RosterTooLarge.exception(count: length(members), max: max)}
    else
      {:ok, build_container(members)}
    end
  end
end
```

#### 4.1.3 `Ltix.MembershipsService.stream_members/2` — Lazy Stream

The lazy counterpart to `get_members/2`. Fetches the first page eagerly
to catch auth/scope/HTTP errors upfront, then returns a lazy stream for
subsequent pages.

```elixir
@spec stream_members(Client.t(), keyword()) ::
  {:ok, Enumerable.t()} | {:error, Exception.t()}
def stream_members(client, opts \\ [])
```

Both `get_members/2` and `stream_members/2` share the same base query
options (`@query_schema`). `get_members/2` adds `:max_members`.

Use `stream_members/2` for large rosters where you want to process
members incrementally or stop early.

**Sketch implementation** (delegates to `Ltix.Pagination`):

```elixir
def stream_members(%Client{} = client, opts \\ []) do
  with {:ok, opts} <- NimbleOptions.validate(opts, @stream_members_schema),
       :ok <- Client.require_scope(client, @nrps_scope) do
    url = endpoint_url(client, opts)
    headers = [{"accept", @media_type}, {"authorization", "Bearer #{client.access_token}"}]

    Pagination.stream(url, headers,
      parse: &parse_members/1,
      params: query_params(opts),
      req_options: client.req_options
    )
    # => {:ok, stream} | {:error, reason}
  end
end
```

#### 4.1.4 Request Construction

**Headers** [NRPS §2.4]:
- `Accept: application/vnd.ims.lti-nrps.v2.membershipcontainer+json`
- `Authorization: Bearer <access_token>` [Sec §4.1]

**Response validation**:
- Verify the response `Content-Type` media type matches the expected
  NRPS media type. The check parses the header value and compares only
  the media type portion, ignoring parameters (e.g., `; charset=utf-8`)
  and comparing case-insensitively, per standard HTTP semantics.

**Query parameters**:
- `role` — URL-encoded role URI [NRPS §2.4.1]
  > "A query parameter of `role=Learner` will filter the memberships to just
  > those which have a Learner role."
  > Short names follow the same rule as the `roles` parameter in launch messages.
- `limit` — integer [NRPS §2.4.2]
  > "The Tool may specify a maximum number of members to be returned."
  > The platform may return more or fewer than requested.
- `rlid` — resource link ID [NRPS §3]
  > "The tool needs to append an additional query parameter `rlid` with a
  > value of the Resource Link id."

#### 4.1.5 Pagination [NRPS §2.4.2]

> "If the response from a Platform does not comprise all of the members a
> `rel="next"` header link will be included to indicate how to request the
> next set of members. The absence of a `rel="next"` header link indicates
> that no more members are available."

Pagination uses the shared `Ltix.Pagination` module (see §6.1). The
`rel="next"` URL is opaque and used as-is.

- `get_members/2` eagerly follows all pages, accumulating members
- `stream_members/2` fetches the first page eagerly (for error checking),
  then lazily follows subsequent pages via `Stream.resource/3`
- Both use the client's token for all pages

#### 4.1.6 Differences URL [NRPS §2.4.3] — Not Implemented

> "A response by the Names and Role Provisioning Services may include a
> `rel="differences"` header link."

As of 2026, no major LMS implements `rel="differences"` — not Canvas,
Moodle, Brightspace, Blackboard, Sakai, Open edX, nor the IMS Reference
Implementation. It's not tested in conformance certification. The feature
requires non-trivial platform-side infrastructure (tracking membership
change history, generating timestamped URLs, producing `Deleted` status
entries) for a MAY requirement, creating a chicken-and-egg adoption
problem.

**Not implemented.** No `differences_url` field on `MembershipContainer`,
no `rel="differences"` parsing. If a platform ever ships this, it can be
added without breaking changes. Tools that need incremental roster sync
today can periodically fetch the full membership list and diff locally.

#### 4.1.7 Resource Link Membership [NRPS §3]

> [NRPS §3]: "Optionally, a platform may offer a Resource Link level
> membership service."

> [NRPS §3.1]: "A platform must deny access to this request if the Resource
> Link is not owned by the Tool making the request or the resource link is
> not present in the Context."

> [NRPS §3.2]: "When queried in the context of a Resource Link, an
> additional message section is added per member."

> [NRPS §3.3]: "A platform may return a subset of the context memberships,
> reflecting which members can actually access the Resource Link."

The `message` field on `%Member{}` holds per-member LTI message parameters
when querying by resource link. This includes custom parameters and
Basic Outcome claims [NRPS §3.4]. Substitution parameters [NRPS §3.5] are
resolved platform-side and arrive already substituted.

**Tests** (§4.1 `Ltix.MembershipsService`):
- `authenticate/2` from LaunchContext acquires token with correct scope [NRPS §3.6.1]
- `authenticate/2` from LaunchContext errors when no NRPS claim in launch
- `authenticate/2` from Registration with `endpoint:` acquires token
- `authenticate/2` from Registration without `endpoint:` errors
- `authenticate/2` validates `service_versions` includes `"2.0"`
- `get_members/2` sends correct Accept header [NRPS §2.4]
- `get_members/2` sends correct Authorization header with Bearer token [Sec §4.1]
- `get_members/2` follows all `rel="next"` links and returns complete roster
- `get_members/2` returns error when `max_members` exceeded
- `get_members/2` looks up endpoint from `client.endpoints[Ltix.MembershipsService]`
- `get_members/2` returns `ScopeMismatch` error when client lacks NRPS scope
- `stream_members/2` lazily follows `rel="next"` links across pages
- Multiple calls on same client reuse the same token
- Expired client returns `AccessTokenExpired` error (caller must `Client.refresh/1`)
- Role filter accepts atoms, URI strings, and short names [NRPS §2.4.1]
- Resource link ID appended as `rlid` parameter [NRPS §3]
- Limit hint passed as query parameter [NRPS §2.4.2]
- Response Content-Type validated
- HTTP error responses return `{:error, reason}`
- Members parsed with roles into `%Role{}` structs
- Resource link query includes message section per member [NRPS §3.2]

---

## 5. Error Types

New Splode errors for OAuth and memberships failure modes.

### 5.1 `Ltix.Errors.Invalid.ServiceNotAvailable`

Raised when the caller attempts to use a service that was not included in
the launch claims (e.g., no NRPS claim in the JWT).

```elixir
use Splode.Error, fields: [:service, :spec_ref], class: :invalid

# spec_ref: "[NRPS §3.6.1.1] Claim for inclusion in LTI messages"
def message(%{service: service}) do
  "Service not available: #{service} — no endpoint claim in launch"
end
```

### 5.2 `Ltix.Errors.Security.AccessDenied`

Raised when the platform returns a 401 or 403 for a service request.

```elixir
use Splode.Error, fields: [:service, :status, :body, :spec_ref], class: :security

# spec_ref: "[Sec §4.1] Using OAuth 2.0 Client-Credentials Grant"
def message(%{service: service, status: status}) do
  "Access denied for #{service} (HTTP #{status})"
end
```

### 5.3 `Ltix.Errors.Invalid.TokenRequestFailed`

Raised when the OAuth token request fails. When the response is RFC 6749
§5.2 JSON, `error` and `error_description` are populated. For non-JSON
responses (HTML error pages, plain text), the raw `status` and `body` are
preserved instead.

```elixir
use Splode.Error, fields: [:error, :error_description, :status, :body, :spec_ref], class: :invalid

# spec_ref: "[Sec §4.1] OAuth 2.0 Client Credentials — error response"
def message(%{error: error}) when not is_nil(error) do
  "OAuth token request failed: #{error}"
end
def message(%{status: status}) do
  "OAuth token request failed (HTTP #{status})"
end
```

### 5.4 `Ltix.Errors.Invalid.MalformedResponse`

Raised when the platform returns a 200 but with invalid JSON or a response
body that doesn't match the expected membership container schema.

```elixir
use Splode.Error, fields: [:service, :reason, :spec_ref], class: :invalid

# spec_ref: "[NRPS §2.1] Membership container media type"
def message(%{service: service, reason: reason}) do
  "Malformed response from #{service}: #{reason}"
end
```

### 5.5 `Ltix.Errors.Invalid.RosterTooLarge`

Raised when `get_members/2` exceeds the `:max_members` safety limit.
Guides the user toward `stream_members/2`.

```elixir
use Splode.Error, fields: [:count, :max, :spec_ref], class: :invalid

def message(%{count: count, max: max}) do
  "Roster exceeds max_members limit (#{count} > #{max}); use stream_members/2 for large rosters"
end
```

### 5.6 `Ltix.Errors.Security.AccessTokenExpired`

Raised when a service request is attempted with an expired OAuth access
token. Guides the caller to use `Client.refresh/1`.

Named `AccessTokenExpired` to distinguish from the existing
`Ltix.Errors.Security.TokenExpired`, which covers JWT ID token `exp`
claim validation during the launch flow.

```elixir
use Splode.Error, fields: [:expires_at, :spec_ref], class: :security

# spec_ref: "[Sec §7.1] Access Token Management"
def message(%{expires_at: expires_at}) do
  "OAuth access token expired at #{expires_at}; call Client.refresh/1 to re-acquire"
end
```

### 5.7 `Ltix.Errors.Invalid.ScopeMismatch`

Raised when a service function requires a scope that wasn't granted.
Returned by `Client.require_scope/2`.

```elixir
use Splode.Error, fields: [:scope, :granted_scopes, :spec_ref], class: :invalid

# spec_ref: "[Sec §4.1] OAuth 2.0 Client Credentials — scopes"
def message(%{scope: scope}) do
  "Client is not authorized for scope #{scope}; authenticate with the correct endpoint"
end
```

### 5.8 `Ltix.Errors.Invalid.InvalidEndpoint`

Raised when `OAuth.authenticate/2` receives an endpoint value that fails
`validate_endpoint/1`. Catches type errors at authenticate time rather
than at the point of use.

```elixir
use Splode.Error, fields: [:service, :spec_ref], class: :invalid

# spec_ref: "[Core §6.1] Services exposed as additional claims"
def message(%{service: service}) do
  "Invalid endpoint for #{inspect(service)}"
end
```

---

## 6. Pagination (`Ltix.Pagination`)

Shared infrastructure for following `rel="next"` Link headers across
paginated LTI Advantage responses. NRPS, AGS, and Course Groups all use
the same RFC 8288 pagination pattern: an optional `limit` query parameter
and `rel="next"` Link headers.

### 6.1 Link Header Parsing

Parse RFC 8288 `Link` headers, handling multiple relations in a single
header (comma-separated). Extracts the `rel="next"` URL.

```
Link: <https://lms.example.com/sections/2923/memberships?p=2>; rel="next"
```

### 6.2 `Ltix.Pagination.stream/3` — Lazy Paginated Stream

Fetches the first page eagerly to surface auth/HTTP errors immediately,
then lazily follows `rel="next"` links via `Stream.resource/3`.

```elixir
defmodule Ltix.Pagination do
  @doc """
  Fetch a paginated endpoint as a lazy stream.

  Fetches the first page eagerly. If it succeeds, returns `{:ok, stream}`
  where subsequent pages are fetched lazily as the stream is consumed.
  If the first page fails, returns `{:error, reason}` immediately.

  The `parse` callback receives the response body (decoded JSON) and
  returns a list of parsed items for that page.

  Errors on subsequent pages raise during stream consumption.
  """
  @spec stream(String.t(), [{String.t(), String.t()}], keyword()) ::
    {:ok, Enumerable.t()} | {:error, Exception.t()}
  def stream(url, headers, opts \\ [])

  # Sketch implementation:
  def stream(url, headers, opts) do
    parse = Keyword.fetch!(opts, :parse)
    params = Keyword.get(opts, :params, %{})
    req_options = Keyword.get(opts, :req_options, [])

    # Eager first page — surfaces auth/scope/HTTP errors immediately
    case fetch_page(url, headers, params, req_options) do
      {:ok, %{items: first_items, next_url: next_url}} ->
        stream =
          Stream.resource(
            # Start: emit the already-fetched first page
            fn -> {first_items, next_url} end,

            # Next: emit current items, fetch next page if available
            fn
              {[], nil} ->
                {:halt, :done}

              {[], next_url} ->
                # Fetch next page — errors here raise during consumption
                case fetch_page(next_url, headers, %{}, req_options) do
                  {:ok, %{items: items, next_url: next_next}} ->
                    emit_items(items, next_next, parse)

                  {:error, reason} ->
                    raise reason
                end

              {items, next_url} ->
                emit_items(items, next_url, parse)
            end,

            # Cleanup
            fn _ -> :ok end
          )

        {:ok, stream}

      {:error, _} = error ->
        error
    end
  end
end
```


**Tests**:
- Link header with `rel="next"` parsed correctly
- Multiple link relations in one header parsed correctly
- Missing `rel="next"` signals last page
- `stream/3` returns `{:ok, stream}` on first page success
- `stream/3` returns `{:error, reason}` on first page failure
- Stream lazily fetches subsequent pages
- Stream terminates when no `rel="next"` present

---

## 7. JWK Generation (`Ltix.JWK`)

**Spec basis**: [Sec §6.1] RSA key; [Sec §6.3] Key set URL (kid);
[Sec §6.4] Issuer public key rotation; [Sec §7.2] Key distribution.

A small utility module for generating spec-compliant JWKs and building
JWKS documents. Not NRPS-specific — any Advantage service needs key
material, and the JWK management guide (§10 Phase 4) references this.

```elixir
defmodule Ltix.JWK do
  @generate_key_pair_schema NimbleOptions.new!([
    key_size: [
      type: {:custom, __MODULE__, :validate_key_size, []},
      default: 2048,
      doc: "RSA key size in bits (minimum 2048)."
    ]
  ])

  @doc """
  Generate an RSA key pair for LTI tool authentication.

  Returns `{private_jwk, public_jwk}`. The private key is suitable for
  `registration.tool_jwk`. The public key goes on your JWKS endpoint.

  ## Options

  #{NimbleOptions.docs(@generate_key_pair_schema)}

  ## Examples

      {private, public} = Ltix.JWK.generate_key_pair()
      {private, public} = Ltix.JWK.generate_key_pair(key_size: 4096)
  """
  @spec generate_key_pair(keyword()) :: {JOSE.JWK.t(), JOSE.JWK.t()}
  def generate_key_pair(opts \\ [])

  @doc """
  Build a JWKS (JSON Web Key Set) map from a list of public JWKs.

  Useful for serving your tool's JWKS endpoint. Include multiple keys
  during rotation so platforms can verify with either key.

      jwks = Ltix.JWK.to_jwks([current_public, previous_public])
      # => %{"keys" => [%{"kty" => "RSA", "kid" => "...", ...}, ...]}
  """
  @spec to_jwks([JOSE.JWK.t()]) :: map()
  def to_jwks(public_keys)

  @doc false
  def validate_key_size(size) when is_integer(size) and size >= 2048, do: {:ok, size}
  def validate_key_size(_), do: {:error, "must be an integer >= 2048"}
end
```

**Generated keys include**:
- `kty: RSA` — the only key type allowed [Sec §6.1]
- `alg: RS256` — the required algorithm [Sec §6.1]
- `use: sig` — signing key
- `kid: <unique>` — 16-byte URL-safe base64 identifier [Sec §6.3]

**Tests**:
- Default generates 2048-bit RSA key pair
- Custom key size (e.g., 4096) works
- Key size < 2048 raises `ArgumentError`
- Private key contains RSA private material (d, p, q, etc.)
- Public key contains only public material (n, e)
- Both keys share the same `kid`
- Keys include `alg: RS256` and `use: sig`
- `to_jwks/1` returns valid JWKS map with `"keys"` array
- `to_jwks/1` with multiple keys includes all of them
- `to_jwks/1` only includes public material (no private key leakage)

---

## 8. Directory Structure (New Files)

```
lib/
  ltix/
    jwk.ex                      # JWK generation + JWKS builder
    pagination.ex               # Shared paginated fetch (stream + eager) via rel="next"
    advantage_service.ex        # Behaviour: endpoint_from_claims, validate_endpoint, scopes
    oauth.ex                    # Public API: authenticate/2
    oauth/
      client.ex                 # %Client{} struct (public) + expired?/1, has_scope?/2, require_scope/2
      client_credentials.ex     # OAuth 2.0 client credentials grant [Sec §4.1]
      access_token.ex           # %AccessToken{} struct (public, cacheable)
    memberships_service.ex      # Public API: authenticate/2, get_members/2, stream_members/2
    memberships_service/
      member.ex                 # %Member{} struct + from_json/1
      membership_container.ex   # %MembershipContainer{} struct + from_json/2
    errors/
      invalid/
        service_not_available.ex
        token_request_failed.ex
        malformed_response.ex
        roster_too_large.ex
        scope_mismatch.ex
        invalid_endpoint.ex
      security/
        access_denied.ex
        access_token_expired.ex
test/
  ltix/
    jwk_test.exs                  # JWK generation + JWKS builder
    pagination_test.exs           # Link header parsing, stream
    oauth_test.exs                # OAuth.authenticate
    oauth/
      client_test.exs             # Client predicates, refresh, from_access_token, with_endpoints
      client_credentials_test.exs
    memberships_service_test.exs  # authenticate, get_members, stream_members
    memberships_service/
      member_test.exs
      membership_container_test.exs
```

---

## 9. Renames

The existing `NrpsEndpoint` is renamed to `MembershipsEndpoint` throughout,
and the claim field on `LaunchClaims` is renamed from `nrps_endpoint` to
`memberships_endpoint`. This aligns the naming with the public module
(`Ltix.MembershipsService`) and avoids exposing the niche "NRPS" acronym.

**Changes**:
- `lib/ltix/launch_claims/nrps_endpoint.ex` → `memberships_endpoint.ex`
  (module `Ltix.LaunchClaims.MembershipsEndpoint`)
- `lib/ltix/launch_claims.ex` — field rename: `nrps_endpoint` → `memberships_endpoint`
- `mix.exs` — doc group entry rename
- Tests referencing `nrps_endpoint`
- Add `MembershipsEndpoint.new/1` constructor — accepts a URL string,
  returns a `%MembershipsEndpoint{}`. Used by the registration path
  (e.g., `MembershipsEndpoint.new("https://lms.example.com/memberships")`).
  The existing `from_json/1` remains for parsing launch claims.

---

## 10. Implementation Order

Dependencies flow top-down. Each step builds on the previous. Test helpers
are integrated into each phase rather than deferred — each phase should
leave the library in a working, testable state.

### Phase 0: Foundation + Renames

1. **`Ltix.JWK`** — `generate_key_pair/1` + `to_jwks/1`
   - No dependencies beyond JOSE (already a dep)
   - Provides the key generation that `Registration` and guides reference
2. **Rename `NrpsEndpoint` → `MembershipsEndpoint`** — module, field, tests
3. **Add `tool_jwk` to `Registration`** — new required field + validation
   - Update `Registration.new/1` validation
   - Update `Ltix.Test.setup_platform!/1` to use `Ltix.JWK.generate_key_pair/0`
     instead of inline JOSE calls
   - Fix all existing tests that construct Registrations
   - Update guides: `concepts.md`, `getting-started.md`,
     `storage-adapters.md`, `cookbooks/testing-lti-launches.md`

**Acceptance criteria**:
- [X] `generate_key_pair/1` produces RSA keys with `alg: RS256` [Sec §6.1]
- [X] Generated JWKs include `n`, `e`, `kty`, `use`, and `kid` [Sec §6.2, §6.3]
- [X] Each call generates a unique `kid` [Sec §6.3]
- [X] `to_jwks/1` strips private material — output contains only public
  fields [Sec §6]
- [X] `to_jwks/1` accepts multiple keys (supports rotation overlap) [Sec §6.4]
- [X] Key sizes below 2048 bits are rejected
- [X] Tests which generate JWKs use `Ltix.JWK.generate_key_pair/1` instead of inline JOSE calls
- [X] `Registration.new/1` requires `tool_jwk` — per-registration field
  makes it easy for host apps to follow the SHOULD NOT reuse
  guidance [Sec §7.2]
- [X] All existing tests pass with the new required field

### Phase 1: Data Structures (no HTTP, no OAuth)

4. **`Ltix.MembershipsService.Member`** — struct + `from_json/1`
   - Depends on: `Ltix.LaunchClaims.Role` (already exists)
   - Pure data parsing, no side effects

5. **`Ltix.MembershipsService.MembershipContainer`** — struct + `from_json/2`
   - Depends on: `Member`, `Ltix.LaunchClaims.Context` (already exists)
   - Parses full response body + link headers

6. **Error types** — `ServiceNotAvailable`, `AccessDenied`, `TokenRequestFailed`,
   `MalformedResponse`, `RosterTooLarge`, `AccessTokenExpired`, `ScopeMismatch`,
   `InvalidEndpoint`
   - No dependencies beyond Splode (already exists)
   - Update `guides/error-handling.md` with new error types

**Acceptance criteria**:
- [X] `Member.from_json/1` returns error when `user_id` or `roles` is
  missing — these are the only MUST fields [NRPS §2.2]
- [X] `from_json/1` defaults missing `status` to `:active` [NRPS §2.3]
- [X] `from_json/1` maps status strings to atoms: `"Active"` → `:active`,
  `"Inactive"` → `:inactive`, `"Deleted"` → `:deleted` [NRPS §2.3]
- [X] `from_json/1` parses `roles` via `Role.parse_all/1` per the LTI-13
  role vocabulary [NRPS §2.2]
- [X] All PII fields default to `nil` — the platform controls what it
  shares [NRPS §2.2]
- [X] `MembershipContainer.from_json/2` returns error when `context` is
  missing or `context.id` is absent [NRPS §2.2]
- [X] All error types carry a `spec_ref` field

### Phase 2: OAuth Infrastructure

7. **`Ltix.AdvantageService`** — behaviour with three callbacks
   - `endpoint_from_claims/1`, `validate_endpoint/1`, `scopes/1`
   - No dependencies, pure contract definition

8. **`Ltix.OAuth.AccessToken`** — public, cacheable struct
   - Raw OAuth response parsing (`granted_scopes` as string list)
   - Pure data, no dependencies

9. **`Ltix.OAuth.ClientCredentials`** — JWT assertion + token request
   - Depends on: `AccessToken`, `Registration`, JOSE (already deps)
   - First module with HTTP calls (via `Req`)
   - Uses `registration.tool_jwk` for signing
   - `Ltix.Test`: stub the token endpoint via `Req.Test.stub/2`

10. **`Ltix.OAuth.Client`** — public struct, the primary user-facing type
    - Predicates: `expired?/1`, `has_scope?/2`, `require_scope/2`, `require_any_scope/2`
    - `refresh/1` — re-acquires token, re-derives scopes from endpoints
    - Constructors: `from_access_token/2`, `with_endpoints/2`
    - `scopes` as `MapSet.t(String.t())`, `endpoints` as `%{module() => term()}`

11. **`Ltix.OAuth`** — `authenticate/2`
    - Depends on: `Client`, `ClientCredentials`, `AdvantageService`
    - Calls `validate_endpoint/1` and `scopes/1` on service
      modules — no hardcoded services

12. **`Ltix.Pagination`** — `stream/3` + Link header parsing
    - Depends on: `Req` (already a dep)
    - Shared infrastructure for NRPS, AGS, Course Groups
    - `Stream.resource/3` for lazy pagination, eager first-page fetch

**Acceptance criteria**:
- [X] `ClientCredentials` sends `grant_type=client_credentials`,
  `client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer`,
  `client_assertion=<JWT>`, and `scope` [Sec §4.1, §4.1.1]
- [X] JWT assertion includes all six MUST claims: `iss`, `sub`, `aud`,
  `iat`, `exp`, `jti` [Sec §4.1.1]
- [X] `aud` set to the platform's `token_endpoint` URL [Sec §4.1.1]
- [X] `exp` set to an absolute time, short-lived (e.g., 5 min) [Sec §4.1.1]
- [X] JWT signed with the tool's private key; JOSE header includes `alg`
  (RS256) and `kid` [Sec §5.4, §6.3]
- [X] JOSE header omits `x5u`, `x5c`, `jku`, `jwk` fields [Sec §5.4]
- [X] Scopes derived from endpoints via `AdvantageService.scopes/1`,
  space-separated in the token request [Sec §4.1]
- [X] `AccessToken` parsed from response; `granted_scopes` captured from
  the response `scope` field, falling back to requested scopes when
  absent [Sec §4.1, RFC 6749 §5.1]
- [X] `token_type` accepted case-insensitively [RFC 6749 §5.1]
- [X] Missing `expires_in` defaults to 3600s
- [X] Non-2xx responses handled as errors; non-JSON bodies produce
  `TokenRequestFailed` with raw status and body
- [X] `Client.expired?/1` checks `expires_at` with buffer;
  `Client.refresh/1` re-acquires when expired [Sec §7.1.1]
- [X] `Client.require_scope/2` verifies the client was granted the needed
  scope before making service calls [Sec §4.1]
- [X] `OAuth.authenticate/2` validates endpoints via
  `validate_endpoint/1` before requesting a token
- [X] `Pagination.stream/3` parses RFC 8288 `rel="next"` Link headers
  [NRPS §2.4.2]; absence of `rel="next"` halts the stream
- [X] First page fetched eagerly (surfaces auth/HTTP errors); subsequent
  pages fetched lazily via `Stream.resource/3`

### Phase 3: Memberships Service Client

13. **`Ltix.MembershipsService`** — `authenticate/2`, `get_members/2`,
    `stream_members/2`
    - Depends on: `Ltix.OAuth`, `Ltix.Pagination`, `MembershipContainer`,
      `MembershipsEndpoint`
    - Implements `Ltix.AdvantageService` behaviour
    - `Ltix.Test`: add helpers for stubbing memberships responses:
      - `Ltix.Test.build_membership_response/1` — builds a membership
        container JSON from simple keyword options
      - `Ltix.Test.stub_memberships!/2` — stubs both the OAuth token
        endpoint and the memberships endpoint
      - Extend `Ltix.Test.setup_platform!/1` to optionally set up
        memberships stubbing

**Acceptance criteria**:
- [ ] `authenticate/2` from `LaunchContext` extracts the NRPS endpoint
  from claims and requests scope
  `contextmembership.readonly` [NRPS §3.6.1]
- [ ] `authenticate/2` from `Registration` requires caller-supplied
  `endpoint:` option
- [ ] `authenticate/2` rejects endpoints where `service_versions` does
  not include `"2.0"` [NRPS §3.6.1]
- [ ] `stream_members/2` sends `Authorization: Bearer <token>` [Sec §4.1]
  and `Accept: application/vnd.ims.lti-nrps.v2.membershipcontainer+json`
  [NRPS §2.4]
- [ ] `stream_members/2` checks `Client.require_scope/2` before making
  any HTTP request [NRPS §3.6.1]
- [ ] Role filter resolves atoms and short names to URI strings per
  the LTI-13 role vocabulary [NRPS §2.4.1]
- [ ] `limit` passed as query parameter when provided [NRPS §2.4.2]
- [ ] Resource link queries append `rlid` query parameter [NRPS §3]
- [ ] Resource link responses parsed with `message` section using
  `LaunchClaims.from_json/1` (LTI 1.3 claims format) [NRPS §3.2]
- [ ] `get_members/2` delegates to `stream_members/2`, consumes all
  pages, and wraps in `MembershipContainer`
- [ ] `get_members/2` enforces `max_members` safety limit

### Phase 4: Documentation

14. **`guides/advantage-services.md`** — Authenticating to Advantage Services
    - What Advantage Services are and how OAuth works at a high level
    - `Ltix.OAuth.authenticate/2` and the `AdvantageService` behaviour
    - `Client` lifecycle: expiry checking, refresh, token reuse
    - `from_access_token/2` and `with_endpoints/2` for caching
    - Multi-scope tokens for multiple services
    - Implementing custom/proprietary services via `AdvantageService`
    - Error handling for auth failures

15. **`guides/memberships-service.md`** — Names and Roles Provisioning
    (Memberships) Service
    - Authentication from LaunchContext (shorthand) and from Registration
    - Querying rosters: `get_members/2` (eager) and `stream_members/2` (lazy)
    - Role filtering, resource link membership
    - The `MembershipContainer` and `Member` structs
    - `max_members` safety valve and when to use streaming
    - Error handling for service-specific failures

16. **`guides/jwk-management.md`** — JWK Management
    - `Ltix.JWK.generate_key_pair/1` and `Ltix.JWK.to_jwks/1`
    - What `registration.tool_jwk` is and why it's required
    - Key generation basics (RSA 2048+ for RS256) [Sec §6.1]
    - Per-registration keys vs shared keys [Sec §7.2]
    - Key rotation: generating a new key, publishing both old and new
      via `to_jwks/1`, migrating registrations [Sec §6.4]
    - Storage options (env vars, Vault, DB) — Ltix is agnostic,
      document the extension points
    - JWKS endpoint hosting: Ltix doesn't serve one, but `to_jwks/1`
      builds the response body. Show a Plug-based endpoint example.
    - The `kid` field: how platforms match keys, why it matters [Sec §6.3]
    - Common mistakes (committing keys, using the same key across
      registrations, forgetting to include `kid`)

17. **Module docs** — `@moduledoc` on public modules
    - `Ltix.JWK`, `Ltix.Pagination`
    - `Ltix.AdvantageService`, `Ltix.OAuth`, `Ltix.OAuth.Client`,
      `Ltix.OAuth.AccessToken`
    - `Ltix.MembershipsService`, `Ltix.MembershipsService.Member`,
      `Ltix.MembershipsService.MembershipContainer`

18. **Existing docs updates**
    - `lib/ltix.ex` — add Advantage Services section to facade moduledoc
    - `mix.exs` — add `Ltix.JWK`, `Ltix.Pagination`, OAuth, and
      MembershipsService modules to doc groups, all four guides to extras

---

## 11. Test Strategy

### Unit Tests
- `Ltix.JWK` — key generation, key size validation, JWKS building (see §7)
- `Ltix.Pagination` — Link header parsing, stream (see §6)
- `Registration.new/1` — validates `tool_jwk` is present and valid
- `Member.from_json/1` — all field combinations, role parsing, status defaults
- `MembershipContainer.from_json/2` — envelope parsing, context validation, merge strategy
- `MembershipContainer` — `Enumerable` protocol implementation
- `ClientCredentials` — JWT assertion construction (including JOSE header), token parsing, error parsing
- `Client.expired?/1` — buffer logic
- `Client.has_scope?/2` / `Client.require_scope/2` — scope checking with raw scope strings

### Integration Tests (Stubbed HTTP)
- Full flow: `authenticate/2` acquires token → `get_members/2` fetches all pages → complete roster
- Token reuse: multiple calls on same client don't re-acquire
- Expired client: returns clear error, caller refreshes and retries
- Multi-scope: single token covering multiple services' scopes
- Scope mismatch: using wrong-scoped client returns `ScopeMismatch` error
- Invalid endpoint: wrong struct type returns `InvalidEndpoint` at authenticate time
- Scopes derived from endpoints: `scopes/1` drives token request
- `get_members/2` with multi-page response returns all members
- `get_members/2` with `max_members` exceeded returns `RosterTooLarge` error
- `stream_members/2` returns `{:ok, stream}` on first page success
- `stream_members/2` returns `{:error, reason}` on first page failure
- `stream_members/2` lazily fetches subsequent pages
- Role filtering (atoms, URIs, short names), resource link queries
- Error paths: platform rejects token, returns 403, returns malformed response

### Test Helpers
- `Ltix.Test.build_membership_response/1` — builds membership container
  JSON from simple keyword options (members with roles, status, PII)
- `Ltix.Test.stub_memberships!/2` — stubs both the OAuth token endpoint
  and the memberships endpoint. Handles pagination headers for
  multi-page stubs.
- `setup_platform!/1` extended to optionally set up memberships stubbing

### Stubbing Pattern
Use `Req.Test.stub/2` (same pattern as `KeySet`) for both the OAuth token
endpoint and the memberships endpoint. `Ltix.Test.setup_platform!/1`
includes `tool_jwk` in the registration automatically.

---

## 12. Resolved Questions

1. **`message` field parsing**: The `message` section in resource link
   membership responses uses "the LTI 1.3 claims format" [NRPS §3.2].
   These are the same namespaced claim keys that `LaunchClaims.from_json/1`
   already parses.

   **Decision**: Reuse `LaunchClaims.from_json/1`. The `message` field on
   `%Member{}` is `[LaunchClaims.t()]`. Each message object gets classified
   and parsed identically to launch claims: `.custom` is populated,
   `.message_type` is set, and unrecognized claims (like Basic Outcome)
   land in `.extensions`. Most OIDC fields will be `nil`, which accurately
   reflects what's present. No new parser needed.

2. **`service_versions` validation**: The `MembershipsEndpoint` struct
   already stores `service_versions`. A defensive check that `"2.0"` is
   in the list should be performed at `authenticate` time, returning a clear
   error if the platform only supports an unsupported version.

3. **`get_members/2` return type**: Returns `MembershipContainer`, which
   implements `Enumerable` (delegating to `.members`). Callers can pipe
   the result directly into `Enum`/`Stream` for member iteration, while
   still accessing `.context` on the struct.

4. **`differences_url` is not implemented**: No major LMS implements
   `rel="differences"` as of 2026. Not worth the complexity. See §4.1.6.

5. **Token refresh is explicit, not transparent**: The `%Ltix.OAuth.Client{}`
   is an immutable struct. No invisible token refresh during pagination.
   If a token expires mid-stream, the request fails with a clear error.
   The caller uses `Client.expired?/1` to check and
   `Client.refresh/1` to get a new client. Tokens last ~1 hour,
   so expiry during a single paginated fetch is rare. For long-lived
   workflows, the host app manages refresh on their own schedule.

6. **OAuth client is shared infrastructure**: `Ltix.OAuth` manages
   authentication and refresh for all Advantage services. Each service
   module implements `AdvantageService` and provides an `authenticate/2`
   shorthand. One token can cover multiple scopes. Scope checking
   happens inside service functions via `Client.require_scope/2`.

7. **`Ltix.AdvantageService` behaviour**: Three callbacks:
   `endpoint_from_claims/1`, `validate_endpoint/1`, and
   `scopes/1`. `Ltix.OAuth` calls these generically — it
   has no hardcoded knowledge of specific services. This makes the system
   extensible to proprietary platform extensions (e.g., Blackboard Ultra
   proctoring) and experimental specs without changing Ltix.

8. **`Client` is the primary user-facing struct**: Predicates
   (`expired?/1`, `has_scope?/2`, `require_scope/2`), `refresh/1`,
   and constructors (`from_access_token/2`, `with_endpoints/2`) all
   live on `Client`. `OAuth` is purely the initial authentication
   entry point.

9. **`AccessToken` is public and cacheable**: `Ltix.OAuth.AccessToken`
   holds the raw OAuth response data (`granted_scopes` as string list,
   `token_type`, `expires_at`). It's the cacheable unit — tokens are
   per-registration, while endpoints are per-context (per-course,
   per-launch). Host apps can cache an `AccessToken` and reuse it
   across contexts via `Client.from_access_token/2` or swap endpoints
   on an existing client via `Client.with_endpoints/2`. Both constructors
   validate endpoints and verify scope coverage upfront.

10. **Scopes are endpoint-driven**: Rather than each service module
    declaring a static `scope/0`, scopes are derived from endpoint
    structs via `scopes/1`. For NRPS, the scope is
    implied by the endpoint's presence. For AGS, the scopes come from
    the endpoint struct's `scope` field (which the platform populates
    in launch claims). This means `OAuth.authenticate/2` only requests
    scopes that the platform has indicated are available.

11. **Endpoint validation fails fast**: `OAuth.authenticate/2` calls
    `validate_endpoint/1` on each endpoint at authenticate time. Wrong
    struct types produce `%InvalidEndpoint{}` immediately, rather than
    surfacing as a cryptic `FunctionClauseError` later in a service call.

12. **Service shorthands accept both LaunchContext and Registration**:
    `Ltix.MembershipsService.authenticate/2` pattern-matches on the first
    argument. LaunchContext path extracts endpoints from claims.
    Registration path requires the caller to supply the endpoint struct.
    Multi-scope from registration uses `Ltix.OAuth.authenticate/2`
    with an `endpoints:` map.

---

## 13. Open Questions

None. All design questions have been resolved (see §12).
