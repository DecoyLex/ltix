# Ltix v0.1.0 — LTI 1.3 Core (Tool Side) Implementation Plan

**Scope**: Tool-side LTI 1.3 Core launch flow + claim parsing (including Advantage
service claim structs for AGS, NRPS, and Deep Linking endpoints). No platform side.
No Advantage service *API calls* — just parsing the claims platforms send in launches.

**Guiding principle**: Every line of every function must clearly communicate which
passage of the spec it implements. Spec references use the format:

- `[Core §X.Y.Z]` → LTI 1.3 Core Specification (https://www.imsglobal.org/spec/lti/v1p3/)
- `[Sec §X.Y.Z]` → 1EdTech Security Framework v1.0 (https://www.imsglobal.org/spec/security/v1p0/)
- `[Cert §X.Y.Z]` → LTI Advantage Conformance Certification Guide (https://www.imsglobal.org/spec/lti/v1p3/cert)

**Approach**: TDD, driven by the Certification Guide test cases [Cert §6].
Each module is developed test-first, with tests named after the conformance
scenario they cover.

---

## 1. Project Bootstrap

### 1.1 Mix Project Setup

```
mix new .
```

**Dependencies** (minimal, no framework coupling):

| Dependency | Purpose | Spec basis |
|---|---|---|
| `jose` | JWT/JWS/JWK (RS256 signing & verification) | [Sec §5.1.2] ID Token is a JWT; [Sec §5.1.3] RS256 verification; [Sec §6.1] RSA keys |
| `req` | HTTP client for JWKS fetching (testable via `Req.Test`) | [Sec §6.3] Key Set URL — tool fetches platform public keys from JWKS endpoint |
| `splode` | Structured, composable error types (Ash-compatible) | Rich error reporting |
| `plug` (optional) | Request/response interface for convenience wrappers | [Sec §5.1.1.3] Authentication response via form_post — optional, not required for core API |

JSON encoding/decoding uses the built-in `JSON` module (OTP 27+). No `jason` dependency needed.

No Ecto, no Phoenix, no database. The library is storage-agnostic — callers
provide configuration and implement a behaviour for state persistence (nonces,
registrations).

### 1.2 Directory Structure

```
lib/
  ltix.ex                          # Public API facade
  ltix/
    registration.ex                # Platform registration data [Core §3.1.2, §3.1.3]
    deployment.ex                  # Deployment identity [Core §3.1.3]
    launch_context.ex              # Parsed & validated launch (output struct)
    oidc/
      login_initiation.ex          # Step 1: Handle login initiation [Sec §5.1.1.1]
      authentication_request.ex    # Step 2: Build auth request [Sec §5.1.1.2]
      callback.ex                  # Step 3: Handle auth response [Sec §5.1.1.3]
    jwt/
      token.ex                     # JWT decoding and structural validation [Sec §5.1.3]
      key_set.ex                   # JWKS fetching and caching [Sec §6.3, §6.4]
    launch_claims.ex               # Main claims struct + from_json/2 entry point
    launch_claims/
      role.ex                      # %Role{type, name, sub_role, uri} + predicates [Core §5.3.7, §A.2]
      context.ex                   # %Context{id, label, title, type} [Core §5.4.1]
      resource_link.ex             # %ResourceLink{id, title, description} [Core §5.3.5]
      launch_presentation.ex       # %LaunchPresentation{...} [Core §5.4.4]
      tool_platform.ex             # %ToolPlatform{guid, name, ...} [Core §5.4.2]
      lis.ex                       # %Lis{person_sourcedid, ...} [Core §5.4.5]
      ags_endpoint.ex              # %AgsEndpoint{scope, lineitems, lineitem} [Core §6.1]
      nrps_endpoint.ex             # %NrpsEndpoint{context_memberships_url, ...} [Core §6.1]
      deep_linking_settings.ex     # %DeepLinkingSettings{deep_link_return_url, ...} [Core §6.1]
    errors.ex                      # Splode root: use Splode, error_classes: [...]
    errors/
      invalid.ex                   # Error class for spec-violating input
      invalid/
        missing_claim.ex           # Missing required LTI claim
        invalid_claim.ex           # Claim present but wrong value/format
        invalid_json.ex            # Malformed JSON/JWT structure [Cert §6.1.1 "Invalid LTI message"]
        missing_parameter.ex       # Missing OIDC login parameter [Sec §5.1.1.1]
        registration_not_found.ex  # Unknown issuer/client_id [Sec §5.1.1.1]
        deployment_not_found.ex    # Unknown deployment_id [Core §3.1.3]
      security.ex                  # Error class for security violations
      security/
        signature_invalid.ex       # JWT signature verification failed [Sec §5.1.3 step 1]
        token_expired.ex           # exp in the past [Sec §5.1.3 step 7]
        issuer_mismatch.ex         # iss doesn't match registration [Sec §5.1.3 step 2]
        audience_mismatch.ex       # client_id not in aud [Sec §5.1.3 step 3]
        algorithm_not_allowed.ex   # alg is not RS256 [Sec §5.1.3 step 6; Sec §7.3.2]
        nonce_missing.ex            # No nonce in JWT [Sec §5.1.3 step 9]
        nonce_reused.ex            # Nonce previously seen [Sec §5.1.3 step 9]
        nonce_not_found.ex         # Nonce not issued by this tool [Sec §5.1.3 step 9]
        state_mismatch.ex          # CSRF state doesn't match [Sec §7.3.1]
        kid_missing.ex             # No kid in JWT header [Cert §6.1.1 "No KID Sent"]
        kid_not_found.ex           # kid not in JWKS [Cert §6.1.1 "Incorrect KID"]
      unknown.ex                   # Catch-all error class
      unknown/
        unknown.ex                 # Generic unexpected error
    callback_behaviour.ex          # Behaviour for host-app integration
test/
  ltix/
    oidc/
      login_initiation_test.exs
      authentication_request_test.exs
      callback_test.exs
    jwt/
      token_test.exs
      key_set_test.exs
    launch_claims_test.exs           # Claims parsing: OIDC, LTI, nested, extensions
    launch_claims/
      role_test.exs                  # Comprehensive role URI parsing [Core §A.2]
      context_test.exs
      resource_link_test.exs
      launch_presentation_test.exs
      tool_platform_test.exs
      lis_test.exs
      ags_endpoint_test.exs
      nrps_endpoint_test.exs
      deep_linking_settings_test.exs
    integration/
      full_launch_test.exs         # End-to-end launch flow [Sec §5.1.1]
      certification_test.exs       # Tests mapped to [Cert §6.1] scenarios
  support/
    jwt_helper.ex                  # RSA key generation, JWT minting for tests
```

---

## 2. Module-by-Module Plan

Each section below states: **what it implements**, **which spec passages govern
it**, **what tests prove it**, and **the order of implementation** (dependencies
flow top-down).

---

### 2.1 `Ltix.Registration` — Platform Registration Data

**Spec basis**: [Core §3.1.2] LTI Domain Model — platform-tool relationship;
[Core §3.1.3] Tool Deployment — registration and deployment model;
[Sec §5.1.1.1] Third-party Initiated Login — tool must know platform's endpoints
prior to launch (out-of-band registration).

> [Core §3.1.3]: "When a user deploys a tool within their tool platform, the
> platform MUST generate an immutable `deployment_id` identifier to identify the
> integration."

A struct holding everything the tool knows about a registered platform.

> [Core §3.1.3]: "A tool MUST allow multiple deployments on a given platform to
> share the same `client_id` and the security contract attached to it."

This means the data model supports a **one-to-many relationship** from
`client_id` to `deployment_id`. A tool cannot assume `client_id` uniquely
identifies a deployment.

```elixir
defstruct [
  :issuer,             # [Sec §5.1.2] iss — Platform issuer identifier (HTTPS URL, no query/fragment)
  :client_id,          # [Sec §5.1.1.2] Tool's OAuth 2.0 client_id assigned by platform
  :auth_endpoint,      # [Sec §5.1.1.1] Platform OIDC authorization endpoint URL
  :jwks_uri,           # [Sec §6.3] Platform Key Set URL for public key retrieval
  :token_endpoint      # [Sec §4.1] Platform OAuth 2.0 token endpoint URL (for future service calls)
]
```

**Validation rules**:
- `issuer` MUST be a case-sensitive HTTPS URL containing scheme, host, optionally
  port and path, with **no query or fragment components**
  > [Sec §5.1.2]: "The `iss` value is a case-sensitive URL using the HTTPS scheme
  > that contains: scheme, host; and, optionally, port number, and path components;
  > and, no query or fragment components."
- `client_id` MUST be non-empty string [Sec §5.1.1.2: tool must send `client_id`]
- `auth_endpoint` MUST be HTTPS URL
  > [Sec §3]: "Implementers MUST use TLS 1.2 and/or TLS 1.3... Implementers MUST NOT use Secure Sockets Layer (SSL)."
  > [Cert §4.2]: "All communication endpoints MUST be secured with TLS (SSL-alone is expressly forbidden)."
- `jwks_uri` MUST be HTTPS URL [Sec §3; Sec §6.3]
- `token_endpoint` MUST be HTTPS URL when present [Sec §3]

**Tests**:
- Valid registration construction
- Rejection of non-HTTPS issuer [Sec §5.1.2]
- Rejection of issuer with query string [Sec §5.1.2]
- Rejection of issuer with fragment [Sec §5.1.2]
- Rejection of empty client_id
- Rejection of non-HTTPS auth_endpoint [Sec §3]
- Rejection of non-HTTPS jwks_uri [Sec §3]

---

### 2.1b `Ltix.Deployment` — Deployment Identity

**Spec basis**: [Core §3.1.3] Tool Deployment; [Core §5.3.3] deployment_id claim.

> [Core §3.1.3]: "When a user deploys a tool within their tool platform, the
> platform MUST generate an immutable `deployment_id` identifier to identify the
> integration. A platform MUST generate a unique `deployment_id` for each tool
> it integrates with."
>
> [Core §3.1.3]: "Every message between the platform and tool MUST include the
> `deployment_id` in addition to the `client_id`."

A struct representing a single deployment of a tool on a platform:

```elixir
defstruct [
  :deployment_id       # [Core §5.3.3] Case-sensitive string, ≤ 255 ASCII chars
]

@type t :: %__MODULE__{
  deployment_id: String.t()
}
```

**Validation rules**:
- `deployment_id` MUST be a non-empty string
- `deployment_id` MUST NOT exceed 255 ASCII characters in length
  > [Core §5.3.3]: "The required deployment_id claim's value contains a
  > case-sensitive string that identifies the platform-tool integration. It MUST
  > NOT exceed 255 ASCII characters in length."
- `deployment_id` is case-sensitive — comparisons MUST be exact byte match

**Tests**:
- Valid deployment construction
- Rejection of empty deployment_id
- Rejection of deployment_id exceeding 255 characters [Core §5.3.3]
- Rejection of non-ASCII deployment_id (> 255 ASCII chars, even if fewer Unicode chars)

---

### 2.2 `Ltix.CallbackBehaviour` — Host Application Interface

**Purpose**: Decouple the library from storage. The host app implements this
behaviour to look up registrations and track nonces.

```elixir
@doc """
Look up a platform registration by issuer and client_id.

Called during OIDC login initiation [Sec §5.1.1.1]. The `client_id` parameter
is optional — when not provided by the platform in the login request, the tool
must be able to locate the registration by issuer alone.

> [Core §4.1.3]: "The new optional parameter `client_id` specifies the client
> id for the authorization server that should be used to authorize the
> subsequent LTI message request."
"""
@callback get_registration(issuer :: String.t(), client_id :: String.t() | nil) ::
  {:ok, Registration.t()} | {:error, :not_found}

@doc """
Look up a deployment by registration and deployment_id.

Called during callback validation after the JWT deployment_id claim is
extracted. The deployment_id is case-sensitive.

> [Core §3.1.3]: "Every message between the platform and tool MUST include
> the `deployment_id` in addition to the `client_id`."
"""
@callback get_deployment(registration :: Registration.t(), deployment_id :: String.t()) ::
  {:ok, Deployment.t()} | {:error, :not_found}

@doc """
Store a nonce during OIDC login initiation [Sec §5.1.1.2] so it can be
validated when the callback arrives.

The nonce is generated by the library and must be persisted by the host app
so that `validate_nonce/2` can verify it was issued by us and not replayed.
"""
@callback store_nonce(nonce :: String.t(), registration :: Registration.t()) :: :ok

@doc """
Validate a nonce from the ID Token [Sec §5.1.3 step 9].

The implementation MUST verify two things:
1. The nonce was previously issued by this tool (matches a stored value)
   > [Sec §5.1.3 step 9]: "The Tool SHOULD verify that it has not yet received
   > this nonce value"
2. The nonce has not been used before (replay prevention)

After successful validation, the nonce MUST be marked as consumed so it
cannot be reused. The host app MAY define its own acceptable time window for
nonce expiry.
"""
@callback validate_nonce(nonce :: String.t(), registration :: Registration.t()) ::
  :ok | {:error, :nonce_already_used | :nonce_not_found}
```

**Atom-to-Splode conversion**: The behaviour returns simple atoms for ease of
implementation by host apps. The library converts these at the call boundary:

| Callback atom | Splode error |
|---|---|
| `get_registration` → `:not_found` | `Errors.Invalid.RegistrationNotFound` |
| `get_deployment` → `:not_found` | `Errors.Invalid.DeploymentNotFound` |
| `validate_nonce` → `:nonce_already_used` | `Errors.Security.NonceReused` |
| `validate_nonce` → `:nonce_not_found` | `Errors.Security.NonceNotFound` |

**Spec basis**:
- Registration lookup: [Sec §5.1.1.1] Tool receives `iss` (and optionally
  `client_id` per [Core §4.1.3]) and must locate the correct registration.
  > [Core §4.1.3]: "The new optional parameter `client_id` specifies the client
  > id for the authorization server that should be used to authorize the
  > subsequent LTI message request."
  The `client_id` may be absent from the login initiation request. When absent,
  the tool must look up the registration by `issuer` alone. When multiple
  registrations exist for the same issuer, the lookup MUST fail unless
  `client_id` is provided to disambiguate.
- Nonce storage and validation:
  > [Sec §5.1.3 step 9]: "The ID Token MUST contain a nonce Claim. The Tool
  > SHOULD verify that it has not yet received this nonce value (within a
  > Tool-defined time window), in order to help prevent replay attacks. The Tool
  > MAY define its own precise method for detecting replay attacks."
  The nonce serves dual purpose: (1) binding the ID Token to the authentication
  request (the nonce in the JWT must match the nonce sent in Step 2), and
  (2) replay prevention (a nonce must not be accepted twice).
- Deployment lookup:
  > [Core §3.1.3]: "When a user deploys a tool within their tool platform, the
  > platform MUST generate an immutable `deployment_id` identifier to identify
  > the integration."
  >
  > [Core §5.3.3]: "The required deployment_id claim's value contains a
  > case-sensitive string that identifies the platform-tool integration. It MUST
  > NOT exceed 255 ASCII characters in length. The `deployment_id` is a stable
  > locally unique identifier within the `iss` (Issuer)."

---

### 2.3 `Ltix.JWT.KeySet` — JWKS Fetching & Caching

**Spec basis**: [Sec §6.3] Key Set URL — "platform publishes JWKS endpoint for
public key distribution"; [Sec §6.4] Issuer Public Key Rotation — clients
should periodically refresh key sets; [Cert §4.2.1] "A Platform MUST provide a
Well-Known URL (JWKS) for the retrieval of Public Cryptographic keys."

**Responsibilities**:
1. Fetch JWKS from `registration.jwks_uri` via HTTPS [Sec §3: TLS required]
2. Parse JWK Set into `JOSE.JWK` structs [Sec §6.2: JSON Web Key format per RFC 7517]
   > [Sec §6.2]: "When using RSA keys, they MUST include the `n` (modulus) and
   > `e` (exponent) as defined in [RFC7518]."
3. Select key by `kid` header from JWT
   > [Sec §6.3]: "The supplier of the key set URL MUST use the `kid` parameter
   > to identify the keys. Even when there is only one key in a key-set a `kid`
   > MUST be supplied."
   >
   > [Sec §6.3]: "The Issuer of a JWT identifies the key a receiver uses to
   > validate the JWT signature by using the `kid` JWT header Claim."
4. Cache keys; respect `cache-control: max-age` header when present [Sec §6.3]
   > [Sec §6.3]: "The Issuer MAY issue a `cache-control: max-age` HTTP header
   > on requests to retrieve a key set to signal how long the retriever may
   > cache the key set before refreshing it."
5. Re-fetch on `kid` miss (key rotation support) [Sec §6.4]
   > [Sec §6.4]: "When the Issuer rotates its public key, the Issuer MUST add
   > it to the JSON Key Set under a new `kid`."
   When verifying a platform's JWT and the `kid` is not found in the cached
   JWKS, the tool SHOULD re-fetch the JWKS URL (the platform may have rotated
   keys). To prevent abuse, re-fetch at most once per `kid` miss.

**Tests** (TDD from [Cert §6.1.1] bad payload scenarios):
- Successful JWKS fetch and key selection by `kid` [Sec §6.3]
- Key selection from JWKS with multiple keys [Sec §6.3]
- `{:error, %Security.KidNotFound{}}` when JWT `kid` not in JWKS [Cert §6.1.1 "Incorrect KID in JWT header"]
- `{:error, %Security.KidMissing{}}` when JWT header has no `kid` field [Cert §6.1.1 "No KID Sent in JWT header"]
- Re-fetch on unknown `kid` (key rotation) [Sec §6.4] — verify only one re-fetch per miss
- Respect `cache-control: max-age` header for cache TTL [Sec §6.3]
- `{:error, %Unknown.Unknown{}}` on network failure

---

### 2.4 `Ltix.JWT.Token` — JWT Decoding & Structural Validation

**Spec basis**: [Sec §5.1.3] Authentication Response Validation — the nine
validation steps tools MUST perform on the ID Token; [Sec §5.1.2] ID Token
structure; [Sec §5.4] JWT Message requirements; [Cert §6.1.1] Known "Bad"
Payloads.

**Responsibilities** — implements [Sec §5.1.3] Authentication Response Validation.
Each step is annotated with its requirement level (MUST/SHOULD/MAY) from the spec:

> [Sec §5.1.3]: Tools "MUST validate ID tokens" by performing the following steps.

1. Decode JWT without verification (to extract header for `kid` lookup) [Sec §5.1.2]
2. **[MUST] Verify RS256 signature** using platform's public key — Step 1
   > [Sec §5.1.3 step 1]: "The Tool MUST Validate the signature of the ID Token
   > according to JSON Web Signature [RFC7515], Section 5.2 using the Public Key
   > from the Platform."
3. **[SHOULD→MUST for LTI] Validate algorithm** is RS256 — Step 6
   > [Sec §5.1.3 step 6]: "The `alg` value SHOULD be the default of RS256 or the
   > algorithm sent by the Tool in the `id_token_signed_response_alg` parameter
   > during its registration."
   >
   > [Sec §5.4]: "Message Tool JWTs MUST NOT use `none` as the `alg` value."
   >
   > [Cert §4.2]: "All Learning Platforms and Tools MUST provide the mechanisms
   > (the libraries) for signing and verification of signatures for JWTs signed
   > with RSA 256."
   >
   > [Cert §4.2]: "The use of Symmetric Cryptosystems SHALL NOT be considered
   > legal and use of them is expressly forbidden."
   >
   > Although the Security Framework says SHOULD for the `alg` check, the
   > Certification Guide elevates this to a hard requirement for LTI: only RS256
   > is tested. We treat `alg != RS256` as an error.
4. Validate structural claims — Steps 2–5, 7–9:
   - **[MUST]** `iss` matches registration issuer — Step 2
     > [Sec §5.1.3 step 2]: "The Issuer Identifier for the Platform MUST exactly
     > match the value of the `iss` (Issuer) Claim (therefore the Tool MUST
     > previously have been made aware of this identifier)."
   - **[MUST]** `aud` contains tool's `client_id` — Step 3
     > [Sec §5.1.3 step 3]: "The Tool MUST validate that the `aud` (audience)
     > Claim contains its client_id value registered as an audience with the
     > Issuer identified by the `iss` (Issuer) Claim. The `aud` (audience) Claim
     > MAY contain an array with more than one element. The Tool MUST reject the
     > ID Token if it does not list the client_id as a valid audience, or if it
     > contains additional audiences not trusted by the Tool. The request message
     > will be rejected with a HTTP code of 401."
     Note: `aud` may be a single string or an array per [Sec §5.1.2]:
     "In the common special case when there is one audience, the `aud` value MAY
     be a single case-sensitive string." Validation must handle both forms.
   - **[SHOULD]** `azp` present if multiple audiences — Step 4
     > [Sec §5.1.3 step 4]: "If the ID Token contains multiple audiences, the
     > Tool SHOULD verify that an `azp` Claim is present."
   - **[SHOULD]** `azp` value matches tool's client_id — Step 5
     > [Sec §5.1.3 step 5]: "If an `azp` (authorized party) Claim is present,
     > the Tool SHOULD verify that its client_id is the Claim's value."
   - **[MUST]** `exp` not in the past — Step 7
     > [Sec §5.1.3 step 7]: "The current time MUST be before the time
     > represented by the `exp` Claim."
     > [Sec §5.1.2]: "Implementers MAY provide for some small leeway, usually no
     > more than a few minutes, to account for clock skew."
   - **[MAY]** `iat` within acceptable skew — Step 8
     > [Sec §5.1.3 step 8]: "The Tool MAY use the `iat` Claim to reject tokens
     > that were issued too far away from the current time, limiting the amount
     > of time that it needs to store nonces used to prevent attacks. The Tool
     > MAY define its own acceptable time range."
   - **[MUST for presence, SHOULD for replay]** `nonce` validation — Step 9
     > [Sec §5.1.3 step 9]: "The ID Token MUST contain a `nonce` Claim. The Tool
     > SHOULD verify that it has not yet received this nonce value (within a
     > Tool-defined time window), in order to help prevent replay attacks."

**Tests** (TDD from [Cert §6.1.1]):
- Valid JWT passes all checks
- `{:error, %Security.SignatureInvalid{}}` on tampered payload [Sec §5.1.3 step 1]
- `{:error, %Security.TokenExpired{}}` when `exp` is in the past [Cert §6.1.1 "Timestamps Incorrect"]
- `{:error, %Security.IssuerMismatch{}}` when `iss` doesn't match [Sec §5.1.3 step 2]
- `{:error, %Security.AudienceMismatch{}}` when `client_id` not in `aud` as string [Sec §5.1.3 step 3]
- `{:error, %Security.AudienceMismatch{}}` when `client_id` not in `aud` as array [Sec §5.1.3 step 3]
- Valid when `aud` is a single string matching `client_id` [Sec §5.1.2]
- Valid when `aud` is an array containing `client_id` [Sec §5.1.2]
- `{:error, %Security.AudienceMismatch{}}` when multiple audiences but `azp` is wrong [Sec §5.1.3 step 5]
- `{:error, %Security.AlgorithmNotAllowed{}}` if alg is `none` [Sec §5.4]
- `{:error, %Security.AlgorithmNotAllowed{}}` if alg is HS256 [Cert §4.2 symmetric forbidden]
- `{:error, %Security.AlgorithmNotAllowed{}}` if alg is not RS256 [Sec §5.1.3 step 6; Cert §4.2]
- `{:error, %Security.NonceMissing{}}` when nonce claim absent [Sec §5.1.3 step 9]

---

### 2.5 `Ltix.LaunchClaims` — Claim Parsing & Classification

**Spec basis**: [Core §5.3] Required message claims; [Core §5.4] Optional
message claims; [Sec §5.1.2] ID Token claims; [Core §6.1] Services exposed as
additional claims; [Core §5.4.7] Vendor-specific extension claims.

**Architecture** (mirrors AshLti pattern): The `LaunchClaims` module is the main
struct + `from_json/2` entry point. It uses three mapping tables to classify every
JWT key, delegates to nested struct modules for complex claims, and collects
unrecognized keys into an `extensions` map.

#### 2.5.1 Key Classification — Three Mapping Tables

```elixir
# Table 1: OIDC standard claims → flat struct fields [Sec §5.1.2]
@oidc_keys %{
  "iss" => :issuer,              # [Sec §5.1.2] Issuer Identifier (HTTPS URL, no query/fragment)
  # [Core §5.3.6]: "sub (Required): When included, the sub (Subject) MUST be a
  #   stable locally unique to the iss (Issuer) identifier for the actual,
  #   authenticated End-User. It MUST NOT exceed 255 ASCII characters in length
  #   and is case-sensitive."
  # [Core §5.3.6.1]: "The platform may in these cases not include the sub claim
  #   or any other user identity claims. The tool must interpret the lack of a sub
  #   claim as a launch request coming from an anonymous user."
  "sub" => :subject,
  "aud" => :audience,            # [Sec §5.1.2] MUST contain Tool's client_id; string or array
  "exp" => :expires_at,          # [Sec §5.1.2] Expiration time; [Sec §5.1.3 step 7] Tool MUST NOT accept after
  "iat" => :issued_at,           # [Sec §5.1.2] Issued-at timestamp; [Sec §5.1.3 step 8] clock skew check
  "nonce" => :nonce,             # [Sec §5.1.2] Unique value for replay prevention; [Sec §5.1.3 step 9]
  "azp" => :authorized_party,    # [Sec §5.1.2] Required if multiple audiences; MUST contain Tool ID
  "email" => :email,             # [OIDC Core §5.1] Standard claim
  "name" => :name,               # [OIDC Core §5.1] Standard claim
  "given_name" => :given_name,   # [OIDC Core §5.1] Standard claim; [Core §5.3.6] user identity
  "family_name" => :family_name, # [OIDC Core §5.1] Standard claim; [Core §5.3.6] user identity
  "middle_name" => :middle_name, # [OIDC Core §5.1] Standard claim
  "picture" => :picture,         # [OIDC Core §5.1] Standard claim
  "locale" => :locale            # [OIDC Core §5.1] Standard claim
}

# Table 2: LTI-namespaced claims (prefix stripped) → struct fields
@lti_claim_prefix "https://purl.imsglobal.org/spec/lti/claim/"

@lti_keys %{
  # [Core §5.3.1]: "For conformance with this specification, the claim must have
  #   the value `LtiResourceLinkRequest`."
  "message_type" => :message_type,

  # [Core §5.3.2]: "For conformance with this specification, the claim must have
  #   the value `1.3.0`."
  "version" => :version,

  # [Core §5.3.3]: "The required deployment_id claim's value contains a case-sensitive
  #   string... It MUST NOT exceed 255 ASCII characters in length. The deployment_id
  #   is a stable locally unique identifier within the iss (Issuer)."
  "deployment_id" => :deployment_id,

  # [Core §5.3.4]: "The required target_link_uri MUST be the same value as the
  #   target_link_uri passed by the platform in the OIDC third party initiated
  #   login request."
  "target_link_uri" => :target_link_uri,

  # [Core §5.3.7]: "If this list is not empty, it MUST contain at least one role
  #   from the role vocabularies described in [Core §A.2]."
  "roles" => :roles,

  # [Core §5.4.3]: Array of user IDs this user can mentor/supervise.
  # [Core §5.4.3]: "The sender MUST NOT include a list of user ID values in
  #   this property unless they also provide
  #   http://purl.imsglobal.org/vocab/lis/v2/membership#Mentor as one of the
  #   values passed in the roles claim."
  "role_scope_mentor" => :role_scope_mentor,

  # [Core §5.4.1]: "id (REQUIRED). Stable identifier that uniquely identifies the
  #   context. The context id MUST be locally unique to the deployment_id."
  "context" => :context,                   # → nested Context struct

  # [Core §5.3.5]: "id (REQUIRED). Opaque identifier for a placement of an LTI
  #   resource link within a context that MUST be a stable and locally unique to the
  #   deployment_id. This value MUST change if the link is copied or exported. The
  #   value of id MUST NOT exceed 255 ASCII characters in length and is case-sensitive."
  "resource_link" => :resource_link,       # → nested ResourceLink struct

  # [Core §5.4.6]: Key-value map.
  # [Core §5.4.6]: "Each custom property value MUST always be of type string."
  # Empty string ("") IS valid. null is NOT valid.
  # Values with $ prefix are unresolved substitution variables [Core §5.4.6.1]:
  # "If the platform does not support a given variable, the substitution parameter
  # MUST be passed unresolved."
  "custom" => :custom,

  "launch_presentation" => :launch_presentation, # [Core §5.4.4] → nested
  "tool_platform" => :tool_platform,       # [Core §5.4.2] → nested
  "lis" => :lis                            # [Core §5.4.5] → nested
}

# Table 3: Service endpoint claims (full URIs) → struct fields
# [Core §6.1]: "The platform MUST include in each message applicable service
#   endpoints as fully resolved URLs (not as URL templates). The platform MUST
#   have a separate claim in the message for each service."
@service_keys %{
  "https://purl.imsglobal.org/spec/lti-ags/claim/endpoint" => :ags_endpoint,
  "https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice" => :nrps_endpoint,
  "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings" => :deep_linking_settings
}
```

#### 2.5.2 `classify_key/1` — Route Each JWT Key

```elixir
defp classify_key(key) do
  cond do
    Map.has_key?(@oidc_keys, key) ->
      {:oidc, Map.fetch!(@oidc_keys, key)}

    Map.has_key?(@service_keys, key) ->
      {:service, Map.fetch!(@service_keys, key)}

    String.starts_with?(key, @lti_claim_prefix) ->
      suffix = String.replace_leading(key, @lti_claim_prefix, "")
      case Map.fetch(@lti_keys, suffix) do
        {:ok, field} -> {:lti, field}
        :error -> {:extension, key}
      end

    true ->
      {:extension, key}
  end
end
```

OIDC keys take priority → service keys → LTI prefix+suffix → extension.

> [Core §5.4.7]: "In order to preserve forward compatibility and
> interoperability between platforms and tools, receivers of messages MUST ignore
> any claims in messages they do not understand, and not treat the presence of
> such claims as an error."

Extensions are preserved in the `extensions` map — never dropped, never errors.

#### 2.5.3 `from_json/2` — Parsing Pipeline

```elixir
@spec from_json(map(), keyword()) :: {:ok, t()} | {:error, Splode.Error.t()}
def from_json(json, opts \\ []) when is_map(json) do
  parsers = resolve_extension_parsers(opts)
  {fields, extensions} = classify_keys(json)

  with {:ok, fields} <- parse_nested_claims(fields),
       {:ok, fields} <- parse_roles(fields),
       {:ok, extensions} <- parse_extensions(extensions, parsers) do
    {:ok, struct!(__MODULE__, Map.put(fields, :extensions, extensions))}
  end
end
```

Pipeline stages (short-circuits on first error via `with`):
1. **Classify keys** — split JWT body into known fields vs extensions
2. **Parse nested claims** — call `from_json/1` on each nested struct type
3. **Parse roles** — convert URI strings to `%Role{}` structs per [Core §A.2]
4. **Parse extensions** — apply registered extension parsers per [Core §5.4.7]
5. **Build struct** — construct `%LaunchClaims{}`

#### 2.5.4 Nested Claim Parsers

```elixir
@nested_parsers %{
  context: &Context.from_json/1,                       # [Core §5.4.1]
  resource_link: &ResourceLink.from_json/1,            # [Core §5.3.5]
  launch_presentation: &LaunchPresentation.from_json/1, # [Core §5.4.4]
  tool_platform: &ToolPlatform.from_json/1,            # [Core §5.4.2]
  lis: &Lis.from_json/1,                               # [Core §5.4.5]
  ags_endpoint: &AgsEndpoint.from_json/1,              # [Core §6.1]
  nrps_endpoint: &NrpsEndpoint.from_json/1,            # [Core §6.1]
  deep_linking_settings: &DeepLinkingSettings.from_json/1 # [Core §6.1]
}
```

If a nested claim is **present but invalid** (e.g., Context missing `id` per
[Core §5.4.1]), the error propagates and `from_json/2` returns `{:error, reason}`.
If a nested claim is **absent**, the field defaults to `nil` — no error per
[Core §5.4]: optional claims may be omitted.

#### 2.5.5 Extension Parsers — Pluggable [Core §5.4.7]

```elixir
# Application config
config :ltix, launch_claim_parsers: %{
  "https://example.com/custom" => &MyApp.CustomClaim.from_json/1
}

# Per-call override (takes priority)
LaunchClaims.from_json(jwt_body, parsers: %{
  "https://example.com/custom" => &MyApp.CustomClaim.from_json/1
})
```

Parser contract: arity 1, receives raw value, returns `{:ok, parsed}` or
`{:error, reason}`. Errors halt the pipeline. Per [Core §5.4.7], vendor
extensions use fully-qualified URL claim names.

#### 2.5.6 The `%LaunchClaims{}` Struct

```elixir
@type t :: %__MODULE__{
  # OIDC Standard Claims [Sec §5.1.2]
  issuer: String.t() | nil,            # [Sec §5.1.2] iss
  subject: String.t() | nil,           # [Sec §5.1.2] sub; [Core §5.3.6] ≤255 ASCII
  audience: String.t() | [String.t()] | nil, # [Sec §5.1.2] aud
  expires_at: integer() | nil,         # [Sec §5.1.2] exp
  issued_at: integer() | nil,          # [Sec §5.1.2] iat
  nonce: String.t() | nil,             # [Sec §5.1.2] nonce
  authorized_party: String.t() | nil,  # [Sec §5.1.2] azp

  # OIDC Profile Claims [OIDC Core §5.1]; [Core §5.3.6] user identity
  email: String.t() | nil,
  name: String.t() | nil,
  given_name: String.t() | nil,
  family_name: String.t() | nil,
  middle_name: String.t() | nil,
  picture: String.t() | nil,
  locale: String.t() | nil,

  # LTI Core Required Claims [Core §5.3]
  message_type: String.t() | nil,      # [Core §5.3.1] "LtiResourceLinkRequest"
  version: String.t() | nil,           # [Core §5.3.2] "1.3.0"
  deployment_id: String.t() | nil,     # [Core §5.3.3] ≤255 ASCII, case-sensitive
  target_link_uri: String.t() | nil,   # [Core §5.3.4] actual endpoint URL
  roles: [Role.t()],                   # [Core §5.3.7] parsed role URIs from [Core §A.2]
  unrecognized_roles: [String.t()],    # URIs not in [Core §A.2] vocabularies (preserved)
  role_scope_mentor: [String.t()] | nil, # [Core §5.4.3] array of user IDs

  # Nested Claim Objects
  context: Context.t() | nil,          # [Core §5.4.1]
  resource_link: ResourceLink.t() | nil, # [Core §5.3.5]
  custom: map() | nil,                 # [Core §5.4.6]
  launch_presentation: LaunchPresentation.t() | nil, # [Core §5.4.4]
  tool_platform: ToolPlatform.t() | nil, # [Core §5.4.2]
  lis: Lis.t() | nil,                  # [Core §5.4.5]

  # Advantage Service Claims [Core §6.1] (parsed from launch, no API calls)
  ags_endpoint: AgsEndpoint.t() | nil,
  nrps_endpoint: NrpsEndpoint.t() | nil,
  deep_linking_settings: DeepLinkingSettings.t() | nil,

  # Forward compatibility [Core §5.4.7] + vendor extensions
  extensions: %{optional(String.t()) => term()}
}
```

**Tests** (`test/ltix/launch_claims_test.exs`):
- OIDC claims parsed correctly [Sec §5.1.2] (iss, sub, aud, exp, iat, nonce, azp, profile)
- LTI claims parsed correctly [Core §5.3, §5.4] (message_type, version, deployment_id, etc.)
- Service endpoint claims parsed into nested structs [Core §6.1]
- Unknown claims preserved in `extensions` [Core §5.4.7]
- Extension parsers invoked (config-based and per-call)
- Per-call parsers override config parsers
- Missing optional nested claims default to `nil` [Core §5.4]
- Present but invalid nested claims propagate errors
- Roles parsed into `%Role{}` structs [Core §A.2]; unrecognized collected separately

---

### 2.6 Nested Claim Structs

Each nested claim type lives in `lib/ltix/launch_claims/` and implements
`from_json/1` returning `{:ok, struct}` or `{:error, reason}`.

#### 2.6.1 `Ltix.LaunchClaims.Context` [Core §5.4.1]

Claim key: `https://purl.imsglobal.org/spec/lti/claim/context`

> [Core §5.4.1]: "id (REQUIRED). Stable identifier that uniquely identifies the
> context. The context id MUST be locally unique to the `deployment_id`. The
> value of `id` MUST NOT exceed 255 ASCII characters in length and is
> case-sensitive."

```elixir
defstruct [:id, :label, :title, :type]

# type is array of URIs from [Core §A.1] context type vocabulary
def from_json(%{"id" => _} = json), do: {:ok, ...}
def from_json(_), do: {:error, Errors.Invalid.MissingClaim.exception(
  claim: "context.id", spec_ref: "Core §5.4.1")}
```

**Context Type Vocabulary** [Core §A.1]:

> [Core §A.1]: Conforming implementations "MUST recognize the new URI values."
> Implementations "MAY recognize the deprecated simple names... and the deprecated
> URN values."

| Type | URI (MUST recognize) | Deprecated Simple Name (MAY recognize) |
|---|---|---|
| Course Template | `http://purl.imsglobal.org/vocab/lis/v2/course#CourseTemplate` | `CourseTemplate` |
| Course Offering | `http://purl.imsglobal.org/vocab/lis/v2/course#CourseOffering` | `CourseOffering` |
| Course Section | `http://purl.imsglobal.org/vocab/lis/v2/course#CourseSection` | `CourseSection` |
| Group | `http://purl.imsglobal.org/vocab/lis/v2/course#Group` | `Group` |

The `type` array, if present, MUST contain at least one value from this
vocabulary per [Core §5.4.1]. The implementation SHOULD use fully-qualified URIs
for any non-standard context types.

#### 2.6.2 `Ltix.LaunchClaims.ResourceLink` [Core §5.3.5]

Claim key: `https://purl.imsglobal.org/spec/lti/claim/resource_link`

> [Core §5.3.5]: "id (REQUIRED). Opaque identifier for a placement of an LTI
> resource link within a context that MUST be a stable and locally unique to the
> `deployment_id`. This value MUST change if the link is copied or exported. The
> value of `id` MUST NOT exceed 255 ASCII characters in length and is
> case-sensitive."

```elixir
defstruct [:id, :title, :description]

def from_json(%{"id" => _} = json), do: {:ok, ...}
def from_json(_), do: {:error, Errors.Invalid.MissingClaim.exception(
  claim: "resource_link.id", spec_ref: "Core §5.3.5")}
```

#### 2.6.3 `Ltix.LaunchClaims.LaunchPresentation` [Core §5.4.4]

Claim key: `https://purl.imsglobal.org/spec/lti/claim/launch_presentation`

```elixir
defstruct [:document_target, :height, :width, :return_url, :locale]

# [Core §5.4.4] All fields optional.
def from_json(json) do
  # Validate document_target if present
  # [Core §5.4.4]: document_target MUST be one of: "frame", "iframe", or "window"
  {:ok, ...}
end
```

**Validation rules**:
- `document_target`: when present, MUST be one of `"frame"`, `"iframe"`, or `"window"`
  > [Core §5.4.4]: "The value MUST be one of: `frame`, `iframe`, or `window`."
- `height`: optional, number (viewport height in pixels)
- `width`: optional, number (viewport width in pixels)
- `return_url`: optional, fully-qualified HTTPS URL
- `locale`: optional, IETF BCP47 language tag

**Return URL parameters** [Core §5.4.4]: When the tool redirects back to
`return_url`, it MAY append these query parameters:
- `lti_errormsg` — user-targeted message for unsuccessful activity
- `lti_msg` — user-targeted message for successful activity
- `lti_errorlog` — log-targeted message for unsuccessful activity
- `lti_log` — log-targeted message for successful activity

> [Core §5.4.4]: "If the message sender includes a `return_url` in its
> `launch_presentation`, it MUST support these four query parameters."

#### 2.6.4 `Ltix.LaunchClaims.ToolPlatform` [Core §5.4.2]

Claim key: `https://purl.imsglobal.org/spec/lti/claim/tool_platform`

> [Core §5.4.2]: "guid (REQUIRED). A stable locally unique to the `iss`
> identifier for an instance of the tool platform. The value of `guid` is a
> case-sensitive string that MUST NOT exceed 255 ASCII characters in length."

```elixir
defstruct [:guid, :name, :contact_email, :description, :url,
           :product_family_code, :version]

# guid is REQUIRED when the claim is present [Core §5.4.2]
def from_json(%{"guid" => _} = json), do: {:ok, ...}
def from_json(_), do: {:error, Errors.Invalid.MissingClaim.exception(
  claim: "tool_platform.guid", spec_ref: "Core §5.4.2")}
```

**Validation rules**:
- `guid` (REQUIRED within claim): case-sensitive string, MUST NOT exceed 255
  ASCII characters. UUID recommended per RFC 4122.
- All other fields are optional.

#### 2.6.5 `Ltix.LaunchClaims.Lis` [Core §5.4.5]

Claim key: `https://purl.imsglobal.org/spec/lti/claim/lis`

```elixir
defstruct [:person_sourcedid, :course_offering_sourcedid,
           :course_section_sourcedid]

# [Core §5.4.5] SIS integration identifiers. All optional.
# See also [Core §Appendix D] for LIS integration guidance.
def from_json(json), do: {:ok, ...}
```

#### 2.6.6 `Ltix.LaunchClaims.AgsEndpoint` [Core §6.1]

Claim key: `https://purl.imsglobal.org/spec/lti-ags/claim/endpoint`

```elixir
defstruct [:scope, :lineitems, :lineitem]

# [Core §6.1] Service endpoint exposed as additional claim.
# scope: array of granted scope strings; lineitems/lineitem: fully resolved URLs.
# All optional.
def from_json(json), do: {:ok, ...}
```

#### 2.6.7 `Ltix.LaunchClaims.NrpsEndpoint` [Core §6.1]

Claim key: `https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice`

```elixir
defstruct [:context_memberships_url, :service_versions]

# [Core §6.1] NRPS service endpoint claim. All optional.
def from_json(json), do: {:ok, ...}
```

#### 2.6.8 `Ltix.LaunchClaims.DeepLinkingSettings` [Core §6.1]

Claim key: `https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings`

```elixir
defstruct [:deep_link_return_url, :accept_types,
           :accept_presentation_document_targets, :accept_media_types,
           :accept_multiple, :accept_lineitem, :auto_create,
           :title, :text, :data]

# deep_link_return_url REQUIRED when claim is present; rest optional.
def from_json(%{"deep_link_return_url" => _} = json), do: {:ok, ...}
def from_json(_), do: {:error, Errors.Invalid.MissingClaim.exception(
  claim: "deep_linking_settings.deep_link_return_url", spec_ref: "Core §6.1")}
```

**Tests**: Each nested struct has its own test file covering:
- All fields populated
- Only required fields populated
- Missing required field returns error:
  - Context missing `id` [Core §5.4.1]
  - ResourceLink missing `id` [Core §5.3.5]
  - ToolPlatform missing `guid` [Core §5.4.2]
  - DeepLinkingSettings missing `deep_link_return_url`
- Missing optional fields default to `nil`
- LaunchPresentation: valid `document_target` values accepted (`frame`, `iframe`, `window`) [Core §5.4.4]
- LaunchPresentation: invalid `document_target` returns error [Core §5.4.4]
- Context: `type` array with full URI values recognized [Core §A.1]
- Context: `type` array with deprecated simple names recognized [Core §A.1]

---

### 2.7 `Ltix.LaunchClaims.Role` — Role URI Parsing

**Spec basis**: [Core §5.3.7] Roles claim; [Core §A.2] Role vocabularies —
[Core §A.2.1] LIS vocabulary for system roles, [Core §A.2.2] LIS vocabulary
for institution roles, [Core §A.2.3] LIS vocabulary for context roles,
[Core §A.2.3.1] Context sub-roles, [Core §A.2.4] LTI vocabulary for system roles.

> [Core §5.3.7]: "If this list is not empty, it MUST contain at least one role
> from the role vocabularies described in [role vocabularies]."
>
> [Core §5.3.7.1]: "The platform may provide no user-identity claims, but may
> still include roles claim values. If the platform wishes to send no role
> information, it must still send the roles claim, but may leave the value empty."

**Struct**:

```elixir
@type t :: %__MODULE__{
  type: :context | :institution | :system,
  name: atom(),           # e.g., :instructor, :learner, :administrator
  sub_role: atom() | nil, # e.g., :teaching_assistant, :grader [Core §A.2.3.1]
  uri: String.t()         # Original URI preserved
}
```

**Responsibilities**:
1. Parse full context role URIs per [Core §A.2.3]: `http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor`
2. Parse context sub-roles per [Core §A.2.3.1]: `membership/Instructor#TeachingAssistant`
3. Parse institution role URIs per [Core §A.2.2]: `http://purl.imsglobal.org/vocab/lis/v2/institution/person#Faculty`
4. Parse system role URIs per [Core §A.2.1]: `http://purl.imsglobal.org/vocab/lis/v2/system/person#Administrator`
5. Parse LTI system role URIs per [Core §A.2.4]: `http://purl.imsglobal.org/vocab/lti/system/person#TestUser`
6. Parse short (simple name) role URIs [Cert §6.1.2 "Valid Instructor Launch Short Role"]
7. Accept unknown role URIs — return `:error`, collected in `unrecognized_roles` by `LaunchClaims`

**`parse_all/1`** — Separates recognized from unrecognized:

```elixir
@spec parse_all([String.t()]) :: {[t()], [String.t()]}
def parse_all(uris) do
  Enum.reduce(uris, {[], []}, fn uri, {parsed, unrecognized} ->
    case parse(uri) do
      {:ok, role} -> {[role | parsed], unrecognized}
      :error -> {parsed, [uri | unrecognized]}
    end
  end)
  |> then(fn {p, u} -> {Enum.reverse(p), Enum.reverse(u)} end)
end
```

**Predicate helpers**:

```elixir
def instructor?(roles), do: has_role?(roles, :context, :instructor)
def learner?(roles), do: has_role?(roles, :context, :learner)
def administrator?(roles), do: has_role?(roles, :context, :administrator)
def content_developer?(roles), do: has_role?(roles, :context, :content_developer)
def mentor?(roles), do: has_role?(roles, :context, :mentor)
def teaching_assistant?(roles), do: has_role?(roles, :context, :instructor, :teaching_assistant)

def has_role?(roles, type, name, sub_role \\ nil)
```

**Filter helpers**:

```elixir
def context_roles(roles), do: Enum.filter(roles, &(&1.type == :context))
def institution_roles(roles), do: Enum.filter(roles, &(&1.type == :institution))
def system_roles(roles), do: Enum.filter(roles, &(&1.type == :system))
```

**Role vocabulary** (comprehensive, per [Core §A.2]):

> [Core §A]: "Conforming implementations MAY recognize the deprecated simple
> names (for context types and context roles) and the deprecated URN values,
> and MUST recognize the new URI values."

| Type | Spec section | Base URI | Roles |
|---|---|---|---|
| Context (core) | [Core §A.2.3] | `http://purl.imsglobal.org/vocab/lis/v2/membership#` | Administrator, ContentDeveloper, Instructor, Learner, Mentor |
| Context (non-core) | [Core §A.2.3] | `http://purl.imsglobal.org/vocab/lis/v2/membership#` | Manager, Member, Officer |
| Institution (core) | [Core §A.2.2] | `http://purl.imsglobal.org/vocab/lis/v2/institution/person#` | Administrator, Faculty, Guest, None, Other, Staff, Student |
| Institution (non-core) | [Core §A.2.2] | `http://purl.imsglobal.org/vocab/lis/v2/institution/person#` | Alumni, Instructor, Learner, Member, Mentor, Observer, ProspectiveStudent |
| System (LIS, core) | [Core §A.2.1] | `http://purl.imsglobal.org/vocab/lis/v2/system/person#` | Administrator, None |
| System (LIS, non-core) | [Core §A.2.1] | `http://purl.imsglobal.org/vocab/lis/v2/system/person#` | AccountAdmin, Creator, SysAdmin, SysSupport, User |
| System (LTI) | [Core §A.2.4] | `http://purl.imsglobal.org/vocab/lti/system/person#` | TestUser |

**Deprecated URI forms** (MAY recognize for backward compatibility):
- System roles formerly used `http://purl.imsglobal.org/vocab/lis/v2/person#`
  (without `system/` in path)
- Institution roles formerly used `http://purl.imsglobal.org/vocab/lis/v2/person#`
  (without `institution/` in path)

**Context sub-roles** [Core §A.2.3.1] — Complete listing:

URI format: `http://purl.imsglobal.org/vocab/lis/v2/membership/{RoleName}#{SubRoleName}`

> [Core §A.2.3.1]: "Whenever a platform specifies a sub-role, by best practice
> it should also include the associated principal role." The tool should NOT
> assume the principal role is always present alongside the sub-role.

| Principal Role | Sub-Roles |
|---|---|
| Administrator | Administrator, Developer, ExternalDeveloper, ExternalSupport, ExternalSystemAdministrator, Support, SystemAdministrator |
| ContentDeveloper | ContentDeveloper, ContentExpert, ExternalContentExpert, Librarian |
| Instructor | ExternalInstructor, Grader, GuestInstructor, Lecturer, PrimaryInstructor, SecondaryInstructor, TeachingAssistant, TeachingAssistantGroup, TeachingAssistantOffering, TeachingAssistantSection, TeachingAssistantSectionAssociation, TeachingAssistantTemplate |
| Learner | ExternalLearner, GuestLearner, Instructor, Learner, NonCreditLearner |
| Manager | AreaManager, CourseCoordinator, ExternalObserver, Manager, Observer |
| Member | Member |
| Mentor | Advisor, Auditor, ExternalAdvisor, ExternalAuditor, ExternalLearningFacilitator, ExternalMentor, ExternalReviewer, ExternalTutor, LearningFacilitator, Mentor, Reviewer, Tutor |
| Officer | Chair, Communications, Secretary, Treasurer, Vice-Chair |

**TestUser role** [Core §A.2.4]:
> Indicates the user is created by the platform for testing purposes (e.g.,
> student preview mode). Tools MAY wish to filter this user from rosters. Tools
> MAY want to ignore this user when sending grades but SHOULD be able to treat
> it as a regular user.

**Tests** (`test/ltix/launch_claims/role_test.exs`):
- Full URI parsing for each context role (8 roles) [Core §A.2.3]
- Full URI parsing for each context sub-role (complete table above) [Core §A.2.3.1]
- Full URI parsing for each institution role (14 roles) [Core §A.2.2]
- Full URI parsing for each system role (LIS: 7 roles) [Core §A.2.1]
- Full URI parsing for LTI system role (TestUser) [Core §A.2.4]
- Deprecated URI forms (without `system/` or `institution/` path segment) [Core §A]
- Short role format acceptance (e.g., `Instructor`) [Cert §6.1.2 "Valid Instructor Launch Short Role"]
- Multiple roles via `parse_all/1` [Cert §6.1.2 "Valid Instructor Launch with Roles"]
- Unknown role URIs → `:error`, collected in unrecognized [Cert §6.1.2 "Valid Instructor Launch Unknown Role"]
- Empty list accepted (anonymous launch) [Core §5.3.7.1]
- Sub-role without principal role present (tool must handle) [Core §A.2.3.1]
- Predicate helpers return correct booleans
- Filter helpers return correct subsets
- Original URI preserved in struct

---

### 2.8 `Ltix.OIDC.LoginInitiation` — Step 1: Handle Platform Login Request

**Spec basis**: [Sec §5.1.1.1] Step 1: Third-party Initiated Login.

> [Cert §4.2.2]: "All launches will be required to go through the OIDC
> initialization and launch process. There are no exceptions to the requirement
> that OIDC always will be used."

**Input**: HTTP request from platform with parameters per [Sec §5.1.1.1].

> [Sec §5.1.1.1]: "The redirect may be a form POST or a GET — a Tool must
> support either case."

The library accepts a plain `map()` of string-keyed params, so the host app's
HTTP handler is responsible for extracting params from either GET query string or
POST body and passing them as a map. This makes the library transport-agnostic
while ensuring both delivery methods are supported.

**Parameters**:
- `iss` (REQUIRED) — Platform issuer identifier [Sec §5.1.1.1]
- `login_hint` (REQUIRED) — Opaque login hint [Sec §5.1.1.1]
- `target_link_uri` (REQUIRED) — Tool endpoint for post-auth resource display [Sec §5.1.1.1]
- `lti_message_hint` (OPTIONAL) — Opaque to tool; pass through verbatim
  > [Core §4.1.1]: "If present in the login initiation request, the tool MUST
  > include it back in the authentication request unaltered."
- `lti_deployment_id` (OPTIONAL) — May be used for deployment-specific routing
  > [Core §4.1.2]: "If included, MUST contain the same deployment id that would
  > be passed in the deployment_id claim for the subsequent LTI message launch."
- `client_id` (OPTIONAL) — Disambiguates registrations when issuer has multiple
  > [Core §4.1.3]: "The new optional parameter `client_id` specifies the client
  > id for the authorization server that should be used to authorize the
  > subsequent LTI message request."

**Responsibilities**:
1. Extract and validate required parameters [Sec §5.1.1.1]
2. Look up registration via callback behaviour (`iss`, optionally `client_id` per [Core §4.1.3])
3. Generate cryptographic `state` value [Sec §5.1.1.2: CSRF prevention; Sec §7.3.1]
4. Generate cryptographic `nonce` value [Sec §5.1.1.2: "nonce: Unique per-request value for replay mitigation"]
5. Store `nonce` via callback behaviour (`store_nonce/2`) for later validation
6. Return authentication request parameters for redirect to platform

**Tests**:
- Valid login initiation produces correct auth request params [Sec §5.1.1.1 → §5.1.1.2]
- Missing `iss` returns error [Sec §5.1.1.1: required]
- Missing `login_hint` returns error [Sec §5.1.1.1: required]
- Missing `target_link_uri` returns error [Sec §5.1.1.1: required]
- Unknown issuer returns error (registration not found)
- `lti_message_hint` preserved when present [Core §4.1.1: "tool must return unaltered"]
- `lti_message_hint` omitted when not present in input
- `client_id` used for registration lookup when present [Core §4.1.3]
- `client_id` absent — registration looked up by issuer alone
- `lti_deployment_id` preserved in output for host app routing [Core §4.1.2]

---

### 2.9 `Ltix.OIDC.AuthenticationRequest` — Step 2: Build Auth Redirect

**Spec basis**: [Sec §5.1.1.2] Step 2: Authentication Request — "Tool redirects
to Platform's OIDC authorization endpoint."

**Responsibilities**: Build the redirect URL to the platform's OIDC authorization
endpoint with these parameters:

| Parameter | Value | Spec |
|---|---|---|
| `scope` | `openid` | [Sec §5.1.1.2] "scope=openid" |
| `response_type` | `id_token` | [Sec §5.1.1.2] "response_type=id_token" |
| `client_id` | Registration's client_id | [Sec §5.1.1.2] "client_id: Tool's client ID" |
| `redirect_uri` | Tool's registered callback URI | [Sec §5.1.1.2] "redirect_uri: Registered redirect URI" |
| `login_hint` | From Step 1 (pass through) | [Sec §5.1.1.2] "login_hint: From step 1" |
| `state` | Generated in Step 1 | [Sec §5.1.1.2] "state: For CSRF/state maintenance"; [Sec §7.3.1] |
| `response_mode` | `form_post` | [Sec §5.1.1.2] "response_mode=form_post" |
| `nonce` | Generated in Step 1 | [Sec §5.1.1.2] "nonce: Unique per-request value" |
| `prompt` | `none` | [Sec §5.1.1.2] "prompt=none: Fail if no existing user session" |
| `lti_message_hint` | From Step 1 (pass through, if present) | [Core §4.1.1] "tool must return unaltered" |

**Tests**:
- All required parameters present in output URL [Sec §5.1.1.2]
- `lti_message_hint` included when provided [Core §4.1.1]
- `lti_message_hint` omitted when not provided
- Redirect URI is properly URL-encoded
- `prompt=none` is always set [Sec §5.1.1.2]

---

### 2.10 `Ltix.OIDC.Callback` — Step 3: Handle Authentication Response

**Spec basis**: [Sec §5.1.1.3] Step 3: Authentication Response — "Platform
validates redirect URI and login hint, then sends id_token and state to
redirect_uri"; [Sec §5.1.3] Authentication Response Validation — the nine
steps tools MUST perform; [Sec §5.1.1.5] Authentication Error Response.

This is the heart of the library. It receives the platform's form POST and
produces either a validated `LaunchContext` or an error.

**Input**: HTTP POST with `id_token` and `state` parameters [Sec §5.1.1.3].
The tool may also receive error responses per [Sec §5.1.1.5] / OIDC Core
§3.1.2.6 — if the platform could not complete authentication, it sends
`error`, `error_description`, `error_uri`, and `state` instead of `id_token`.
The callback must detect and handle this case.

**Validation pipeline** — implements [Sec §5.1.3] Authentication Response
Validation. The nine numbered steps from the spec are mapped below, with
additional LTI-layer validation appended. Step numbers in parentheses reference
the spec's step numbering:

> [Sec §5.1.3]: Tools "MUST validate ID tokens" by performing the following.

1. **Check for error response** [Sec §5.1.1.5]
   If `error` parameter is present (instead of `id_token`), return error
   immediately — the platform could not complete authentication.
2. **Verify `state`** matches the value generated in Step 1
   > [Sec §7.3.1]: "State parameter MUST be used" to prohibit CSRF.
3. **Extract JWT header** — get `kid` and `alg` [Sec §5.1.2]
4. **Validate `alg`** is RS256 (Spec step 6, SHOULD; Cert §4.2, MUST for LTI)
   > [Sec §5.4]: "Message Tool JWTs MUST NOT use `none` as the `alg` value."
   >
   > [Cert §4.2]: "The use of Symmetric Cryptosystems SHALL NOT be considered
   > legal and use of them is expressly forbidden."
5. **Fetch platform public key** by `kid` from JWKS [Sec §6.3]
   > [Cert §4.2.1]: "A Platform MUST provide a Well-Known URL (JWKS) for the
   > retrieval of Public Cryptographic keys."
6. **Verify JWT signature** (Spec step 1, MUST) — [Sec §5.1.3 step 1]:
   > "The Tool MUST Validate the signature of the ID Token according to JSON
   > Web Signature [RFC7515], Section 5.2 using the Public Key from the
   > Platform."
7. **Validate `iss`** (Spec step 2, MUST) — [Sec §5.1.3 step 2]:
   > "The Issuer Identifier for the Platform MUST exactly match the value of
   > the `iss` (Issuer) Claim."
8. **Validate `aud`** (Spec step 3, MUST) — [Sec §5.1.3 step 3]:
   > "The Tool MUST validate that the `aud` (audience) Claim contains its
   > client_id value... The Tool MUST reject the ID Token if it does not list
   > the client_id as a valid audience, or if it contains additional audiences
   > not trusted by the Tool. The request message will be rejected with a HTTP
   > code of 401."
   `aud` may be a single string or an array — must handle both forms.
9. **Validate `azp`** (Spec steps 4–5, SHOULD) — [Sec §5.1.3 steps 4–5]:
   If `aud` has multiple values, verify `azp` is present and equals the tool's
   `client_id`.
10. **Validate `exp`** (Spec step 7, MUST) — [Sec §5.1.3 step 7]:
   > "The current time MUST be before the time represented by the `exp` Claim."
11. **Validate `iat`** (Spec step 8, MAY) — [Sec §5.1.3 step 8]:
   > "The Tool MAY use the `iat` Claim to reject tokens that were issued too
   > far away from the current time."
12. **Validate `nonce`** (Spec step 9, MUST for presence) — [Sec §5.1.3 step 9]:
   > "The ID Token MUST contain a `nonce` Claim."
   The nonce in the JWT must match a nonce previously issued by this tool in
   Step 2 (binding), and must not have been used before (replay prevention).
   Both checks are delegated to `CallbackBehaviour.validate_nonce/2`.
13. **Parse claims** — `LaunchClaims.from_json(jwt_body)` [Core §5.3, §5.4]
14. **Validate required LTI claims** [Core §5.3]:
    - `message_type` MUST equal `"LtiResourceLinkRequest"` [Core §5.3.1]
    - `version` MUST equal `"1.3.0"` [Core §5.3.2]
    - `deployment_id` MUST be present [Core §5.3.3]
    - `target_link_uri` MUST be present [Core §5.3.4]
    - `resource_link` MUST be present with `id` sub-field [Core §5.3.5]
    - `roles` MUST be present (may be empty array) [Core §5.3.7]
    - `sub` MUST be present (except anonymous launches) [Core §5.3.6]
15. **Validate `deployment_id`** — must be known for this registration
   > [Core §5.3.3]: "The deployment_id is a stable locally unique identifier
   > within the iss (Issuer)."
16. **Build `LaunchContext`** from validated claims [Sec §5.1.1.4]
   > [Core §5.3.4]: "A Tool should rely on this claim rather than the initial
   > `target_link_uri` to do the final redirection, since the login initiation
   > request is unsigned."
   The `LaunchContext.target_link_uri` (from the signed JWT) should be used
   by the host app for the final redirect, not the unsigned value from Step 1.

**Tests** (mapped to [Cert §6.1] tool certification scenarios):

*Known "Bad" Payloads [Cert §6.1.1]*:
- Missing KID → `Security.KidMissing` [Cert §6.1.1 "No KID Sent in JWT header"]
- Incorrect KID → `Security.KidNotFound` [Cert §6.1.1 "Incorrect KID in JWT header"]
- Wrong LTI version → `Invalid.InvalidClaim` [Cert §6.1.1 "Wrong LTI Version"]
- Missing version → `Invalid.MissingClaim` [Cert §6.1.1 "No LTI Version"]
- Invalid JSON → `Invalid.InvalidJson` [Cert §6.1.1 "Invalid LTI message"]
- Missing claims → `Invalid.MissingClaim` [Cert §6.1.1 "Missing LTI Claims"]
- Invalid timestamps → `Security.TokenExpired` [Cert §6.1.1 "Timestamps Incorrect"]
- Missing message_type → `Invalid.MissingClaim` [Cert §6.1.1 "messsage_type Claim Missing"]
- Missing role → `Invalid.MissingClaim` [Cert §6.1.1 "role Claim Missing"]
- Missing deployment_id → `Invalid.MissingClaim` [Cert §6.1.1 "deployment_id Claim Missing"]
- Missing resource_link_id → `Invalid.MissingClaim` [Cert §6.1.1 "resource_link_id Claim Missing"]
- Missing sub → `Invalid.MissingClaim` [Cert §6.1.1 "user Claim Missing"]
- State mismatch → `Security.StateMismatch` [Sec §7.3.1]

*Valid Teacher Launches [Cert §6.1.2]*:
- Valid Instructor Launch [Cert §6.1.2]
- Valid Instructor Launch with Roles [Cert §6.1.2]
- Valid Instructor Launch Short Role [Cert §6.1.2]
- Valid Instructor Launch Unknown Role [Cert §6.1.2]
- Valid Instructor Launch No Role [Cert §6.1.2]
- Valid Instructor Launch Email Only [Cert §6.1.2]
- Valid Instructor Launch Names Only [Cert §6.1.2]
- Valid Instructor No PII [Cert §6.1.2]
- Valid Instructor Email Without Context [Cert §6.1.2]

*Valid Student Launches [Cert §6.1.3]*:
- Valid Student Launch [Cert §6.1.3]
- Valid Student Launch with Roles [Cert §6.1.3]
- Valid Student Launch Short Role [Cert §6.1.3]
- Valid Student Launch Unknown Role [Cert §6.1.3]
- Valid Student Launch No Role [Cert §6.1.3]
- Valid Student Launch Email Only [Cert §6.1.3]
- Valid Student Launch Names Only [Cert §6.1.3]
- Valid Student No PII [Cert §6.1.3]
- Valid Student Email Without Context [Cert §6.1.3]

---

### 2.11 `Ltix.LaunchContext` — Validated Launch Output

**Spec basis**: [Sec §5.1.1.4] Step 4: Resource is displayed — "Tool validates
ID token, verifies state, then displays resource."

The successful output of the OIDC callback — wraps the parsed `%LaunchClaims{}`
along with the resolved `%Registration{}` and `%Deployment{}`:

```elixir
defstruct [
  :claims,         # %LaunchClaims{} — all parsed claim data [Core §5.3, §5.4, §6.1]
  :registration,   # %Registration{} — the matched platform registration [Core §3.1.2]
  :deployment      # %Deployment{} — the matched deployment [Core §3.1.3]
]

@type t :: %__MODULE__{
  claims: LaunchClaims.t(),
  registration: Registration.t(),
  deployment: Deployment.t()
}
```

This keeps the validated launch self-contained. Callers access claims via
`context.claims.roles`, `context.claims.resource_link.id`, etc. The
`%LaunchClaims{}` struct handles all claim data; `LaunchContext` adds the
resolved registration/deployment context that was used during validation.

---

### 2.12 `Ltix.Errors` — Structured Error Types (Splode)

Uses [Splode](https://hexdocs.pm/splode) for structured, composable errors that
integrate naturally with Ash Framework and other Splode-aware libraries.

```elixir
defmodule Ltix.Errors do
  use Splode,
    error_classes: [
      invalid: Ltix.Errors.Invalid,       # Malformed input (bad JWT, missing claims)
      security: Ltix.Errors.Security,      # Security violations (sig, exp, nonce)
      unknown: Ltix.Errors.Unknown         # Unexpected / catch-all
    ],
    unknown_error: Ltix.Errors.Unknown.Unknown
end
```

**Error class: `invalid`** — Spec-violating input data:

```elixir
defmodule Ltix.Errors.Invalid.MissingClaim do
  use Splode.Error, fields: [:claim, :spec_ref], class: :invalid

  def message(%{claim: claim, spec_ref: ref}) do
    "Missing required LTI claim: #{claim} [#{ref}]"
  end
end
```

**Error class: `security`** — Security framework violations:

```elixir
defmodule Ltix.Errors.Security.SignatureInvalid do
  use Splode.Error, fields: [:spec_ref], class: :security

  def message(%{spec_ref: ref}) do
    "JWT signature verification failed [#{ref}]"
  end
end
```

Each error module carries a `spec_ref` field with a human-readable pointer to the
violated spec passage (e.g., `"Sec §5.1.3 step 1"`), making debugging
straightforward and reinforcing the reference-implementation nature of the library.

Individual error modules:

| Module | Class | Spec ref |
|---|---|---|
| `Invalid.MissingClaim` | `:invalid` | Varies: [Core §5.3.1] message_type, [Core §5.3.2] version, [Core §5.3.3] deployment_id, [Core §5.3.5] resource_link.id, [Core §5.3.6] sub, [Core §5.3.7] roles |
| `Invalid.InvalidClaim` | `:invalid` | Varies: [Core §5.3.1] wrong message_type, [Core §5.3.2] wrong version |
| `Invalid.InvalidJson` | `:invalid` | [Cert §6.1.1 "Invalid LTI message"] |
| `Invalid.MissingParameter` | `:invalid` | [Sec §5.1.1.1] missing iss/login_hint/target_link_uri |
| `Invalid.RegistrationNotFound` | `:invalid` | [Sec §5.1.1.1] unknown issuer+client_id |
| `Invalid.DeploymentNotFound` | `:invalid` | [Core §3.1.3; Core §5.3.3] unknown deployment_id |
| `Security.SignatureInvalid` | `:security` | [Sec §5.1.3 step 1] "Validating JWT signature" |
| `Security.TokenExpired` | `:security` | [Sec §5.1.3 step 7] "Tool MUST NOT accept after exp" |
| `Security.IssuerMismatch` | `:security` | [Sec §5.1.3 step 2] "iss exactly matches issuer identifier" |
| `Security.AudienceMismatch` | `:security` | [Sec §5.1.3 step 3] "aud contains Tool's client_id" |
| `Security.AlgorithmNotAllowed` | `:security` | [Sec §5.1.3 step 6; Sec §7.3.2] RS256 only |
| `Security.NonceMissing` | `:security` | [Sec §5.1.3 step 9] "The ID Token MUST contain a nonce Claim" |
| `Security.NonceReused` | `:security` | [Sec §5.1.3 step 9] "nonce not previously received" |
| `Security.NonceNotFound` | `:security` | [Sec §5.1.3 step 9] nonce not previously issued by this tool |
| `Security.StateMismatch` | `:security` | [Sec §7.3.1] "state parameter MUST be used" for CSRF |
| `Security.KidMissing` | `:security` | [Cert §6.1.1 "No KID Sent in JWT header"] |
| `Security.KidNotFound` | `:security` | [Cert §6.1.1 "Incorrect KID in JWT header"] |
| `Unknown.Unknown` | `:unknown` | — |

---

### 2.13 `Ltix` — Public API Facade

The top-level module exposes exactly two functions for the OIDC launch flow,
corresponding to the two endpoints a tool must expose per [Sec §5.1.1]:

```elixir
@doc """
Handle OIDC third-party initiated login [Sec §5.1.1.1] and build
authentication request [Sec §5.1.1.2].

The caller receives the full redirect URI (to the platform's auth endpoint)
and the `state` value. The caller is responsible for:
1. Storing `state` in the user's session for CSRF verification [Sec §7.3.1]
2. Redirecting the user agent to `redirect_uri`

The nonce is stored via `CallbackBehaviour.store_nonce/2` automatically.
"""
@spec handle_login(params :: map(), callback_module :: module(), opts :: keyword()) ::
  {:ok, %{redirect_uri: String.t(), state: String.t()}} | {:error, Error.t()}

@doc """
Handle authentication response [Sec §5.1.1.3], validate ID token [Sec §5.1.3],
parse claims [Core §5.3, §5.4], and display resource [Sec §5.1.1.4].

The caller passes in the POST params (containing `id_token` and `state`) and
the `state` value from the session. The library handles all validation per
[Sec §5.1.3] and returns a validated `LaunchContext`.

> [Core §5.3.4]: "A Tool should rely on [the target_link_uri claim in the
> signed JWT] rather than the initial target_link_uri to do the final
> redirection, since the login initiation request is unsigned."

The caller should use `context.claims.target_link_uri` for the final redirect.
"""
@spec handle_callback(params :: map(), state :: String.t(), callback_module :: module(), opts :: keyword()) ::
  {:ok, LaunchContext.t()} | {:error, Error.t()}
```

- `handle_login/3` — Steps 1+2 [Sec §5.1.1.1, §5.1.1.2]: receives platform login initiation, returns redirect URL
- `handle_callback/4` — Steps 3+4 [Sec §5.1.1.3, §5.1.1.4, §5.1.3]: receives auth response, returns validated launch

---

## 3. Implementation Order

The order is driven by dependency flow and TDD. We build leaf modules first
(no dependencies on other Ltix modules), then compose upward.

| Phase | Module | Depends on | Test focus |
|---|---|---|---|
| **1** | `Ltix.Registration` | — | Struct validation [Core §3.1.3; Sec §5.1.2] |
| **1** | `Ltix.Deployment` | — | Struct validation [Core §3.1.3] |
| **1** | `Ltix.Errors` (Splode) | `splode` | Error classes & modules |
| **1** | `Ltix.CallbackBehaviour` | — | Behaviour definition |
| **1** | `test/support/jwt_helper.ex` | `jose` | RSA key gen [Sec §6.1], JWT minting [Sec §5.1.2] |
| **2** | `Ltix.LaunchClaims.Role` | — | Role parsing [Core §A.2]; [Cert §6.1.2, §6.1.3] role scenarios |
| **2** | Nested claim structs | — | Required/optional field parsing [Core §5.3.5, §5.4.1–§5.4.5, §6.1] |
| **2** | `Ltix.LaunchClaims` | `Role`, nested structs | Key classification, from_json/2, extensions [Core §5.3, §5.4, §5.4.7] |
| **3** | `Ltix.JWT.KeySet` | `jose`, `req` | JWKS fetch [Sec §6.3, §6.4]; kid lookup [Cert §6.1.1] |
| **3** | `Ltix.JWT.Token` | `jose`, `KeySet` | ID Token validation [Sec §5.1.3]; [Cert §6.1.1] bad payloads |
| **4** | `Ltix.LaunchContext` | `LaunchClaims` | Struct construction |
| **4** | `Ltix.OIDC.LoginInitiation` | `Registration`, `CallbackBehaviour` | Login params [Sec §5.1.1.1] |
| **4** | `Ltix.OIDC.AuthenticationRequest` | `Registration` | Auth redirect [Sec §5.1.1.2] |
| **5** | `Ltix.OIDC.Callback` | `Token`, `LaunchClaims`, `KeySet`, `CallbackBehaviour` | Full validation [Sec §5.1.3] |
| **6** | `Ltix` (facade) | `OIDC.*` | Two-function public API [Sec §5.1.1] |
| **7** | Integration tests | All | [Cert §6.1] end-to-end scenarios |

---

## 4. Test Strategy

### 4.1 Test Helpers (`test/support/jwt_helper.ex`)

Generates RSA key pairs [Sec §6.1] and mints JWTs [Sec §5.1.2] for tests.
Every test that needs a JWT uses this helper rather than static fixtures,
ensuring tests are self-contained and key material is never accidentally committed.

```elixir
defmodule Ltix.Test.JWTHelper do
  @moduledoc "Generate RSA keys [Sec §6.1] and sign JWTs [Sec §5.1.2] for testing."

  def generate_rsa_key_pair() do
    # Returns {private_jwk, public_jwk, kid}
    # Keys per [Sec §6.1] RSA Key; kid per [Sec §6.2] JSON Web Key
  end

  def build_jwks(public_keys) do
    # Returns a JWKS map per [Sec §6.3] Key Set URL format
  end

  def mint_id_token(claims, private_key, opts \\ []) do
    # Signs claims as a JWT with RS256 per [Sec §5.1.2; Sec §5.4]
    # opts: :kid, :alg (for testing bad alg scenarios per [Cert §6.1.1])
  end

  def valid_lti_claims(overrides \\ %{}) do
    # Returns a complete, valid LtiResourceLinkRequest claim set
    # per [Core §5.3] required claims + [Core §5.4] optional claims
    # Caller can override individual claims for negative tests
  end
end
```

### 4.2 Certification Scenario Mapping

Tests are organized to map directly to [Cert §6.1] test categories:

```
test/ltix/integration/certification_test.exs

describe "Known Bad Payloads [Cert §6.1.1]" do
  test "No KID Sent in JWT header"
  test "Incorrect KID in JWT header"
  test "Wrong LTI Version"
  test "No LTI Version"
  test "Invalid LTI message"
  test "Missing LTI Claims"
  test "Timestamps Incorrect"
  test "messsage_type Claim Missing"           # [sic] — matches cert suite spelling
  test "role Claim Missing"
  test "deployment_id Claim Missing"
  test "resource_link_id Claim Missing"
  test "user Claim Missing"
end

describe "Valid Teacher Launches [Cert §6.1.2]" do
  test "Valid Instructor Launch"
  test "Valid Instructor Launch with Roles"
  test "Valid Instructor Launch Short Role"
  test "Valid Instructor Launch Unknown Role"
  test "Valid Instructor Launch No Role"
  test "Valid Instructor Launch Email Only"
  test "Valid Instructor Launch Names Only"
  test "Valid Instructor No PII"
  test "Valid Instructor Email Without Context"
end

describe "Valid Student Launches [Cert §6.1.3]" do
  test "Valid Student Launch"
  test "Valid Student Launch with Roles"
  test "Valid Student Launch Short Role"
  test "Valid Student Launch Unknown Role"
  test "Valid Student Launch No Role"
  test "Valid Student Launch Email Only"
  test "Valid Student Launch Names Only"
  test "Valid Student No PII"
  test "Valid Student Email Without Context"
end
```

### 4.3 JWKS Mocking with Req.Test

For `KeySet` tests, use `Req.Test` stubs instead of Bypass. The `KeySet` module
accepts Req options (including `:plug`) so tests can intercept HTTP without a
real server:

```elixir
test "fetches and selects key by kid [Sec §6.3]" do
  {_private, public, kid} = JWTHelper.generate_rsa_key_pair()
  jwks = JWTHelper.build_jwks([{public, kid}])

  Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
    Req.Test.json(conn, jwks)
  end)

  assert {:ok, key} = KeySet.get_key(registration, kid)
end

test "returns error on network failure" do
  Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
    Req.Test.transport_error(conn, :timeout)
  end)

  assert {:error, %Ltix.Errors.Unknown.Unknown{}} = KeySet.get_key(registration, "some-kid")
end
```

This is concurrent-safe and requires no external processes. The `KeySet` module
uses `plug: {Req.Test, Ltix.JWT.KeySet}` in its Req options during test, which
is configured via application config or passed as an option.

---

## 5. Design Decisions

### 5.1 No Framework Coupling

The library works with plain maps for HTTP params. Optional `Plug`-based
convenience functions can wrap `handle_login/3` and `handle_callback/4` but are
not required. This ensures the library works with Phoenix, Plug, Bandit, or any
HTTP server.

### 5.2 Storage Agnosticism via Behaviour

The `CallbackBehaviour` lets host apps store registrations and nonces however
they choose (ETS, database, GenServer, etc.). The library never touches storage
directly. This follows the spec's separation of concerns — registration is
out-of-band per [Sec §5.1.1.1], and nonce tracking is an implementation choice
per [Sec §5.1.3 step 9].

### 5.3 State Parameter Management

The `state` value generated in `handle_login/3` is returned to the caller. The
caller is responsible for storing it (typically in a session or short-lived
cache) and passing it back to `handle_callback/4`. The library verifies the match
per [Sec §7.3.1: "state parameter MUST be used"] but does not manage session state.

### 5.4 Symmetric Keys Forbidden

> [Cert §4.2]: "The use of Symmetric Cryptosystems SHALL NOT be considered
> legal and use of them is expressly forbidden."
>
> [Cert §4.2]: "All Learning Platforms and Tools MUST provide the mechanisms
> (the libraries) for signing and verification of signatures for JWTs signed
> with RSA 256."
>
> [Cert §4.2]: "The signing of a JWT with a public key SHALL NOT be legal or
> respected. All JWT instances to be signed MUST be signed only with the
> provided private key."

The library only accepts RS256. Any JWT signed with a symmetric algorithm
(HS256, etc.) is rejected with `Security.AlgorithmNotAllowed`.

### 5.5 Clock Skew Tolerance

`exp` and `iat` validation accepts a configurable clock skew (default: 5 seconds)
via `opts`. This is a practical necessity acknowledged by [Sec §5.1.3 step 7]:
"Optionally limiting time skew using iat."

### 5.6 Forward Compatibility & Extensions

> [Core §5.4.7]: "In order to preserve forward compatibility and
> interoperability between platforms and tools, receivers of messages MUST ignore
> any claims in messages they do not understand, and not treat the presence of
> such claims as an error."

Unknown claims are preserved in `LaunchClaims.extensions` and never cause
validation failure. Extension parsers are pluggable via application config or
per-call option, allowing vendor-specific claims to be parsed into typed structs
without modifying the library.

### 5.7 User Identification — `sub` Only

> [Core §3.3]: "A user MUST have a unique identifier within the platform, which
> acts as an OpenID Provider."
>
> [Core §3.3]: "A tool or platform MUST NOT use any other attribute other than
> the unique identifier to identify a user when interacting between tool and
> platform."

The `sub` claim is the **only** authoritative user identifier. Email, name, and
other profile claims MUST NOT be used to identify or de-duplicate users. This
constraint should be documented prominently for library consumers.

### 5.8 HTTPS Everywhere

> [Sec §3]: "Implementers MUST use TLS 1.2 and/or TLS 1.3. Implementers MUST
> NOT use Secure Sockets Layer (SSL)."
>
> [Core §3.5]: "Implementers MUST use HTTPS for all URLs to resources included
> in messages and services."

All URLs (registration endpoints, JWKS URIs, service endpoints, return URLs)
MUST be HTTPS. The library validates this for registration fields and should
document it for consumers.

### 5.9 Multi-Deployment Architecture

> [Core §3.1.3]: "A tool MUST allow multiple deployments on a given platform to
> share the same `client_id` and the security contract attached to it."

The `Registration` struct represents the security contract (issuer, client_id,
endpoints). Deployments are resolved separately per message via the
`deployment_id` claim. The data model supports one-to-many from client_id to
deployment_id. The `Deployment` struct is intentionally thin — it holds only the
`deployment_id`, but the `CallbackBehaviour.get_deployment/2` callback allows
host apps to attach additional deployment-specific data.

### 5.10 AshLti-Aligned Claims Architecture

The `LaunchClaims` module mirrors AshLti's proven pattern:
- Three mapping tables (`@oidc_keys` per [Sec §5.1.2], `@lti_keys` per [Core §5.3–§5.4], `@service_keys` per [Core §6.1])
- `classify_key/1` routes every JWT key deterministically
- Nested structs with `from_json/1` for complex claims
- `%Role{type, name, sub_role, uri}` per [Core §A.2] with predicates and filters
- `parse_all/1` splits recognized/unrecognized roles gracefully
- `with`-chain short-circuits on first nested parse error
- Pluggable extension parsers per [Core §5.4.7] (config + per-call, per-call wins)

This ensures AshLti can eventually depend on Ltix for claim parsing with zero
impedance mismatch.

---

## 6. Out of Scope for v0.1.0

These are explicitly deferred:

- **Platform side** — Only tool side is implemented
- **Advantage service API calls** — AGS [Core §6.2], NRPS, Deep Linking *endpoints*
  are parsed from launch claims [Core §6.1], but no HTTP calls to those services
  are made. Service calls require OAuth 2.0 Client Credentials Grant [Sec §4.1]
  which is deferred.
  - *Certification impact*: [Cert §6.3] NRPS (5 tests) and [Cert §6.4] AGS
    (1+ tests) require service API calls. These cert scenarios are deferred.
- **Deep Linking responses** — [Cert §6.2] Deep Linking message testing (7 tests)
  requires the tool to construct and sign a Deep Linking Response JWT. This
  requires the tool to have its own JWKS endpoint and signing infrastructure.
  Deferred to v0.2.0.
  - *When implemented, the tool's JWKS endpoint MUST*:
    - Serve over TLS [Sec §3]
    - Include `kid` on every key, even if only one [Sec §6.3]
    - Include `n` and `e` for RSA keys [Sec §6.2]
    - Not reuse `kid` for different keys of same `kty` [Sec §6.3]
  - *Tool-signed JWTs MUST*:
    - Use RS256 (MUST NOT use `none`) [Sec §5.4]
    - Include `kid` in JOSE header [Sec §6.3]
    - SHOULD NOT use `x5u`, `x5c`, `jku`, or `jwk` header fields [Sec §5.3]
- **Tool-originating messages** [Sec §5.2] — Not needed for core launch
- **OAuth 2.0 Client Credentials Grant** [Sec §4.1, §4.1.1] — Only needed for
  service calls. When implemented, the client assertion JWT must include:
  `iss` = `sub` = tool's `client_id`, `aud` = token endpoint URL, `iat`, `exp`
  (typically 5 min after iat), `jti` (unique identifier) [Sec §4.1.1]
- **Custom variable substitution** [Core §5.4.6.1] — Platform-side concern
- **Plug integration module** — Can be added in v0.2.0 as a convenience layer

---

## 7. Acceptance Criteria for v0.1.0

The release is ready when:

1. All [Cert §6.1.1] Known "Bad" Payloads tests pass (12 scenarios)
2. All [Cert §6.1.2] Valid Teacher Launches tests pass (9 scenarios)
3. All [Cert §6.1.3] Valid Student Launches tests pass (9 scenarios)
4. Full end-to-end launch flow test passes (login [Sec §5.1.1.1] → redirect [Sec §5.1.1.2] → callback [Sec §5.1.1.3] → LaunchContext [Sec §5.1.1.4])
5. Zero dependencies beyond `jose`, `req`, `splode`, and `plug` (optional; no test-only deps needed for HTTP mocking)
6. Every public function has `@spec` and `@doc` with spec references
7. `mix test` passes with zero warnings
8. Library can be added as a dep and used with two function calls + one behaviour impl
