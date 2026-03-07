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
| `plug` | Request/response interface (optional integration) | [Sec §5.1.1.3] Authentication response via form_post |

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
        token_expired.ex           # exp in the past [Sec §5.1.3 step 6]
        issuer_mismatch.ex         # iss doesn't match registration [Sec §5.1.3 step 2]
        audience_mismatch.ex       # client_id not in aud [Sec §5.1.3 step 3]
        algorithm_not_allowed.ex   # alg is not RS256 [Sec §5.1.3 step 5; Sec §7.3.2]
        nonce_reused.ex            # Nonce previously seen [Sec §5.1.3 step 8]
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

A struct holding everything the tool knows about a registered platform:

```elixir
defstruct [
  :issuer,             # [Sec §5.1.2] iss — Platform issuer identifier (HTTPS URL, no query/fragment)
  :client_id,          # [Sec §5.1.1.2] Tool's OAuth 2.0 client_id assigned by platform
  :auth_endpoint,      # [Sec §5.1.1.1] Platform OIDC authorization endpoint URL
  :jwks_uri,           # [Sec §6.3] Platform Key Set URL for public key retrieval
  :deployment_ids      # [Core §3.1.3] Set of valid deployment_id values (max 255 ASCII, case-sensitive)
]
```

**Validation rules**:
- `issuer` MUST be HTTPS URL without query or fragment
  > [Sec §5.1.2]: "Issuer Identifier... HTTPS URL... no query or fragment"
- `client_id` MUST be non-empty string [Sec §5.1.1.2: tool must send `client_id`]
- `auth_endpoint` MUST be HTTPS URL
  > [Sec §3]: "Implementers MUST use TLS 1.2 and/or TLS 1.3... Implementers MUST NOT use Secure Sockets Layer (SSL)."
  > [Cert §4.2]: "All communication endpoints MUST be secured with TLS (SSL-alone is expressly forbidden)."
- `jwks_uri` MUST be HTTPS URL [Sec §3; Sec §6.3]
- `deployment_ids` MUST be a MapSet of strings, each ≤ 255 ASCII characters
  > [Core §5.3.3]: "The deployment_id claim's value contains a case-sensitive string... It MUST NOT exceed 255 ASCII characters in length."

**Tests**:
- Valid registration construction
- Rejection of non-HTTPS issuer [Sec §5.1.2]
- Rejection of issuer with query string [Sec §5.1.2]
- Rejection of empty client_id
- Rejection of deployment_id exceeding 255 characters [Core §5.3.3]

---

### 2.2 `Ltix.CallbackBehaviour` — Host Application Interface

**Purpose**: Decouple the library from storage. The host app implements this
behaviour to look up registrations and track nonces.

```elixir
@callback get_registration(issuer :: String.t(), client_id :: String.t()) ::
  {:ok, Registration.t()} | {:error, :not_found}

@callback get_deployment(registration :: Registration.t(), deployment_id :: String.t()) ::
  {:ok, Deployment.t()} | {:error, :not_found}

@callback validate_nonce(nonce :: String.t(), registration :: Registration.t()) ::
  :ok | {:error, :nonce_already_used}
```

**Spec basis**:
- Registration lookup: [Sec §5.1.1.1] Tool receives `iss` (and optionally
  `client_id` per [Core §4.1.3]) and must locate the correct registration.
  > [Core §4.1.3]: "The new optional parameter `client_id` specifies the client
  > id for the authorization server that should be used to authorize the
  > subsequent LTI message request."
- Nonce validation:
  > [Sec §5.1.3 step 8]: "Verifying nonce not previously received" — for
  > replay prevention.
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
3. Select key by `kid` header from JWT [Cert §6.1.1: "No KID Sent", "Incorrect KID"]
4. Cache keys with TTL; re-fetch on `kid` miss (key rotation support) [Sec §6.4]

**Tests** (TDD from [Cert §6.1.1] bad payload scenarios):
- Successful JWKS fetch and key selection by `kid` [Sec §6.3]
- `{:error, :kid_not_found}` when JWT `kid` not in JWKS [Cert §6.1.1 "Incorrect KID in JWT header"]
- `{:error, :kid_missing}` when JWT header has no `kid` field [Cert §6.1.1 "No KID Sent in JWT header"]
- Re-fetch on unknown `kid` (key rotation) [Sec §6.4]
- `{:error, :jwks_fetch_failed}` on network failure

---

### 2.4 `Ltix.JWT.Token` — JWT Decoding & Structural Validation

**Spec basis**: [Sec §5.1.3] Authentication Response Validation — the eight
validation steps tools MUST perform on the ID Token; [Sec §5.1.2] ID Token
structure; [Cert §6.1.1] Known "Bad" Payloads.

**Responsibilities** — implements [Sec §5.1.3] Authentication Response Validation:

> [Sec §5.1.3]: Tools "MUST validate ID tokens" by performing the following steps.

1. Decode JWT without verification (to extract header for `kid` lookup) [Sec §5.1.2]
2. Verify RS256 signature using platform's public key
   > [Sec §5.1.3 step 1]: "The Tool MUST Validate the signature of the ID Token
   > according to JSON Web Signature [RFC7515], Section 5.2 using the Public Key
   > from the Platform."
3. Validate algorithm is RS256
   > [Sec §7.3.2]: Framework "recommends asymmetric (RSA) keys over symmetric
   > for broader interoperability."
   >
   > [Cert §4.2]: "All Learning Platforms and Tools MUST provide the mechanisms
   > (the libraries) for signing and verification of signatures for JWTs signed
   > with RSA 256."
   >
   > [Cert §4.2]: "The use of Symmetric Cryptosystems SHALL NOT be considered
   > legal and use of them is expressly forbidden."
4. Validate structural claims:
   - `iss` matches registration issuer
     > [Sec §5.1.3 step 2]: "Verifying iss claim exactly matches Platform's
     > issuer identifier."
   - `aud` contains tool's `client_id`
     > [Sec §5.1.3 step 3]: "Confirming aud contains Tool's client_id; rejecting
     > if missing or untrusted audiences present."
   - `azp` present if multiple audiences
     > [Sec §5.1.3 step 4]: "Verifying azp present if multiple audiences."
   - `exp` not in the past
     > [Sec §5.1.3 step 6]: "Verifying current time before exp claim." Tool
     > "MUST NOT accept after this time."
   - `iat` within acceptable skew
     > [Sec §5.1.3 step 7]: "Optionally limiting time skew using iat."

**Tests** (TDD from [Cert §6.1.1]):
- Valid JWT passes all checks
- `{:error, :signature_invalid}` on tampered payload [Sec §5.1.3 step 1]
- `{:error, :token_expired}` when `exp` is in the past [Cert §6.1.1 "Timestamps Incorrect"]
- `{:error, :issuer_mismatch}` when `iss` doesn't match [Sec §5.1.3 step 2]
- `{:error, :audience_mismatch}` when `client_id` not in `aud` [Sec §5.1.3 step 3]
- `{:error, :azp_mismatch}` when multiple audiences but `azp` is wrong [Sec §5.1.3 step 4]
- `{:error, :algorithm_not_allowed}` if alg is not RS256 [Sec §5.1.3 step 5; Sec §7.3.2; Cert §4.2 "RSA 256 signing confirmation"]

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
  "exp" => :expires_at,          # [Sec §5.1.2] Expiration time; [Sec §5.1.3 step 6] Tool MUST NOT accept after
  "iat" => :issued_at,           # [Sec §5.1.2] Issued-at timestamp; [Sec §5.1.3 step 7] clock skew check
  "nonce" => :nonce,             # [Sec §5.1.2] Unique value for replay prevention; [Sec §5.1.3 step 8]
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

  # [Core §5.4.3]: Array of user IDs this user can mentor/supervise
  "role_scope_mentor" => :role_scope_mentor,

  # [Core §5.4.1]: "id (REQUIRED). Stable identifier that uniquely identifies the
  #   context. The context id MUST be locally unique to the deployment_id."
  "context" => :context,                   # → nested Context struct

  # [Core §5.3.5]: "id (REQUIRED). Opaque identifier for a placement of an LTI
  #   resource link within a context that MUST be a stable and locally unique to the
  #   deployment_id. This value MUST change if the link is copied or exported. The
  #   value of id MUST NOT exceed 255 ASCII characters in length and is case-sensitive."
  "resource_link" => :resource_link,       # → nested ResourceLink struct

  # [Core §5.4.6]: Key-value map; values with $ prefix are substitution variables
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
@spec from_json(map(), keyword()) :: {:ok, t()} | {:error, String.t()}
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
def from_json(_), do: {:error, "Context requires an \"id\" field"}
```

Type values from [Core §A.1]: `CourseTemplate`, `CourseOffering`, `CourseSection`, `Group`.

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
def from_json(_), do: {:error, "ResourceLink requires an \"id\" field"}
```

#### 2.6.3 `Ltix.LaunchClaims.LaunchPresentation` [Core §5.4.4]

Claim key: `https://purl.imsglobal.org/spec/lti/claim/launch_presentation`

```elixir
defstruct [:document_target, :height, :width, :return_url, :locale]

# [Core §5.4.4] All fields optional. document_target indicates window type;
# return_url is where platform wants control returned after tool is done.
def from_json(json), do: {:ok, ...}
```

#### 2.6.4 `Ltix.LaunchClaims.ToolPlatform` [Core §5.4.2]

Claim key: `https://purl.imsglobal.org/spec/lti/claim/tool_platform`

> [Core §5.4.2]: "guid (REQUIRED). A stable locally unique to the `iss`
> identifier for an instance of the tool platform. The value of `guid` is a
> case-sensitive string that MUST NOT exceed 255 ASCII characters in length."

```elixir
defstruct [:guid, :name, :contact_email, :description, :url,
           :product_family_code, :version]

def from_json(json), do: {:ok, ...}
```

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
def from_json(_), do: {:error, "DeepLinkingSettings requires a \"deep_link_return_url\" field"}
```

**Tests**: Each nested struct has its own test file covering:
- All fields populated
- Only required fields populated
- Missing required field returns error (Context [Core §5.4.1], ResourceLink [Core §5.3.5], DeepLinkingSettings)
- Missing optional fields default to `nil`

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

| Type | Spec section | Prefix | Core roles |
|---|---|---|---|
| Context | [Core §A.2.3] | `membership` | Administrator, ContentDeveloper, Instructor, Learner, Mentor, Manager, Member, Officer |
| Institution | [Core §A.2.2] | `institution/person#` | Administrator, Faculty, Guest, None, Other, Staff, Student, Alumni, Instructor, Learner, Member, Mentor, Observer, ProspectiveStudent |
| System (LIS) | [Core §A.2.1] | `system/person#` | Administrator, None, AccountAdmin, Creator, SysAdmin, SysSupport, User |
| System (LTI) | [Core §A.2.4] | `lti/system/person#` | TestUser |

Context roles support sub-roles per [Core §A.2.3.1] (e.g., Instructor →
TeachingAssistant, Grader, PrimaryInstructor, Lecturer, etc.).

**Tests** (`test/ltix/launch_claims/role_test.exs`):
- Full URI parsing for each context role + sub-roles [Core §A.2.3, §A.2.3.1]
- Full URI parsing for each institution role [Core §A.2.2]
- Full URI parsing for each system role [Core §A.2.1, §A.2.4]
- Short role format acceptance [Cert §6.1.2 "Valid Instructor Launch Short Role"]
- Multiple roles via `parse_all/1` [Cert §6.1.2 "Valid Instructor Launch with Roles"]
- Unknown role URIs → `:error`, collected in unrecognized [Cert §6.1.2 "Valid Instructor Launch Unknown Role"]
- Empty list accepted (anonymous launch) [Core §5.3.7.1]
- Predicate helpers return correct booleans
- Filter helpers return correct subsets
- Original URI preserved in struct
- TestUser role parsed [Core §A.2.4]

---

### 2.8 `Ltix.OIDC.LoginInitiation` — Step 1: Handle Platform Login Request

**Spec basis**: [Sec §5.1.1.1] Step 1: Third-party Initiated Login.

> [Cert §4.2.2]: "All launches will be required to go through the OIDC
> initialization and launch process. There are no exceptions to the requirement
> that OIDC always will be used."

**Input**: HTTP request from platform with parameters per [Sec §5.1.1.1]:
- `iss` (REQUIRED) — Platform issuer identifier [Sec §5.1.1.1]
- `login_hint` (REQUIRED) — Opaque login hint [Sec §5.1.1.1]
- `target_link_uri` (REQUIRED) — Tool endpoint for post-auth resource display [Sec §5.1.1.1]
- `lti_message_hint` (OPTIONAL)
  > [Core §4.1.1]: "If present in the login initiation request, the tool MUST
  > include it back in the authentication request unaltered."
- `lti_deployment_id` (OPTIONAL)
  > [Core §4.1.2]: "If included, MUST contain the same deployment id that would
  > be passed in the deployment_id claim for the subsequent LTI message launch."
- `client_id` (OPTIONAL)
  > [Core §4.1.3]: "The new optional parameter `client_id` specifies the client
  > id for the authorization server that should be used to authorize the
  > subsequent LTI message request."

**Responsibilities**:
1. Extract and validate required parameters [Sec §5.1.1.1]
2. Look up registration via callback behaviour (`iss`, optionally `client_id` per [Core §4.1.3])
3. Generate cryptographic `state` value [Sec §5.1.1.2: CSRF prevention; Sec §7.3.1]
4. Generate cryptographic `nonce` value [Sec §5.1.1.2: "nonce: Unique per-request value for replay mitigation"]
5. Return authentication request parameters for redirect to platform

**Tests**:
- Valid login initiation produces correct auth request params [Sec §5.1.1.1 → §5.1.1.2]
- Missing `iss` returns error [Sec §5.1.1.1: required]
- Missing `login_hint` returns error [Sec §5.1.1.1: required]
- Missing `target_link_uri` returns error [Sec §5.1.1.1: required]
- Unknown issuer returns error (registration not found)
- `lti_message_hint` preserved when present [Core §4.1.1: "tool must return unaltered"]
- `client_id` used for registration lookup when present [Core §4.1.3]

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
redirect_uri"; [Sec §5.1.3] Authentication Response Validation — the eight
steps tools MUST perform.

This is the heart of the library. It receives the platform's form POST and
produces either a validated `LaunchContext` or an error.

**Input**: HTTP POST with `id_token` and `state` parameters [Sec §5.1.1.3].

**Validation pipeline** — implements [Sec §5.1.3] Authentication Response
Validation. The eight numbered steps from the spec are mapped below, with
additional LTI-layer validation appended:

> [Sec §5.1.3]: Tools "MUST validate ID tokens" by performing the following.

1. **Verify `state`** matches the value generated in Step 1
   > [Sec §7.3.1]: "State parameter MUST be used" to prohibit CSRF.
2. **Extract JWT header** — get `kid` and `alg` [Sec §5.1.2]
3. **Validate `alg`** is RS256
   > [Cert §4.2]: "The use of Symmetric Cryptosystems SHALL NOT be considered
   > legal and use of them is expressly forbidden."
   >
   > [Cert §4.2]: "The signing of a JWT with a public key SHALL NOT be legal or
   > respected. All JWT instances to be signed MUST be signed only with the
   > provided private key."
4. **Fetch platform public key** by `kid` from JWKS [Sec §6.3]
   > [Cert §4.2.1]: "A Platform MUST provide a Well-Known URL (JWKS) for the
   > retrieval of Public Cryptographic keys."
5. **Verify JWT signature** — [Sec §5.1.3 step 1]:
   > "The Tool MUST Validate the signature of the ID Token according to JSON
   > Web Signature [RFC7515], Section 5.2 using the Public Key from the
   > Platform."
6. **Validate `iss`** — [Sec §5.1.3 step 2]:
   > "Verifying iss claim exactly matches Platform's issuer identifier."
7. **Validate `aud`** — [Sec §5.1.3 step 3]:
   > "Confirming aud contains Tool's client_id; rejecting if missing or
   > untrusted audiences present."
8. **Validate `azp`** — [Sec §5.1.3 step 4]:
   > "Verifying azp present if multiple audiences."
9. **Validate `exp`** — [Sec §5.1.3 step 6]:
   > "Verifying current time before exp claim." Tool "MUST NOT accept after
   > this time."
10. **Validate `iat`** — [Sec §5.1.3 step 7]:
   > "Optionally limiting time skew using iat."
11. **Validate `nonce`** — [Sec §5.1.3 step 8]:
   > "Verifying nonce not previously received" — for replay prevention.
12. **Parse claims** — `LaunchClaims.from_json(jwt_body)` [Core §5.3, §5.4]
13. **Validate `deployment_id`** — must be known for this registration
   > [Core §5.3.3]: "The deployment_id is a stable locally unique identifier
   > within the iss (Issuer)."
14. **Build `LaunchContext`** from validated claims [Sec §5.1.1.4]

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
| `Security.TokenExpired` | `:security` | [Sec §5.1.3 step 6] "Tool MUST NOT accept after exp" |
| `Security.IssuerMismatch` | `:security` | [Sec §5.1.3 step 2] "iss exactly matches issuer identifier" |
| `Security.AudienceMismatch` | `:security` | [Sec §5.1.3 step 3] "aud contains Tool's client_id" |
| `Security.AlgorithmNotAllowed` | `:security` | [Sec §5.1.3 step 5; Sec §7.3.2] RS256 only |
| `Security.NonceReused` | `:security` | [Sec §5.1.3 step 8] "nonce not previously received" |
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
"""
@spec handle_login(params :: map(), callback_module :: module(), opts :: keyword()) ::
  {:ok, %{redirect_uri: String.t(), state: String.t()}} | {:error, Error.t()}

@doc """
Handle authentication response [Sec §5.1.1.3], validate ID token [Sec §5.1.3],
parse claims [Core §5.3, §5.4], and display resource [Sec §5.1.1.4].
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
per [Sec §5.1.3 step 8].

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

### 5.7 AshLti-Aligned Claims Architecture

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
- **Tool-originating messages** [Sec §5.2] — Not needed for core launch
- **OAuth 2.0 Client Credentials Grant** [Sec §4.1, §4.1.1] — Only needed for service calls
- **Custom variable substitution** [Core §5.4.6.1] — Platform-side concern
- **Plug integration module** — Can be added in v0.2.0 as a convenience layer

---

## 7. Acceptance Criteria for v0.1.0

The release is ready when:

1. All [Cert §6.1.1] Known "Bad" Payloads tests pass (12 scenarios)
2. All [Cert §6.1.2] Valid Teacher Launches tests pass (9 scenarios)
3. All [Cert §6.1.3] Valid Student Launches tests pass (9 scenarios)
4. Full end-to-end launch flow test passes (login [Sec §5.1.1.1] → redirect [Sec §5.1.1.2] → callback [Sec §5.1.1.3] → LaunchContext [Sec §5.1.1.4])
5. Zero dependencies beyond `jose`, `req`, and `splode` (no test-only deps needed for HTTP mocking)
6. Every public function has `@spec` and `@doc` with spec references
7. `mix test` passes with zero warnings
8. Library can be added as a dep and used with two function calls + one behaviour impl
