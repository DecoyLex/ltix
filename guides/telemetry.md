# Telemetry

Ltix emits [`:telemetry`](https://hexdocs.pm/telemetry) events at key
boundaries. All span events emit `:start`, `:stop`, and `:exception`
suffixes with `system_time` and `duration` measurements provided by
`:telemetry.span/3`.

## OIDC flow

- `[:ltix, :login, :start | :stop | :exception]` — wraps `handle_login/3`. Use `issuer`, `client_id`, and `redirect_uri` metadata to break down measurements.

- `[:ltix, :callback, :start | :stop | :exception]` — wraps `handle_callback/3`. Use `issuer`, `client_id`, `deployment_id`, and `message_type` metadata (stop only; `nil` on error) to break down measurements.

## Advantage services

- `[:ltix, :grade_service, <action>, :start | :stop | :exception]` — wraps each grade service operation. Actions: `:list_line_items`, `:get_line_item`, `:create_line_item`, `:update_line_item`, `:delete_line_item`, `:post_score`, `:get_results`. Use `endpoint` metadata to break down measurements.

- `[:ltix, :memberships_service, <action>, :start | :stop | :exception]` — wraps each memberships service operation. Actions: `:get_members`, `:stream_members`. Use `endpoint` metadata to break down measurements.

- `[:ltix, :deep_linking, :build_response, :start | :stop | :exception]` — wraps `Ltix.DeepLinking.build_response/3`. Use `item_count` and `item_types` metadata to break down measurements.

## OAuth

- `[:ltix, :oauth, :authenticate, :start | :stop | :exception]` — wraps token acquisition via client credentials. Use `scopes_requested` metadata (start and stop) to break down measurements. `scopes_granted` and `expires_in` are available on stop (`nil` on error).

## JWKS cache

Single events (not spans), fired during `Ltix.JWT.KeySet.get_key/3`:

- `[:ltix, :jwks, :cache_hit]` — key found in cache. Metadata: `jwks_uri`, `kid`.
- `[:ltix, :jwks, :cache_miss]` — key fetched from platform. Metadata: `jwks_uri`, `kid`.

A miss is also emitted when the `kid` is not found after fetching
(before the error is returned).

## Not instrumented

| Area | Reason |
|---|---|
| HTTP requests | Req emits `[:req, :request, :*]` already |
| Storage adapter calls | Host app code — instrument your own adapter |
| JWT verification internals | Sub-steps of the callback span |
| Claim parsing | In-memory struct building; negligible cost |
| Pagination per-page | Service-level span covers the whole operation |
