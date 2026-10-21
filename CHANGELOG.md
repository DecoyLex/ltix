# Changelog
All notable changes to this project will be documented in this file.

## v0.2.0

Ltix 0.2 has 60 breaking changes. [Upgrading to 0.2](guides/upgrading-to-0.2.md) describes each one and what to change in your tool.

### Security

- Ltix rejects a launch whose ID token is for a different login or a different registration than its login request.
- Ltix rejects an ID token an hour after its `iat`, and a token with `iat` or `nbf` in the future.
- Ltix rejects an ID token with an untrusted audience in an `aud` list, with critical header extensions, or with a missing or malformed `iss`, `iat`, or `exp`.
- Your storage adapter records a nonce only after Ltix has verified the ID token.
- Ltix sends platform requests only over HTTPS and only to public addresses. It follows a redirect or pagination link only to the scheme, host, and port of the first request.
- A request configured to skip TLS certificate verification returns an error.
- `Ltix.JWT.KeySet` fetches each key set URL at most once every 30 seconds.
- `inspect` output omits private keys and access tokens.

### Storage adapter and keys

- Your storage adapter signs each JWT through the `key_id` and `sign` callbacks. `Ltix.Registration` has no `tool_jwk` field.
- Storage adapter callbacks receive your registration struct and the options of the call. The registration lookup receives the platform's deployment ID.
- A failing storage adapter callback returns `StorageError`.
- `Ltix.JWK` is a PEM-based struct that replaces `JOSE.JWK`. `Ltix.JWK.new/1` builds a key from a PEM, a DER, a JWK map, or a public key alone.
- `Ltix.JWT.KeySet` is a process your application starts. It replaces `Ltix.JWT.KeySet.Cache`, its implementations, and the `:jwks_cache` setting.
- `Ltix.Registration`, `Ltix.JWK`, and `Ltix.Deployment` validate their fields strictly and report `InvalidField`. Registration URLs must be HTTPS.
- `Ltix.OAuth` and `Ltix.Test` accept any struct that implements `Ltix.Registerable` or `Ltix.Deployable`.

### Launch claims and roles

- Ltix checks the type of each claim, reports every missing or invalid claim by its name in the token, and omits a malformed optional claim.
- Claim parsers can be modules that implement `Ltix.LaunchClaims.Parser`, and can override the built-in parsers. A failing claim parser returns `InvalidClaim`.
- Ltix tries custom role parsers in order from the longest prefix to the shortest.
- `Role.administrator?/1` checks the institution role. `Role.context_administrator?/1` checks the context role.
- `Role.to_uri!/1` returns the URI of any role.
- The parser options are named `claim_parsers` and `role_parsers` in every function and in the application config.

### Advantage services

- `Ltix.OAuth.authenticate/2` authenticates a custom Advantage service from a launch context. `Client.request/3` and `Client.request_pages/3` send its requests.
- `Ltix.OAuth.Client` has a `token` field with an `AccessToken`. Its `access_token`, `expires_at`, and `scopes` fields are removed.
- `AccessToken.expired?/1`, `AccessToken.to_map/1`, `AccessToken.from_map/1`, and `Client.require_unexpired/1` are added for caching and storing tokens.
- `Client.refresh/1` returns the client unchanged until its token has expired.
- A client accepts a token with fewer scopes than requested. The `require_all_scopes` option returns an error when a scope is missing. `ScopeMismatch` lists the scopes a request needed.
- Token requests include the deployment ID, and the `audience` of the registration when it has one.
- `get_results` and `get_members` are renamed to `list_results` and `list_members`. `stream_line_items`, `stream_results`, and `stream_members` stream a collection page by page.
- List functions return `CollectionTooLarge` above 10,000 entries.
- Grade operations accept an `endpoint` option. `AGSEndpoint.new/1` and `MembershipsEndpoint.new/1` validate their URLs and scopes.
- `delete_line_item/2` takes the line item as a `line_item` option.
- Scores are built from keyword lists or maps. Score, line item, and deep linking dates are `DateTime` values.
- `to_json` is replaced by `to_map` and JSON encoder protocol implementations for scores, line items, and content items. Grade results, members, and contexts have `to_map` too.
- Unrecognized member fields are in `Member` extensions. A malformed member returns an error.
- Ltix parses `Link` headers per RFC 8288, resolves relative next links, and stops paginating when a next link repeats a page.

### Deep linking

- `build_response/3` enforces `accept_presentation_document_targets` and `accept_media_types`, and reports every constraint violation with the index of the item.
- Content item options accept maps or keyword lists, including nested fields. Unknown options and extensions that would replace standard fields are rejected.
- A resource link accepts a grade service `LineItem` as its line item.
- `verify_deep_linking_response` returns `SignatureInvalid` for an invalid or malformed token.

### Errors and options

- Every fallible operation has a bang variant.
- Functions raise `InvalidOption` for an unknown or invalid option.
- A function that finds one error returns it. A function that finds several returns an error class struct with them in `errors`.
- HTTP 401 and 403 responses return `AccessDenied`. A failed request returns `TransportError` with its URL and response headers.
- Malformed tokens, token responses, and service responses return Ltix errors.
- `Ltix.Errors.status_code/1` returns the Plug status code of any exception.
- Abbreviated struct fields are spelled out, and module names use uppercase acronyms such as `LIS`, `AGS`, and `JSON`.

### Telemetry

- Ltix emits telemetry events for OIDC login and callback, key set fetches, OAuth token requests and refreshes, the grade service, the memberships service, and deep linking.

### Testing

- `Ltix.Test.assert_storage_adapter!` checks a storage adapter, including its signing callbacks.
- Ltix calls the storage adapter in your test config. `setup_platform!/1` takes `:registration` and `:deployment` functions that create the records in your storage.
- Ltix sends each request in a test to the `Req.Test` stub named after the module that makes it, such as `Ltix.GradeService`. `stub_get_members` is renamed to `stub_list_members`.
- `launch_params/2` and `build_launch_context/2` take the same options, default to the instructor role, and include a course context.
- A test can launch from several test platforms.
- `Ltix.Test` compiles without the optional Plug dependency.

### Dependencies

- Jason is an optional dependency for Elixir versions without the built-in `JSON` module.
- Ltix is tested on Elixir 1.17 through 1.20.

## v0.1.0

Initial release with support for LTI 1.3 and LTI Advantage features:

- LTI 1.3 Core: OIDC launch flow, launch claim parsing, JWT verification
- Assignment and Grade Services 2.0
- Names and Role Provisioning Service 2.0
- Deep Linking 2.0
