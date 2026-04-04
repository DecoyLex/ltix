# Remove `to_json` — Encoder Protocols and `to_map` Implementation Plan

## Overview

Replace all `to_json` functions with the appropriate mechanism:

- **Score, LineItem**: implement `JSON.Encoder` / `Jason.Encoder` protocols, guarded by `Code.ensure_loaded?/1`. Remove `to_json` entirely; callers pass structs directly to `encode!`.
- **ContentItem protocol**: rename `to_json/1` → `to_map/1`. The deep linking path embeds maps into JOSE JWT claims, so the map form is genuinely needed.
- **LineItem validation**: extract from `to_json` into a standalone `validate/1`, called explicitly by `GradeService` before encoding.

## Current State Analysis

### Score (`lib/ltix/grade_service/score.ex:170`)
- `to_json/1` converts `%Score{}` → camelCase map (PascalCase enum values, ISO 8601 timestamp, optional field omission, extensions merge)
- Called from `GradeService.post_score` (`grade_service.ex:445`): `json = Score.to_json(score)` → passed to `build_request` → `json_library.encode!(body)`
- Returns `map()` directly (no result tuple)

### LineItem (`lib/ltix/grade_service/line_item.ex:101`)
- `to_json/1` validates label + score_maximum, then delegates to private `serialize/1` (`line_item.ex:108`)
- Called from `create_line_item` (`grade_service.ex:305`) and `update_line_item` (`grade_service.ex:348`): `{:ok, json} <- LineItem.to_json(item)`
- Returns `{:ok, map()} | {:error, Exception.t()}`
- Private `serialize/1` already exists as the pure serialization half

### ContentItem protocol (`lib/ltix/deep_linking/content_item.ex:36`)
- Protocol with `item_type/1` and `to_json/1` callbacks
- 6 implementations: Map, Link, LtiResourceLink, Image, HtmlFragment, File
- Called from `DeepLinking.build_response` (`deep_linking.ex:113`): `Enum.map(items, &ContentItem.to_json/1)` → maps embedded in JWT claims → signed by JOSE
- Returns `%{String.t() => any()}`

### JSON library detection (`lib/ltix/app_config.ex:6-25`)
- Already detects `JSON` (Elixir 1.18+) → `Jason` → user-configured at compile time
- Encoder protocol guards should mirror this pattern

### Test support (`lib/ltix/test.ex:541-544`)
- `line_item_to_json/1` calls `LineItem.to_json` and unwraps for `Req.Test.json/2`

## Desired End State

- No function named `to_json` exists anywhere in the codebase
- `Score` and `LineItem` implement `JSON.Encoder` and/or `Jason.Encoder` (whichever is available)
- `ContentItem` protocol callback is `to_map/1`
- `LineItem` has a public `validate/1` separate from serialization
- `GradeService` call sites pass structs directly to `build_request` (Score, LineItem)
- `Ltix.Test` inlines the LineItem map conversion
- All existing tests pass (updated to reflect new API)
- All doctests updated

### Key Discoveries:
- `build_request/6` (`grade_service.ex:628-634`) calls `AppConfig.json_library!().encode!(body)` — encoder protocols dispatch correctly here
- JOSE JWT path (`deep_linking.ex:208`) uses `JOSE.JWT.from_map(claims)` — needs plain maps, not structs
- `LineItem.serialize/1` (`line_item.ex:108-117`) is already the pure serialization logic, separate from validation
- `@reverse_keys` (`line_item.ex:66`) maps struct fields to JSON keys — reusable in encoder impl

## What We're NOT Doing

- Not adding encoder protocol impls for ContentItem types (they go through JOSE, not `json_library.encode!`)
- Not changing `from_json` on any module
- Not refactoring the `build_request` function signature
- Not changing `AppConfig.json_library!` detection logic

## Implementation Approach

Three phases, each independently testable and commitable. ContentItem rename first (mechanical, no logic change), then LineItem (validation extraction + encoder), then Score (encoder, simplest).

## Phase 1: Rename ContentItem `to_json` → `to_map`

### Overview
Purely mechanical rename across the protocol definition, all 6 implementations, the single call site, all tests, and all doctests.

### Changes Required:

#### 1. Protocol definition
**File**: `lib/ltix/deep_linking/content_item.ex`
**Changes**: Rename callback `to_json/1` → `to_map/1` in both `@doc`, `@spec`, and `def`. Update `@moduledoc` example.

```elixir
# Line 16 (moduledoc example)
def to_map(item) do
```

```elixir
# Line 34-36
@doc "Serialize the content item to a JSON-compatible map."
@spec to_map(t) :: %{String.t() => any()}
def to_map(content_item)
```

```elixir
# Line 43-44 (Map impl)
def to_map(map) when is_map(map), do: map
def to_map(_), do: raise(ArgumentError, "Invalid content item: expected a map")
```

#### 2. All content item implementations
**Files**: `link.ex`, `lti_resource_link.ex`, `image.ex`, `html_fragment.ex`, `file.ex`
**Changes**: Rename `def to_json(item)` → `def to_map(item)` in each `defimpl ContentItem` block. Update `@doc` text and doctests in each.

Doctests change from e.g.:
```elixir
iex> json = Ltix.DeepLinking.ContentItem.Link.to_json(link)
```
to:
```elixir
iex> json = Ltix.DeepLinking.ContentItem.Link.to_map(link)
```

#### 3. Call site
**File**: `lib/ltix/deep_linking.ex:113`
**Changes**:
```elixir
# Before
items_json = Enum.map(items, &ContentItem.to_json/1)
# After
items_json = Enum.map(items, &ContentItem.to_map/1)
```

#### 4. Tests
**Files**: All test files under `test/ltix/deep_linking/content_item/`
**Changes**: Rename all `describe "to_json/1"` → `describe "to_map/1"` and update all `ContentItem.to_json(` calls to `ContentItem.to_map(`.

Test files:
- `test/ltix/deep_linking/content_item/map_test.exs`
- `test/ltix/deep_linking/content_item/html_fragment_test.exs`
- `test/ltix/deep_linking/content_item/image_test.exs`
- `test/ltix/deep_linking/content_item/file_test.exs`
- `test/ltix/deep_linking/content_item/link_test.exs`
- `test/ltix/deep_linking/content_item/lti_resource_link_test.exs`

### Success Criteria:

#### Automated Verification:
- [x] `mix test test/ltix/deep_linking/` passes
- [x] `mix compile --warnings-as-errors`
- [x] `mix format --check-formatted`
- [x] `mix credo --strict`
- [x] No references to `to_json` remain in `lib/ltix/deep_linking/` or `test/ltix/deep_linking/`

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to the next phase.

---

## Phase 2: LineItem — extract validation, add encoder protocols

### Overview
Separate `LineItem.to_json/1` into `validate/1` (public) + encoder protocol impls. Update `GradeService` call sites to validate explicitly, then pass the struct to `build_request`.

### Changes Required:

#### 1. Extract `validate/1` and add encoder impls
**File**: `lib/ltix/grade_service/line_item.ex`
**Changes**:

Remove `to_json/1`. Add public `validate/1` that runs the existing label + score_maximum checks:

```elixir
@doc """
Validate that a line item has the required fields for publishing.

Checks that `label` is present and non-blank, and that
`score_maximum` is a positive number.

## Examples

    iex> item = %Ltix.GradeService.LineItem{label: "Quiz 1", score_maximum: 100}
    iex> Ltix.GradeService.LineItem.validate(item)
    :ok

    iex> item = %Ltix.GradeService.LineItem{label: nil, score_maximum: 100}
    iex> {:error, _} = Ltix.GradeService.LineItem.validate(item)
"""
@spec validate(t()) :: :ok | {:error, Exception.t()}
def validate(%__MODULE__{} = item) do
  with :ok <- validate_label(item.label),
       :ok <- validate_score_maximum(item.score_maximum) do
    :ok
  end
end
```

Make `serialize/1` the body of the encoder protocol impls. Add guarded encoder impls after the module:

```elixir
if Code.ensure_loaded?(JSON.Encoder) do
  defimpl JSON.Encoder, for: Ltix.GradeService.LineItem do
    def encode(item, encoder) do
      item
      |> Ltix.GradeService.LineItem.__serialize__()
      |> JSON.Encoder.Map.encode(encoder)
    end
  end
end

if Code.ensure_loaded?(Jason.Encoder) do
  defimpl Jason.Encoder, for: Ltix.GradeService.LineItem do
    def encode(item, opts) do
      item
      |> Ltix.GradeService.LineItem.__serialize__()
      |> Jason.Encode.map(opts)
    end
  end
end
```

Rename private `serialize/1` → public `__serialize__/1` (needed by the `defimpl` blocks which are outside the module). Keep `@doc false`.

```elixir
@doc false
@spec __serialize__(t()) :: map()
def __serialize__(%__MODULE__{} = item) do
  @reverse_keys
  |> Enum.reduce(%{}, fn {field, json_key}, acc ->
    case Map.fetch!(item, field) do
      nil -> acc
      value -> Map.put(acc, json_key, value)
    end
  end)
  |> Map.merge(item.extensions)
end
```

Remove `to_json/1` and its `@doc`/`@spec`.

#### 2. Update GradeService call sites
**File**: `lib/ltix/grade_service.ex`
**Changes**:

`create_line_item` (line 305):
```elixir
# Before
{:ok, json} <- LineItem.to_json(struct!(LineItem, Enum.into(opts, %{}))),
# ...
json
# After
item = struct!(LineItem, Enum.into(opts, %{})),
:ok <- LineItem.validate(item),
# ...
item
```

`update_line_item` (line 348):
```elixir
# Before
{:ok, json} <- LineItem.to_json(item),
# ...
json
# After
:ok <- LineItem.validate(item),
# ...
item
```

In both cases, the struct is now passed directly as the body to `build_request/6`, which calls `json_library.encode!(body)` — the encoder protocol dispatches correctly.

#### 3. Update test support
**File**: `lib/ltix/test.ex`
**Changes**:

Replace `line_item_to_json/1` (lines 541-544) with an inlined conversion. Each stub call site builds the map directly:

```elixir
defp line_item_to_json(%LineItem{} = item) do
  %{}
  |> maybe_put("id", item.id)
  |> maybe_put("label", item.label)
  |> maybe_put("scoreMaximum", item.score_maximum)
  |> maybe_put("resourceLinkId", item.resource_link_id)
  |> maybe_put("resourceId", item.resource_id)
  |> maybe_put("tag", item.tag)
  |> maybe_put("startDateTime", item.start_date_time)
  |> maybe_put("endDateTime", item.end_date_time)
  |> maybe_put("gradesReleased", item.grades_released)
  |> Map.merge(item.extensions)
end
```

#### 4. Update tests
**File**: `test/ltix/grade_service/line_item_test.exs`
**Changes**:

Split the existing `describe "to_json/1"` (lines 107-226) into two describes:

- `describe "validate/1"` — the 5 validation tests (label nil, label blank, score_maximum nil, score_maximum zero, score_maximum negative)
- `describe "JSON encoding"` — the 4 serialization tests (camelCase keys, excludes nil fields, extensions round-trips, includes id), updated to call `json_library.encode!` then `json_library.decode!` on the struct instead of `to_json`

### Success Criteria:

#### Automated Verification:
- [x] `mix test test/ltix/grade_service/` passes
- [x] `mix compile --warnings-as-errors`
- [x] `mix format --check-formatted`
- [x] `mix credo --strict`
- [x] No references to `LineItem.to_json` remain anywhere in the codebase
- [x] `grep -r "to_json" lib/ltix/grade_service/line_item.ex` returns nothing

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to the next phase.

---

## Phase 3: Score — add encoder protocols, remove `to_json`

### Overview
Replace `Score.to_json/1` with `JSON.Encoder` / `Jason.Encoder` impls. Score has no validation coupling, so this is the cleanest replacement.

### Changes Required:

#### 1. Add encoder impls, remove `to_json`
**File**: `lib/ltix/grade_service/score.ex`
**Changes**:

Extract the body of `to_json/1` into `__serialize__/1` (`@doc false`). Remove `to_json/1` and its `@doc`/`@spec`.

```elixir
@doc false
@spec __serialize__(t()) :: map()
def __serialize__(%__MODULE__{} = score) do
  json = %{
    "userId" => score.user_id,
    "activityProgress" => Map.fetch!(@activity_progress_to_json, score.activity_progress),
    "gradingProgress" => Map.fetch!(@grading_progress_to_json, score.grading_progress),
    "timestamp" => DateTime.to_iso8601(score.timestamp)
  }

  json
  |> maybe_put("scoreGiven", score.score_given)
  |> maybe_put("scoreMaximum", score.score_maximum)
  |> maybe_put("scoringUserId", score.scoring_user_id)
  |> maybe_put("comment", score.comment)
  |> maybe_put_submission(score.submission)
  |> Map.merge(score.extensions)
end
```

Add guarded encoder impls after the module (same pattern as LineItem):

```elixir
if Code.ensure_loaded?(JSON.Encoder) do
  defimpl JSON.Encoder, for: Ltix.GradeService.Score do
    def encode(score, encoder) do
      score
      |> Ltix.GradeService.Score.__serialize__()
      |> JSON.Encoder.Map.encode(encoder)
    end
  end
end

if Code.ensure_loaded?(Jason.Encoder) do
  defimpl Jason.Encoder, for: Ltix.GradeService.Score do
    def encode(score, opts) do
      score
      |> Ltix.GradeService.Score.__serialize__()
      |> Jason.Encode.map(opts)
    end
  end
end
```

#### 2. Update GradeService call site
**File**: `lib/ltix/grade_service.ex:445`
**Changes**:
```elixir
# Before
json = Score.to_json(score),
# After (just pass the struct directly)
```

Remove the `json = Score.to_json(score)` line. Pass `score` directly as the body argument to `build_request`.

#### 3. Update tests
**File**: `test/ltix/grade_service/score_test.exs`
**Changes**:

Rename `describe "to_json/1"` → `describe "JSON encoding"`. Update all tests to encode via `json_library.encode!` then `json_library.decode!` instead of calling `to_json` directly.

### Success Criteria:

#### Automated Verification:
- [x] `mix test` passes (full suite — 41 doctests, 821 tests, 0 failures)
- [x] `mix compile --warnings-as-errors`
- [x] `mix format --check-formatted`
- [x] `mix credo --strict`
- [x] No `to_json` function references remain (only module attribute names and unrelated test helpers)
- [x] No `__serialize__` references anywhere

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation.

---

## Testing Strategy

### Unit Tests:
- ContentItem: all existing `to_json` tests become `to_map` tests (same assertions)
- LineItem: validation tests assert `:ok` / `{:error, _}` from `validate/1`; serialization tests round-trip through `encode!` → `decode!`
- Score: serialization tests round-trip through `encode!` → `decode!`

### Encoder Protocol Coverage:
- Both `JSON.Encoder` and `Jason.Encoder` impls exist but only one will be active at compile time (whichever the host app provides)
- Tests exercise whichever is active via `AppConfig.json_library!().encode!`

### Doctests:
- ContentItem types: update `to_json` → `to_map` in all examples
- LineItem: replace `to_json` doctest with `validate/1` doctest
- Score: remove `to_json` doctest (encoding is tested via unit tests, not doctests — `encode!` returns iodata, not inspectable maps)

## References
- Research: `.research/2026-04-03-to-json-usage.md`
- JSON library detection: `lib/ltix/app_config.ex:6-25`
- `JSON.Encoder` protocol: Elixir 1.18+ built-in
- `Jason.Encoder` protocol: `jason` hex package
