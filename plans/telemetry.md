# Telemetry Instrumentation Plan

Add `:telemetry` events at meaningful boundaries — where host apps need visibility
into launch flow health, service call latency, and cache effectiveness.

## Design Principles

- Instrument at **boundaries**, not internals
- Don't duplicate what dependencies already emit (Req emits `[:req, :request, :*]`)
- Don't wrap storage adapter calls — that's host app code, they instrument their own
- Use **span** pattern (start/stop/exception) for operations with duration
- Use **single events** for instant observations (cache hit/miss)

## Events

### OIDC Flow (spans)

#### `[:ltix, :login, :start | :stop | :exception]`

Wraps `Ltix.handle_login/3`.

| Metadata       | Type     | Description                    |
| -------------- | -------- | ------------------------------ |
| `issuer`       | `String` | Platform issuer URL            |
| `client_id`    | `String` | Client ID from login params    |
| `redirect_uri` | `String` | Redirect URI from login params |

#### `[:ltix, :callback, :start | :stop | :exception]`

Wraps `Ltix.handle_callback/3`.

| Metadata        | Type     | Description                          |
| --------------- | -------- | ------------------------------------ |
| `issuer`        | `String` | From verified token (stop only)      |
| `client_id`     | `String` | From verified token (stop only)      |
| `deployment_id` | `String` | From verified token (stop only)      |
| `message_type`  | `String` | e.g. `LtiResourceLinkRequest` (stop) |

### Advantage Services (spans)

#### `[:ltix, :grade_service, <action>, :start | :stop | :exception]`

Actions: `:list_line_items`, `:get_line_item`, `:create_line_item`,
`:update_line_item`, `:delete_line_item`, `:post_score`, `:get_results`

| Metadata   | Type     | Description          |
| ---------- | -------- | -------------------- |
| `endpoint` | `String` | Service endpoint URL |

#### `[:ltix, :memberships_service, <action>, :start | :stop | :exception]`

Actions: `:get_members`, `:stream_members`

| Metadata   | Type     | Description          |
| ---------- | -------- | -------------------- |
| `endpoint` | `String` | Service endpoint URL |

#### `[:ltix, :deep_linking, :build_response, :start | :stop | :exception]`

| Metadata     | Type       | Description             |
| ------------ | ---------- | ----------------------- |
| `item_count` | `integer`  | Number of content items |
| `item_types` | `[String]` | Types of items included |

### OAuth (span)

#### `[:ltix, :oauth, :authenticate, :start | :stop | :exception]`

Wraps token acquisition via client credentials.

| Metadata           | Type       | Description                      |
| ------------------ | ---------- | -------------------------------- |
| `scopes_requested` | `[String]` | Scopes sent in the request       |
| `scopes_granted`   | `[String]` | Scopes returned (stop only)      |
| `expires_in`       | `integer`  | Token lifetime in seconds (stop) |

### JWKS Cache (single events)

#### `[:ltix, :jwks, :cache_hit]`

| Metadata   | Type     | Description            |
| ---------- | -------- | ---------------------- |
| `jwks_uri` | `String` | Platform JWKS endpoint |
| `kid`      | `String` | Key ID that was found  |

#### `[:ltix, :jwks, :cache_miss]`

| Metadata   | Type     | Description            |
| ---------- | -------- | ---------------------- |
| `jwks_uri` | `String` | Platform JWKS endpoint |
| `kid`      | `String` | Key ID being looked up |

## What We Intentionally Don't Instrument

| Area                  | Reason                                                   |
| --------------------- | -------------------------------------------------------- |
| HTTP requests         | Req emits `[:req, :request, :*]` already                 |
| Storage adapter calls | Host app code — they should instrument their own adapter |
| JWT internals         | Sub-steps of the callback span; failures surface there   |
| Claim parsing         | Pure in-memory struct building; negligible cost          |
| Pagination per-page   | Service-level span covers the whole operation            |

## Implementation Notes

- Add `:telemetry` as a dependency (it's already a transitive dep via Req)
- Use `:telemetry.span/3` for span events
- Use `:telemetry.execute/3` for single events
- Metadata on `:start` is limited to what's known before the operation runs;
  richer metadata (like `message_type`) appears on `:stop`
- Keep measurements map minimal — `system_time` on start, `duration` on stop
  (both provided automatically by `:telemetry.span/3`)
