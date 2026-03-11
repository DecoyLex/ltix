# Refactor: NimbleOptions → Zoi

## Context

The project already has `zoi ~> 0.17` as a dependency but uses NimbleOptions
for all option validation (15 schemas across 6 modules). Zoi's `keyword/2`
type is a near-direct replacement for NimbleOptions' keyword list validation,
and `Zoi.describe/1` replaces `NimbleOptions.docs/1` for documentation
generation. This migration unifies on a single validation library and removes
NimbleOptions.

**Why Zoi over NimbleOptions?**
- Richer type system (unions, enums, structs, dynamic maps) with chainable API
- Built-in refinements (`positive()`, `non_negative()`, `min()`, `max()`)
  replace hand-rolled custom validators
- `Zoi.type_spec/1` auto-generates `@type` specs from schemas
- `Zoi.describe/1` replaces `NimbleOptions.docs/1` for doc generation
- `Zoi.codec/3` enables bidirectional parsing (decode keyword → struct,
  encode struct → keyword/map) for data transfer types
- Already a dependency — removing NimbleOptions reduces dep count

---

## 1. Translation Reference

### 1.1 Schema Definition

```elixir
# Before
@schema NimbleOptions.new!(
  name: [type: :string, required: true, doc: "The name."],
  count: [type: :pos_integer, default: 10, doc: "Page size."]
)

# After
@schema Zoi.keyword(
  name: Zoi.string(description: "The name.") |> Zoi.required(),
  count: Zoi.integer(description: "Page size.", gt: 0) |> Zoi.default(10)
)
```

### 1.2 Type Mappings

| NimbleOptions                          | Zoi                                            |
|----------------------------------------|------------------------------------------------|
| `type: :string`                        | `Zoi.string()`                                 |
| `type: :boolean`                       | `Zoi.boolean()`                                |
| `type: :atom`                          | `Zoi.atom()`                                   |
| `type: :pos_integer`                   | `Zoi.integer() \|> Zoi.positive()`             |
| `type: :keyword_list`                  | `Zoi.keyword(Zoi.any())` (pass-through) or `Zoi.keyword([...])` (structured) |
| `type: {:in, values}`                  | `Zoi.enum(values)`                             |
| `type: {:struct, Mod}`                 | `Zoi.struct(Mod)`                              |
| `type: {:or, [t1, t2]}`               | `Zoi.union([t1, t2])`                          |
| `type: {:map, :atom, :any}`            | `Zoi.map(Zoi.atom(), Zoi.any())`               |
| `type: {:map, :string, :string}`       | `Zoi.map(Zoi.string(), Zoi.string())`          |
| `type: {:map, :string, :any}`          | `Zoi.map(Zoi.string(), Zoi.any())`             |
| `type: {:map, :atom, :string}`         | `Zoi.map(Zoi.atom(), Zoi.string())`            |
| `type: {:custom, M, :f, []}`           | `Zoi.any() \|> Zoi.refine({M, :f, []})`       |
| `required: true`                       | `\|> Zoi.required()`                           |
| `default: val`                         | `\|> Zoi.default(val)`                         |
| `doc: "text"`                          | `description: "text"` option on constructor    |

### 1.3 Validation Calls

```elixir
# Before (raising)
opts = NimbleOptions.validate!(opts, @schema)

# After (raising)
opts = Zoi.parse!(@schema, opts)

# Before (error tuple)
case NimbleOptions.validate(opts, @schema) do
  {:ok, validated} -> ...
  {:error, %NimbleOptions.ValidationError{} = e} -> {:error, e}
end

# After (error tuple)
case Zoi.parse(@schema, opts) do
  {:ok, validated} -> ...
  {:error, errors} -> {:error, Zoi.ParseError.exception(errors: errors)}
end
```

### 1.4 Documentation Generation

```elixir
# Before
#{NimbleOptions.docs(@schema)}

# After
#{Zoi.describe(@schema)}
```

### 1.5 Schema Composition

NimbleOptions uses raw keyword lists that get merged before `new!`:

```elixir
@query_schema [field1: [...], field2: [...]]
@full_schema NimbleOptions.new!(@query_schema ++ [extra: [...]])
```

Zoi — define shared fields as `{atom, schema}` keyword and merge:

```elixir
@query_fields [
  role: Zoi.union([Zoi.atom(), Zoi.string()]) |> Zoi.optional(),
  per_page: Zoi.integer(description: "Page size.", gt: 0) |> Zoi.optional()
]
@full_schema Zoi.keyword(@query_fields ++ [extra: Zoi.string()])
```

### 1.6 Error Handling

`Zoi.ParseError` is a proper exception (`defexception [:errors]`) with a
`message/1` that calls `Zoi.prettify_errors/1`.

- **`parse!/2`**: Raises `Zoi.ParseError` — drop-in for
  `NimbleOptions.ValidationError`
- **`parse/2`**: Returns `{:error, [%Zoi.Error{}]}`. Wrap into
  `Zoi.ParseError.exception(errors: errors)` to preserve the
  `{:error, exception}` API contract
- **Tests**: `assert_raise NimbleOptions.ValidationError` →
  `assert_raise Zoi.ParseError`

### 1.7 Gotchas (learned during Phase 1)

- **Chain order matters**: refinements and transforms run in declaration order.
  `Zoi.min(2048) |> Zoi.default(2048)` works correctly;
  `Zoi.default(2048) |> Zoi.min(2048)` silently swallows errors.
- **Refine MFA arity**: Zoi calls `fun(value, opts)` — functions must accept
  arity /2 (with `_opts \\ []`), not just /1.
- **No anonymous functions in module attributes**: Elixir can't escape anonymous
  functions at compile time. Use MFA `{Module, :function, []}` form instead.
- **`Zoi.keyword([])` strips all keys**: An empty field list means no keys are
  recognized. Use `Zoi.keyword(Zoi.any())` for pass-through keyword lists like
  `req_options`.
- **`Zoi.map/3` signature**: Takes separate args `(key_schema, value_schema, opts)`,
  NOT a tuple.
- **Prefer built-in refinements**: `Zoi.min/2`, `Zoi.positive/1`,
  `Zoi.non_negative/1` replace custom validators — delete the custom functions.
- **Struct derivation**: For modules with both a schema and a struct, use
  `Zoi.type_spec/1`, `Zoi.Struct.enforce_keys/1`, `Zoi.Struct.struct_fields/1`
  to derive `@type`, `@enforce_keys`, and `defstruct` from the schema.

---

## 2. Implementation Phases

### Phase 1: Simple Modules ✅ DONE

Migrated `jwk.ex`, `oauth.ex`, `pagination.ex` — all 27 tests pass.

Key changes from original plan:
- `jwk.ex`: `validate_key_size/1` deleted entirely, replaced by `Zoi.min(2048)`
- `oauth.ex`: `{:map, :atom, :any}` → `Zoi.map(Zoi.atom(), Zoi.any())` (no custom refine needed)
- Both `req_options` fields use `Zoi.keyword(Zoi.any())` not `Zoi.keyword([])`

---

### Phase 2: Service Modules (multiple schemas, `validate/2` error paths)

These modules have multiple schemas each and use non-raising `validate/2`,
so errors must be wrapped in `Zoi.ParseError` to preserve the
`{:error, exception}` contract.

#### 2.4 `lib/ltix/memberships_service.ex`

**Schemas** (4): `@context_auth_schema`, `@registration_auth_schema`,
`@get_members_schema`, `@stream_members_schema`

| Schema | Key types |
|--------|-----------|
| `@context_auth_schema` | `req_options` keyword list |
| `@registration_auth_schema` | `endpoint` as `{:struct, MembershipsEndpoint}` required, `req_options` |
| `@query_schema` (shared fields) | `endpoint` struct, `role` union (atom/string/struct), `resource_link_id` string, `per_page` pos_integer |
| `@get_members_schema` | `@query_schema` + `max_members` union (pos_integer or `:infinity`) |
| `@stream_members_schema` | `@query_schema` only |

Notable translations:
- `@query_schema` becomes `@query_fields` keyword list of Zoi schemas,
  composed via `++`
- `role: {:or, [:atom, :string, {:struct, Role}]}` →
  `Zoi.union([Zoi.atom(), Zoi.string(), Zoi.struct(Role)])`
- `max_members: {:or, [:pos_integer, {:in, [:infinity]}]}` →
  `Zoi.union([Zoi.integer() |> Zoi.positive(), Zoi.literal(:infinity)])`

**Validation call changes**:
- `authenticate/2` uses `validate!/2` → `Zoi.parse!/2` (raising)
- `get_members/2`, `stream_members/2` use `validate/2` →
  `Zoi.parse/2` + wrap errors

**Test changes** (`test/ltix/memberships_service_test.exs`):
- `assert_raise NimbleOptions.ValidationError` → `assert_raise Zoi.ParseError`

**Acceptance criteria**:
- [ ] Both `authenticate/2` paths (LaunchContext, Registration) work
- [ ] `get_members/2` returns `{:error, exception}` on invalid opts
- [ ] `stream_members/2` returns `{:error, exception}` on invalid opts
- [ ] Schema composition (`@query_fields ++`) works correctly

#### 2.5 `lib/ltix/grade_service.ex`

**Schemas** (7): `@context_auth_schema`, `@registration_auth_schema`,
`@list_line_items_schema`, `@get_line_item_schema`,
`@create_line_item_schema`, `@delete_line_item_schema`,
`@post_score_schema`, `@get_results_schema`

Notable translations:
- `line_item: {:or, [:string, {:struct, LineItem}]}` →
  `Zoi.union([Zoi.string(), Zoi.struct(LineItem)])`
- `score_maximum: {:custom, __MODULE__, :validate_positive_number, []}` →
  `Zoi.number() |> Zoi.positive()` — **removes** `validate_positive_number/1`
- `extensions: {:map, :string, :any}` →
  `Zoi.map(Zoi.string(), Zoi.any()) |> Zoi.default(%{})`

**Validation call changes**:
- `authenticate/2` uses `validate!/2` → `Zoi.parse!/2`
- All other functions use `validate/2` → `Zoi.parse/2` + wrap errors

**Test changes** (`test/ltix/grade_service_test.exs`):
- `assert_raise NimbleOptions.ValidationError` → `assert_raise Zoi.ParseError`

**Acceptance criteria**:
- [ ] All 8 public API functions accept valid options
- [ ] Invalid options return `{:error, %Zoi.ParseError{}}`
- [ ] `validate_positive_number/1` removed (replaced by `Zoi.positive()`)
- [ ] All grade service tests pass

---

### Phase 3: Score Module (most complex, custom validators + error construction)

#### 2.6 `lib/ltix/grade_service/score.ex`

**Schema** (1): `@schema` — 10 fields, 2 custom validators, manual error
construction.

| Field | NimbleOptions | Zoi |
|-------|---------------|-----|
| `user_id` | `:string`, required | `Zoi.string(description: "...") \|> Zoi.required()` |
| `activity_progress` | `{:in, @values}`, required | `Zoi.enum(@activity_progress_values, description: "...") \|> Zoi.required()` |
| `grading_progress` | `{:in, @values}`, required | `Zoi.enum(@grading_progress_values, description: "...") \|> Zoi.required()` |
| `timestamp` | `{:struct, DateTime}` | `Zoi.struct(DateTime, description: "...")` |
| `score_given` | `{:custom, :validate_non_negative_number}` | `Zoi.number(description: "...") \|> Zoi.non_negative()` |
| `score_maximum` | `{:custom, :validate_positive_number}` | `Zoi.number(description: "...") \|> Zoi.positive()` |
| `scoring_user_id` | `:string` | `Zoi.string(description: "...")` |
| `comment` | `:string` | `Zoi.string(description: "...")` |
| `submission` | `{:map, :atom, :string}` | `Zoi.map(Zoi.atom(), Zoi.string(), description: "...")` |
| `extensions` | `{:map, :string, :any}`, default `%{}` | `Zoi.map(Zoi.string(), Zoi.any(), description: "...") \|> Zoi.default(%{})` |

**Custom validator removal**:
- `validate_non_negative_number/1` → replaced by `Zoi.non_negative()`
- `validate_positive_number/1` → replaced by `Zoi.positive()`
- Both functions can be deleted

**Struct derivation** — Score has both `@schema` and `defstruct`. Derive struct
definition from the schema:
- `@type t :: unquote(Zoi.type_spec(@schema))`
- `@enforce_keys Zoi.Struct.enforce_keys(@schema)`
- `defstruct Zoi.Struct.struct_fields(@schema)`

**Error construction change** in `validate_score_pair/2`:
```elixir
# Before
{:error,
 NimbleOptions.ValidationError.exception(
   key: :score_maximum,
   message: "is required when score_given is present"
 )}

# After
{:error,
 ArgumentError.exception("score_maximum is required when score_given is present")}
```

This works because tests only assert `Exception.message(error) =~ "required when"`.

**`new/1` change**:
```elixir
# Before
case NimbleOptions.validate(opts, @schema) do
  {:ok, validated} -> ...
  {:error, %NimbleOptions.ValidationError{} = error} -> {:error, error}
end

# After
case Zoi.parse(@schema, opts) do
  {:ok, validated} -> ...
  {:error, errors} -> {:error, Zoi.ParseError.exception(errors: errors)}
end
```

**Test changes** (`test/ltix/grade_service/score_test.exs`):
- No direct NimbleOptions references in tests
- Tests assert `{:error, _}` and `Exception.message(error) =~ "..."` —
  both work with `Zoi.ParseError` and `ArgumentError`

**Acceptance criteria**:
- [ ] `Score.new/1` with all required fields succeeds
- [ ] Missing required fields return `{:error, exception}`
- [ ] `score_given: -1` returns error (via `Zoi.non_negative()`)
- [ ] `score_maximum: 0` returns error (via `Zoi.positive()`)
- [ ] `score_given` without `score_maximum` returns error with
  "required when" message
- [ ] `validate_non_negative_number/1` and `validate_positive_number/1` deleted
- [ ] All score tests pass

---

### Phase 4: Cleanup

#### 2.7 Remove NimbleOptions dependency

- `mix.exs`: Remove `{:nimble_options, "~> 1.1"}` from deps
- Run `mix deps.unlock nimble_options && mix deps.get`
- `mix compile --warnings-as-errors` — verify no references remain

#### 2.8 Final verification

- [ ] `grep -r "NimbleOptions\|nimble_options" lib/ test/ mix.exs` — zero hits
- [ ] `mix test` — full suite passes
- [ ] `mix credo --strict` — no warnings
- [ ] `mix format --check-formatted` — all formatted

---

## 3. Files Modified (Summary)

| File | Schemas | Phase |
|------|---------|-------|
| `lib/ltix/jwk.ex` | 1 | 1 |
| `lib/ltix/oauth.ex` | 1 | 1 |
| `lib/ltix/pagination.ex` | 1 | 1 |
| `lib/ltix/memberships_service.ex` | 4 | 2 |
| `lib/ltix/grade_service.ex` | 7 | 2 |
| `lib/ltix/grade_service/score.ex` | 1 | 3 |
| `test/ltix/jwk_test.exs` | — | 1 |
| `test/ltix/oauth_test.exs` | — | 1 |
| `test/ltix/memberships_service_test.exs` | — | 2 |
| `test/ltix/grade_service_test.exs` | — | 2 |
| `mix.exs` | — | 4 |

**Total**: 15 schemas across 6 library files, 4 test files, 1 build file.
