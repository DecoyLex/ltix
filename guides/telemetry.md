# Telemetry

Ltix emits [`:telemetry`](https://telemetry.hexdocs.pm) events at key boundaries. All span events emit `:start`, `:stop`, and `:exception` suffixes with `system_time` and `duration` measurements provided by `:telemetry.span/3`.

## OIDC flow

- `[:ltix, :login, :start | :stop | :exception]` wraps `handle_login/3`. Use `issuer`, `client_id`, and `redirect_uri` metadata to break down measurements.

- `[:ltix, :callback, :start | :stop | :exception]` wraps `handle_callback/3`. Use `issuer`, `client_id`, `deployment_id`, and `message_type` metadata (stop only, `nil` on error) to break down measurements.

## Advantage services

- `[:ltix, :grade_service, <action>, :start | :stop | :exception]` wraps each grade service operation. The actions are `:list_line_items`, `:get_line_item`, `:create_line_item`, `:update_line_item`, `:delete_line_item`, `:post_score`, `:list_results`, `:stream_line_items`, and `:stream_results`. The `endpoint` metadata is the URL the operation requests, or `nil` when no URL could be resolved. Use it to break down measurements.

- `[:ltix, :memberships_service, <action>, :start | :stop | :exception]` wraps each memberships service operation. The actions are `:list_members` and `:stream_members`. The `endpoint` metadata is the memberships URL the operation requests, or `nil` when no URL could be resolved. Use it to break down measurements.

- `[:ltix, :deep_linking, :build_response, :start | :stop | :exception]` wraps `Ltix.DeepLinking.build_response/3`. Use `item_count` and `item_types` metadata to break down measurements.

Bang variants such as `list_members!/2` emit the same events as their non-bang functions. A `stream_*` span covers only the first page.

## OAuth

- `[:ltix, :oauth, :authenticate, :start | :stop | :exception]` wraps the token request made by `Ltix.OAuth.authenticate/2` and each service's `authenticate/2`. Use `scopes_requested` metadata (start and stop) to break down measurements. `scopes_granted` and `expires_in` are available on stop (`nil` on error).

- `[:ltix, :oauth, :refresh, :start | :stop | :exception]` wraps the token request made by `Ltix.OAuth.Client.refresh/1`, `Ltix.OAuth.Client.force_refresh/1`, and their bang variants. It has the same metadata as `[:ltix, :oauth, :authenticate]`. `refresh/1` emits nothing when the token has not expired.

## Key set cache

These are single events (not spans), emitted during `Ltix.JWT.KeySet.get_key/3`.

- `[:ltix, :jwks, :cache_hit]` - key found in cache. The metadata is `jwks_uri` and `kid`.
- `[:ltix, :jwks, :cache_miss]` - key fetched from platform. The metadata is `jwks_uri` and `kid`.

A miss is also emitted when the `kid` is not found, before the error is returned.

## Not instrumented

| Area | Reason |
|---|---|
| HTTP requests | Finch emits `[:finch, :request, :*]` already |
| Storage adapter calls | Application code. Instrument your own adapter. |
| JWT verification internals | Sub-steps of the callback span |
| Claim parsing | In-memory struct building with negligible cost |
| Pagination per-page | Service-level span covers the whole operation for `list_*` calls |

## Next steps

- [Error Handling](error-handling.md) - the errors logins, launches, and service calls return
- [Advantage Services](advantage-services.md) - the service calls the OAuth and service events measure
