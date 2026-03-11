# Credo Refactor Plan

128 issues from `mix credo --strict` after config update, broken into six check
types across four phases.

## Issue Summary

| Check            | Issues | Lib files | Test files |
| ---------------- | -----: | --------: | ---------: |
| MultiAlias       |     49 |        16 |         15 |
| SinglePipe       |     31 |         9 |          7 |
| ImplTrue         |     23 |         3 |          3 |
| PipeChainStart   |     13 |         6 |          3 |
| DuplicatedCode   |      8 |         4 |          2 |
| OnePipePerLine   |      4 |         1 |          2 |

---

## Phase 1 — Mechanical rewrites (MultiAlias, OnePipePerLine)

**53 issues.** Pure syntax changes with no behavioral risk.

### MultiAlias (49 issues, 31 files)

Expand every grouped alias `alias Foo.{Bar, Baz}` into individual lines.

Files (by area):
- **Core lib:** `ltix.ex`, `deployment.ex`, `launch_claims.ex`, `launch_context.ex`,
  `storage_adapter.ex`
- **OIDC:** `oidc/callback.ex`, `oidc/login_initiation.ex`
- **OAuth:** `oauth.ex`, `oauth/client.ex`, `oauth/client_credentials.ex`
- **JWT:** `jwt/token.ex`
- **Services:** `grade_service.ex`, `memberships_service.ex`,
  `memberships_service/member.ex`
- **Test helpers:** `test.ex`, `test/platform.ex`
- **Test files:** 15 files (see Issue Summary)

### OnePipePerLine (4 issues, 3 files)

Break multi-pipe expressions that share a line into separate lines.

- `lib/ltix/memberships_service.ex`
- `test/ltix/jwk_test.exs`
- `test/ltix/jwt/token_test.exs`

**Commit:** `style: expand multi-aliases and fix one-pipe-per-line`

---

## Phase 2 — Pipeline hygiene (SinglePipe, PipeChainStart)

**44 issues.** Overlapping locations — many SinglePipe sites are also
PipeChainStart violations. Fix together per-file to avoid double-touching.

### SinglePipe (31 issues, 16 files)

Replace `value |> fun()` with `fun(value)` when the pipeline is only one
step long.

### PipeChainStart (13 issues, 9 files)

Rewrite pipes that start with a function call so they start with a raw value.
Typical fix: pull the first call out into a variable or nest it as the
argument.

**Overlap files** (both checks fire):
- `lib/ltix/jwt/key_set.ex`
- `lib/ltix/launch_claims/role.ex`
- `lib/ltix/memberships_service.ex`
- `lib/ltix/memberships_service/membership_container.ex`
- `lib/ltix/oidc/login_initiation.ex`
- `lib/ltix/test.ex`
- `test/support/jwt_helper.ex`
- `test/support/test_storage_adapter.ex`

**SinglePipe only:**
- `lib/ltix/grade_service.ex`, `lib/ltix/grade_service/score.ex`
- `lib/ltix/oidc/authentication_request.ex`
- `test/ltix/integration/full_launch_test.exs`
- `test/ltix/jwt/token_test.exs`
- `test/ltix/oidc/authentication_request_test.exs`
- `test/ltix/oidc/login_initiation_test.exs`
- `test/ltix_test.exs`

**PipeChainStart only:**
- `test/ltix/integration/full_launch_test.exs`

**Commit:** `refactor: fix single-pipe and pipe-chain-start issues`

---

## Phase 3 — ImplTrue (23 issues, 6 files)

Replace `@impl true` with `@impl ModuleName` to explicitly name the
behaviour being implemented. Requires reading each file to identify the
correct behaviour module.

Files:
- `lib/ltix/jwt/key_set/cachex_cache.ex` (3) — implements `Ltix.JWT.KeySet.Cache`
- `lib/ltix/jwt/key_set/ets_cache.ex` (3) — implements `Ltix.JWT.KeySet.Cache`
- `lib/ltix/test/storage_adapter.ex` (4) — implements `Ltix.StorageAdapter`
- `test/ltix/oauth/client_test.exs` (3) — mock behaviour callbacks
- `test/ltix/oauth_test.exs` (6) — mock behaviour callbacks
- `test/support/test_storage_adapter.ex` (4) — implements `Ltix.StorageAdapter`

For test mocks, identify which behaviour they implement (e.g. `Req.Steps`,
`Ltix.StorageAdapter`) and use that as the `@impl` target.

**Commit:** `style: replace @impl true with explicit behaviour names`

---

## Phase 4 — Duplicate code (8 issues, 4 pairs)

Requires design decisions — consolidate shared logic.

### Pair 1: `mint_id_token` (mass 67)
- `lib/ltix/test.ex:282` ↔ `test/support/jwt_helper.ex:40`
- The `test/support/` file predates `lib/ltix/test.ex` (the public test helper
  module). Migrate callers of `JWTHelper.mint_id_token/2` to use
  `Ltix.Test.mint_id_token/2`, then remove the duplicate.

### Pair 2: `validate_nonce` (mass 61)
- `lib/ltix/test/storage_adapter.ex:84` ↔ `test/support/test_storage_adapter.ex:65`
- Same situation: the `test/support/` adapter is the older copy. Migrate
  internal tests to use `Ltix.Test.StorageAdapter` and remove the duplicate.

### Pair 3: `valid_lti_claims` (mass 44)
- `lib/ltix/test.ex:308` ↔ `test/support/jwt_helper.ex:67`
- Same as Pair 1 — consolidate into `Ltix.Test` and remove from `JWTHelper`.

### Pair 4: `classify_keys` (mass 47)
- `lib/ltix/grade_service/result.ex:75` ↔ `lib/ltix/grade_service/line_item.ex:119`
- Extract a shared private function into a common location (e.g.
  `Ltix.GradeService.Helpers` or inline into the parent `Ltix.GradeService`
  module) and call it from both.

**Commits:**
- `refactor(test): consolidate duplicate test helpers into Ltix.Test`
- `refactor(ags): extract shared classify_keys helper`

---

## Execution Notes

- Run `mix test` after each phase to catch regressions.
- Run `mix credo --strict` after each phase to confirm the issue count drops.
- Phases 1–3 are mechanical and safe to batch. Phase 4 involves design choices
  and should be reviewed per-pair.
