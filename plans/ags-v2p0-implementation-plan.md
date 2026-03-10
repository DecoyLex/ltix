# Assignment and Grade Services (AGS) v2.0 Implementation Plan

**Scope**: Tool-side AGS v2.0 service client. Given a successful LTI 1.3
launch that includes the AGS claim, the tool can manage line items
(gradebook columns), post scores, and read results from the platform's
gradebook.

**Spec references**:
- `[AGS §X]` → LTI Assignment and Grade Services v2.0
  (https://www.imsglobal.org/spec/lti-ags/v2p0/)
- `[Sec §X]` → 1EdTech Security Framework v1.0
  (https://www.imsglobal.org/spec/security/v1p0/)
- `[Core §X]` → LTI Core Specification v1.3
  (https://www.imsglobal.org/spec/lti/v1p3/)

**Prerequisites**: LTI 1.3 Core launch flow, OAuth 2.0 client credentials
(`Ltix.OAuth`), pagination (`Ltix.Pagination`), and the `AdvantageService`
behaviour are all implemented. The AGS endpoint claim
(`Ltix.LaunchClaims.AgsEndpoint`) is already parsed from launch JWTs.

**Approach**: TDD. Each module is developed test-first. The library remains
storage-agnostic and HTTP-client-agnostic (uses `Req` with testable stubs).
All new functions that accept keyword options use `NimbleOptions` for
validation, defaults, and documentation generation.

---

## 1. Service Overview

AGS is three services sharing a common endpoint claim and OAuth
infrastructure:

| Service | Direction | HTTP Methods | Media Type |
|---------|-----------|-------------|------------|
| **Line Item** | Read/Write | GET, POST (container); GET, PUT, DELETE (individual) | `application/vnd.ims.lis.v2.lineitem+json`, `application/vnd.ims.lis.v2.lineitemcontainer+json` |
| **Result** | Read-only | GET (container) | `application/vnd.ims.lis.v2.resultcontainer+json` |
| **Score** | Write-only | POST | `application/vnd.ims.lis.v1.score+json` |

**Scopes** [AGS §3.2, §3.3.2, §3.4.2]:

| Scope | Grants |
|-------|--------|
| `https://purl.imsglobal.org/spec/lti-ags/scope/lineitem` | Full line item CRUD |
| `https://purl.imsglobal.org/spec/lti-ags/scope/lineitem.readonly` | Read-only line item access |
| `https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly` | Read results |
| `https://purl.imsglobal.org/spec/lti-ags/scope/score` | Post scores |

Unlike NRPS (one scope, one endpoint, read-only), AGS has four scopes,
two endpoint URLs in the claim, three sub-services, and write operations.
The scopes available to the tool come directly from the claim's `scope`
array — the platform decides what the tool can do.

---

## 2. Module Architecture

AGS has three logically distinct services, but they share an endpoint
claim, authentication, and the line item URL space. Rather than three
top-level service modules, use a single `Ltix.GradeService` module as the
public API, with data structs in sub-modules.

> **Why `GradeService` not `AgsService`?** Follows the same pattern as
> `MembershipsService` (not `NrpsService`). Users shouldn't need to know
> the spec acronym.

```
Ltix.GradeService                    # Public API + AdvantageService behaviour
Ltix.GradeService.LineItem           # LineItem struct + from_json/to_json
Ltix.GradeService.Result             # Result struct + from_json
Ltix.GradeService.Score              # Score struct + to_json
```

The `AgsEndpoint` claim struct already exists at
`Ltix.LaunchClaims.AgsEndpoint` — no rename needed (unlike NRPS, "AGS"
is the internal claim name, and `GradeService` is the public-facing name).

### 2.1 Why a single module?

The three services are tightly coupled:
- Results and scores are accessed via URLs derived from line item `id`
  (`{lineitem_id}/results`, `{lineitem_id}/scores`) [AGS §3.3.1, §3.4.1]
- They share the same endpoint claim and authentication
- The common workflow is: get/create a line item, then post scores or
  read results for it

Splitting into `LineItemService`, `ResultService`, `ScoreService` would
force users to import three modules and manually pass line item URLs
between them. A single module with clear function names is simpler:

```elixir
{:ok, client} = Ltix.GradeService.authenticate(launch_context)

# Coupled (declarative) — platform created the line item
{:ok, score} = Ltix.GradeService.post_score(client, score)

# Decoupled (programmatic) — tool manages line items
{:ok, items} = Ltix.GradeService.list_line_items(client)
{:ok, item} = Ltix.GradeService.create_line_item(client, label: "Quiz 1", score_maximum: 100)
{:ok, results} = Ltix.GradeService.get_results(client, item)
```

---

## 3. Data Structures

### 3.1 `Ltix.GradeService.LineItem`

**Spec basis**: [AGS §3.2] Line item service.

```elixir
defstruct [
  :id,               # URL — set by platform on create [AGS §3.2.3]
  :label,            # REQUIRED, non-blank string [AGS §3.2.7]
  :score_maximum,    # REQUIRED, number > 0 [AGS §3.2.8]
  :resource_link_id, # Optional, binds to resource link [AGS §3.2.9]
  :resource_id,      # Optional, tool's own identifier [AGS §3.2.10]
  :tag,              # Optional, further qualifier [AGS §3.2.11]
  :start_date_time,  # Optional, ISO 8601 with timezone [AGS §3.2.12]
  :end_date_time,    # Optional, ISO 8601 with timezone [AGS §3.2.13]
  :grades_released,  # Optional, boolean hint [AGS §3.2.14]
  extensions: %{}    # All unrecognized JSON keys (includes URL-keyed extensions per [AGS §3.1.2])
]
```

**Field naming**: Elixir snake_case for struct fields (`score_maximum`),
serialized to camelCase for JSON (`scoreMaximum`). The `from_json/1` and
`to_json/1` functions handle the conversion.

**Immutable on update**: `id` and `resource_link_id` MUST NOT be changed
on PUT [AGS §3.2.6]. The `to_json/1` function for updates should exclude
`id` and preserve `resource_link_id` as-is.

**Extensions**: All unrecognized JSON keys are captured in `extensions`.
The spec requires extension keys to be fully qualified URLs [AGS §3.1.2],
but platforms may include non-URL keys. Capturing everything ensures
lossless round-trips through GET → modify → PUT (robustness principle).

**Parsing vs validation**: `from_json/1` parses platform responses — be liberal
in what we accept. Missing or odd fields become `nil`; no validation errors on
inbound data. Validation (required fields, `scoreMaximum > 0`) applies only to
outbound `to_json/1` for create/update, where we must be conservative.

**Tests**:
- Parse line item with all fields from JSON
- Parse line item with missing optional fields (all `nil`)
- Parse line item with missing `label` or `scoreMaximum` (still succeeds, `nil`)
- `id` parsed from JSON (platform-set)
- `to_json/1` serializes to camelCase
- `to_json/1` validates `label` present and non-blank [AGS §3.2.7]
- `to_json/1` validates `scoreMaximum` > 0 [AGS §3.2.8]
- `to_json/1` excludes `nil` optional fields
- All unrecognized JSON keys captured in `extensions` map
- URL-keyed extensions round-trip through from_json → to_json
- Non-URL unrecognized keys also round-trip (robustness)
- DateTime fields parsed as strings (not converted — platforms vary)

### 3.2 `Ltix.GradeService.Score`

**Spec basis**: [AGS §3.4] Score publish service.

Scores are write-only — the tool POSTs them to the platform. The struct
focuses on construction and serialization.

```elixir
defstruct [
  :user_id,            # REQUIRED [AGS §3.4.5]
  :activity_progress,  # REQUIRED, atom [AGS §3.4.7]
  :grading_progress,   # REQUIRED, atom [AGS §3.4.8]
  :timestamp,          # REQUIRED, ISO 8601 [AGS §3.4.9]
  :score_given,        # Optional, number ≥ 0 [AGS §3.4.4]
  :score_maximum,      # REQUIRED when score_given is present [AGS §3.4.4]
  :scoring_user_id,    # Optional [AGS §3.4.6]
  :comment,            # Optional, plain text [AGS §3.4.11]
  :submission,         # Optional, %{started_at: _, submitted_at: _} [AGS §3.4.10]
  extensions: %{}      # URL-keyed extension properties [AGS §3.1.2]
]
```

**Activity progress values** [AGS §3.4.7]:

| Atom | JSON | Meaning |
|------|------|---------|
| `:initialized` | `"Initialized"` | Not started / reset |
| `:started` | `"Started"` | User has begun |
| `:in_progress` | `"InProgress"` | Draft, available for comment |
| `:submitted` | `"Submitted"` | Submitted, may resubmit |
| `:completed` | `"Completed"` | Done |

**Grading progress values** [AGS §3.4.8]:

| Atom | JSON | Meaning |
|------|------|---------|
| `:fully_graded` | `"FullyGraded"` | Final grade, may display to learner |
| `:pending` | `"Pending"` | Final grade pending, no human needed |
| `:pending_manual` | `"PendingManual"` | Needs human intervention |
| `:failed` | `"Failed"` | Grading could not complete |
| `:not_ready` | `"NotReady"` | No grading process occurring |

> The tool should default to `FullyGraded` for final scores.
>
> [AGS §4.7]: "The Tool must set the 'gradingProgress' to 'FullyGraded'
> when communicating the actual student's final score. The platform may
> decide to not record any score that is not final ('FullyGraded')."
>
> Non-final scores may never reach the gradebook, so the library should
> document this prominently.

**Timestamp** [AGS §3.4.9]: MUST include sub-second precision and
timezone. MUST be strictly increasing per (line_item, user). The library
generates timestamps automatically via `DateTime.utc_now/0` if not
provided, serialized with microsecond precision and `Z` suffix.

**Submission** [AGS §3.4.10]: Optional nested object with `started_at`
and `submitted_at`. Both are ISO 8601 with timezone. `submitted_at` must
be ≥ `started_at` if both present.

**Constructor**: `Score.new/1` accepts keyword options with NimbleOptions
validation and returns `{:ok, %Score{}}` or `{:error, reason}`.
Auto-generates `timestamp` if not provided.

```elixir
{:ok, score} = Score.new(
  user_id: "12345",
  score_given: 85,
  score_maximum: 100,
  activity_progress: :completed,
  grading_progress: :fully_graded
)
```

**Tests**:
- `new/1` with all required fields succeeds
- `new/1` without `user_id` returns error
- `new/1` without `activity_progress` returns error
- `new/1` without `grading_progress` returns error
- `new/1` auto-generates `timestamp` when not provided
- `new/1` with `score_given` but no `score_maximum` returns error
- `new/1` with `score_given < 0` returns error
- `new/1` with `score_given > score_maximum` succeeds (extra credit) [AGS §3.4.4]
- `new/1` with unknown `activity_progress` value returns error
- `to_json/1` serializes atoms to PascalCase strings
- `to_json/1` serializes timestamp with sub-second precision and `Z`
- `to_json/1` serializes submission nested object with camelCase keys
- `to_json/1` excludes `nil` optional fields
- `to_json/1` includes extensions

### 3.3 `Ltix.GradeService.Result`

**Spec basis**: [AGS §3.3.4] Result media type.

Results are read-only — the platform provides them. The struct focuses
on parsing.

```elixir
defstruct [
  :id,               # URL of this result record [AGS §3.3.4.2]
  :score_of,         # URL of the line item [AGS §3.3.4.3]
  :user_id,          # REQUIRED [AGS §3.3.4.4]
  :result_score,     # Optional, number [AGS §3.3.4.5]
  :result_maximum,   # Optional, positive number, default 1 [AGS §3.3.4.6]
  :scoring_user_id,  # Optional [AGS §3.3.4.7]
  :comment,          # Optional, string [AGS §3.3.4.8]
  extensions: %{}    # All unrecognized JSON keys (includes URL-keyed extensions per [AGS §3.1.2])
]
```

**Parsing**: Results are entirely inbound — `from_json/1` only, no `to_json/1`.
Be liberal: missing fields become `nil`, no validation errors.

**Tests**:
- Parse result with all fields from JSON
- Parse result with only `userId` present (other fields `nil`)
- Parse result with missing `userId` (still succeeds, `nil`)
- Missing `resultMaximum` in JSON defaults to `nil` in struct; consumers
  must treat `nil` as 1 per spec [AGS §3.3.4.6]
- All unrecognized JSON keys parsed into `extensions`

---

## 4. `Ltix.GradeService` — Public API

### 4.1 `AdvantageService` Implementation

```elixir
@behaviour Ltix.AdvantageService

@impl true
def endpoint_from_claims(%LaunchClaims{ags_endpoint: %AgsEndpoint{} = ep}),
  do: {:ok, ep}
def endpoint_from_claims(_), do: :error

@impl true
def validate_endpoint(%AgsEndpoint{}), do: :ok
def validate_endpoint(_),
  do: {:error, InvalidEndpoint.exception(service: __MODULE__, spec_ref: "AGS §3.1")}

@impl true
# [AGS §3.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#assignment-and-grade-service-claim)
def scopes(%AgsEndpoint{scope: scopes}) when is_list(scopes), do: scopes
def scopes(%AgsEndpoint{scope: nil}), do: []
```

Unlike NRPS which always requests the same scope, AGS scopes come from
the claim's `scope` array. The platform tells the tool which scopes are
available; `scopes/1` returns them as-is. `OAuth.authenticate/2` sends
them in the token request and captures the granted subset.

### 4.2 `authenticate/2`

Same dual-path pattern as `MembershipsService`: accepts `LaunchContext`
or `Registration`.

```elixir
# From launch context — endpoint extracted from claims
{:ok, client} = Ltix.GradeService.authenticate(launch_context)

# From registration — caller provides endpoint
{:ok, client} = Ltix.GradeService.authenticate(registration,
  endpoint: %AgsEndpoint{
    lineitems: "https://lms.example.com/2344/lineitems/",
    lineitem: "https://lms.example.com/2344/lineitems/1234/lineitem",
    scope: [
      "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
      "https://purl.imsglobal.org/spec/lti-ags/scope/score"
    ]
  }
)

# Multi-service with memberships
{:ok, client} = Ltix.OAuth.authenticate(registration,
  endpoints: %{
    Ltix.GradeService => ags_endpoint,
    Ltix.MembershipsService => memberships_endpoint
  }
)
```

**Tests**:
- `authenticate/2` from LaunchContext acquires token with AGS scopes
- `authenticate/2` from LaunchContext errors when no AGS claim
- `authenticate/2` from Registration with `endpoint:` acquires token
- Scopes from `AgsEndpoint.scope` field requested in token
- Empty `scope` list requests no scopes (client will fail scope checks)

### 4.3 Line Item Operations

#### `list_line_items/2` — Fetch line items from the container

**Spec basis**: [AGS §3.2.4] Container request filters.

Requires scope: `lineitem` or `lineitem.readonly`.

```elixir
@list_line_items_schema NimbleOptions.new!([
  resource_link_id: [
    type: :string,
    doc: "Filter to line items bound to this resource link."
  ],
  resource_id: [
    type: :string,
    doc: "Filter by the tool's resource identifier."
  ],
  tag: [
    type: :string,
    doc: "Filter by tag."
  ],
  per_page: [
    type: :pos_integer,
    doc: "Page size hint."
  ]
])

@spec list_line_items(Client.t(), keyword()) ::
  {:ok, [LineItem.t()]} | {:error, Exception.t()}
def list_line_items(%Client{} = client, opts \\ [])
```

Returns a flat list of `%LineItem{}` structs. Follows all `rel="next"`
pagination links automatically using `Ltix.Pagination`.

Requires the `lineitems` URL from the endpoint. Returns
`ServiceNotAvailable` if the endpoint has no `lineitems` URL.

**Tests**:
- Fetches all line items from container endpoint
- Sends correct Accept header (`lineitemcontainer+json`)
- Filters by `resource_link_id`, `resource_id`, `tag`
- Follows `rel="next"` pagination links
- Returns error when `lineitems` URL is not available on endpoint
- Returns error when client lacks `lineitem` or `lineitem.readonly` scope

#### `get_line_item/2` — Fetch a single line item

```elixir
@spec get_line_item(Client.t(), keyword()) ::
  {:ok, LineItem.t()} | {:error, Exception.t()}
def get_line_item(%Client{} = client, opts \\ [])
```

GETs the line item at the given URL. Uses `lineitem+json` Accept header.

The line item URL comes from:
1. The `line_item:` option [AGS §3.2.3]
2. The endpoint's `lineitem` URL (coupled flow default)

```elixir
# Coupled — use the lineitem from the launch claim
{:ok, item} = Ltix.GradeService.get_line_item(client)

# Explicit URL
{:ok, item} = Ltix.GradeService.get_line_item(client,
  line_item: "https://lms.example.com/.../lineitem"
)
```

**Tests**:
- Fetches line item from `line_item:` option
- Fetches line item from endpoint's `lineitem` URL when no option given
- Returns error when no option given and no `lineitem` on endpoint
- Parses response into `%LineItem{}`

#### `create_line_item/2` — Create a new line item

**Spec basis**: [AGS §3.2.5] Creating a new line item.

Requires scope: `lineitem` (not `lineitem.readonly`).

```elixir
@create_line_item_schema NimbleOptions.new!([
  label: [type: :string, required: true, doc: "Human-readable label."],
  score_maximum: [type: {:custom, __MODULE__, :validate_positive_number, []},
                  required: true, doc: "Maximum score (must be > 0)."],
  resource_link_id: [type: :string, doc: "Bind to a resource link."],
  resource_id: [type: :string, doc: "Tool's resource identifier."],
  tag: [type: :string, doc: "Qualifier tag (e.g., \"grade\", \"originality\")."],
  start_date_time: [type: :string, doc: "ISO 8601 with timezone."],
  end_date_time: [type: :string, doc: "ISO 8601 with timezone."],
  grades_released: [type: :boolean, doc: "Hint to platform about releasing grades."],
  extensions: [type: {:map, :string, :any}, default: %{},
               doc: "Extension properties (e.g., Canvas submission_type). Keys should be fully qualified URLs per spec."]
])

@spec create_line_item(Client.t(), keyword()) ::
  {:ok, LineItem.t()} | {:error, Exception.t()}
def create_line_item(%Client{} = client, opts)
```

POSTs to the `lineitems` container URL. Parses the 201 response into a
`%LineItem{}` with the platform-assigned `id` [AGS §3.2.5].

**Tests**:
- Creates line item with required fields
- Platform response parsed into `%LineItem{}` with `id` assigned
- Returns error when client lacks `lineitem` scope (not `lineitem.readonly`)
- Returns error when `lineitems` URL not available
- Missing `label` returns validation error
- Missing `score_maximum` returns validation error
- `score_maximum` ≤ 0 returns validation error

#### `update_line_item/3` — Update a line item

**Spec basis**: [AGS §3.2.6] Updating a line item.

Requires scope: `lineitem`.

```elixir
@spec update_line_item(Client.t(), LineItem.t()) ::
  {:ok, LineItem.t()} | {:error, Exception.t()}
def update_line_item(%Client{} = client, %LineItem{} = line_item)
```

PUTs the full line item to its `id` URL. This is a full replacement,
not a patch — callers should GET first to avoid overwriting fields
[AGS §3.2.6].

`id` and `resource_link_id` MUST NOT be changed [AGS §3.2.6]. The
serialization sends `id` (required by some platforms) and
`resourceLinkId` as-is.

**Tests**:
- Updates line item at its `id` URL
- Response parsed as updated `%LineItem{}`
- `id` is included in the PUT body
- Returns error when line item has no `id`
- Returns error when client lacks `lineitem` scope

#### `delete_line_item/2` — Delete a line item

Requires scope: `lineitem`.

```elixir
@spec delete_line_item(Client.t(), LineItem.t() | String.t(), keyword()) ::
  :ok | {:error, Exception.t()}
def delete_line_item(%Client{} = client, line_item_or_url, opts \\ [])
```

DELETEs the line item at its `id` URL. Accepts either a `%LineItem{}`
(uses its `id`) or a URL string.

**Coupled line item guard**: Before sending the request, compares the
target URL against the endpoint's `lineitem` URL (the coupled line item
from the launch claim). If they match, returns an error unless the caller
passes `force: true`. This prevents accidental deletion of the
platform-created line item, which Canvas blocks (401) and other
platforms handle inconsistently (Moodle/Blackboard delete the gradebook
entry; D2L severs the link but preserves grade data). The `lineitem`
claim may vanish from future launches.

```elixir
# Decoupled — works normally
GradeService.delete_line_item(client, tool_created_item)

# Coupled — blocked by default
{:error, %CoupledLineItem{}} = GradeService.delete_line_item(client, coupled_item)

# Coupled — explicit opt-in
:ok = GradeService.delete_line_item(client, coupled_item, force: true)
```

**Tests**:
- Deletes line item by struct
- Deletes line item by URL string
- Returns `:ok` on success (HTTP 204)
- Returns error when client lacks `lineitem` scope
- Returns `CoupledLineItem` error when URL matches endpoint's `lineitem`
- Succeeds with `force: true` even when URL matches endpoint's `lineitem`
- No guard triggered when endpoint has no `lineitem` (programmatic-only)

### 4.4 Score Operations

#### `post_score/3` — Post a score for a user

**Spec basis**: [AGS §3.4] Score publish service.

Requires scope: `score`.

```elixir
@spec post_score(Client.t(), Score.t(), keyword()) ::
  :ok | {:error, Exception.t()}
def post_score(%Client{} = client, %Score{} = score, opts \\ [])
```

POSTs to `{lineitem_id}/scores`. The line item URL comes from:
1. The `line_item:` option (`%LineItem{}` struct or URL string)
2. The endpoint's `lineitem` URL (coupled flow default)

```elixir
# Coupled flow — uses lineitem from launch claim
{:ok, score} = Score.new(
  user_id: "12345",
  score_given: 85,
  score_maximum: 100,
  activity_progress: :completed,
  grading_progress: :fully_graded
)
:ok = Ltix.GradeService.post_score(client, score)

# Programmatic — explicit line item
:ok = Ltix.GradeService.post_score(client, score, line_item: item)
```

**URL derivation** [AGS §3.4.1]: The scores endpoint is the line item's
`id` with `/scores` appended. Any existing query parameters on the line
item URL MUST be preserved.

**Response**: HTTP 200 or 204 is success. The response body (if any) is
ignored — score POST is fire-and-forget from the API perspective.

> Stale timestamps do not produce errors visible to the tool.
>
> [AGS §3.4.9]: "The platform MUST NOT update a result if the last
> timestamp on record is later than the incoming score update. It may
> just ignore the incoming score update, or log it if it maintains any
> kind of history or for traceability."
>
> The HTTP response may still be 200/204. The tool cannot detect whether
> a stale score was discarded, so auto-generating monotonic timestamps
> (via `DateTime.utc_now/0`) is important.

**Tests**:
- Posts score to `{lineitem_id}/scores`
- Uses `lineitem` from endpoint when no `line_item:` option
- Uses explicit `line_item:` option
- Sends correct Content-Type (`application/vnd.ims.lis.v1.score+json`)
- Score JSON serialized correctly (camelCase, PascalCase enums)
- Returns `:ok` on HTTP 200 or 204
- Returns error when client lacks `score` scope
- Returns error when no line item URL available

### 4.5 Result Operations

#### `get_results/3` — Fetch results for a line item

**Spec basis**: [AGS §3.3] Result service.

Requires scope: `result.readonly`.

```elixir
@get_results_schema NimbleOptions.new!([
  line_item: [
    type: {:or, [:string, {:struct, LineItem}]},
    doc: "Line item URL or struct. Defaults to the endpoint's `lineitem`."
  ],
  user_id: [
    type: :string,
    doc: "Filter results to a single user."
  ],
  per_page: [
    type: :pos_integer,
    doc: "Page size hint."
  ]
])

@spec get_results(Client.t(), keyword()) ::
  {:ok, [Result.t()]} | {:error, Exception.t()}
def get_results(%Client{} = client, opts \\ [])
```

GETs `{lineitem_id}/results`. Follows `rel="next"` pagination.

```elixir
# All results for the coupled line item
{:ok, results} = Ltix.GradeService.get_results(client)

# Results for a specific user on a specific line item
{:ok, results} = Ltix.GradeService.get_results(client,
  line_item: item,
  user_id: "12345"
)
```

> Result lists may be sparse.
>
> [AGS §3.3.5]: "A GET on Results URL MUST return a result record for
> each user that has a non empty 'resultScore' for the queried upon line
> item. The platform MAY skip empty results."
>
> The tool should not assume every enrolled user has a result entry.

**Tests**:
- Fetches results from `{lineitem_id}/results`
- Uses `lineitem` from endpoint when no `line_item:` option
- Follows `rel="next"` pagination
- Filters by `user_id` query parameter [AGS §3.3.6]
- Sends correct Accept header (`resultcontainer+json`)
- Returns error when client lacks `result.readonly` scope
- Returns error when no line item URL available
- Parses results into `%Result{}` structs

---

## 5. URL Derivation

The Result and Score service endpoints are derived from line item URLs
[AGS §3.3.1, §3.4.1]:

```
Line item:  https://lms.example.com/2344/lineitems/1234/lineitem
Results:    https://lms.example.com/2344/lineitems/1234/lineitem/results
Scores:     https://lms.example.com/2344/lineitems/1234/lineitem/scores
```

This is a private helper function in `GradeService`:

```elixir
defp derive_url(line_item_url, suffix) do
  uri = URI.parse(line_item_url)
  path = String.trim_trailing(uri.path, "/") <> "/" <> suffix
  URI.to_string(%{uri | path: path})
end
```

Query parameters on the line item URL are preserved. The appended path
segment is just the suffix (`results` or `scores`).

**Tests**:
- Appends `/results` to line item URL
- Appends `/scores` to line item URL
- Preserves existing query parameters
- Handles trailing slashes

---

## 6. Scope Checking

Unlike NRPS (single scope, simple check), AGS functions need different
scopes. Some functions accept either of two scopes (e.g., `list_line_items`
works with `lineitem` or `lineitem.readonly`).

Use the existing `Client.require_scope/2` and `Client.require_any_scope/2`:

| Function | Required scope(s) |
|----------|------------------|
| `list_line_items/2` | `lineitem` OR `lineitem.readonly` |
| `get_line_item/2` | `lineitem` OR `lineitem.readonly` |
| `create_line_item/2` | `lineitem` |
| `update_line_item/2` | `lineitem` |
| `delete_line_item/2` | `lineitem` |
| `post_score/3` | `score` |
| `get_results/3` | `result.readonly` |

---

## 7. Error Types

The existing error types cover all AGS failure modes:

| Error | AGS use case |
|-------|-------------|
| `ServiceNotAvailable` | No AGS claim in launch, or missing `lineitems`/`lineitem` URL |
| `InvalidEndpoint` | Wrong endpoint struct type |
| `ScopeMismatch` | Client lacks required scope for the operation |
| `AccessTokenExpired` | Token expired before service call |
| `MalformedResponse` | Platform returns invalid JSON or wrong structure |
| `TransportError` | HTTP errors (4xx, 5xx) |
| `TokenRequestFailed` | OAuth token acquisition failed |

**New error type**:

| Error | Use case |
|-------|----------|
| `CoupledLineItem` | `delete_line_item` target matches the endpoint's coupled `lineitem` URL and `force: true` was not passed |

---

## 8. Directory Structure (New Files)

```
lib/
  ltix/
    errors/
      invalid/
        coupled_line_item.ex          # Error raised when attempting to delete the coupled line item without force
    grade_service.ex                  # Public API + AdvantageService behaviour
    grade_service/
      line_item.ex                    # %LineItem{} + from_json/to_json
      result.ex                       # %Result{} + from_json
      score.ex                        # %Score{} + new/to_json
test/
  ltix/
    grade_service_test.exs            # authenticate, all API functions
    grade_service/
      line_item_test.exs              # struct parsing/serialization
      result_test.exs                 # struct parsing
      score_test.exs                  # struct construction/serialization
```

---

## 9. Implementation Order

### Phase 1: Data Structures (no HTTP, no OAuth)

1. **`Ltix.GradeService.LineItem`** — struct, `from_json/1`, `to_json/1`
   - Pure data parsing/serialization
   - camelCase ↔ snake_case conversion
   - Extension field handling
   - Validation: `label` required, `score_maximum > 0`

2. **`Ltix.GradeService.Score`** — struct, `new/1`, `to_json/1`
   - NimbleOptions-validated constructor
   - Auto-generated timestamp
   - Enum atom ↔ PascalCase string mapping
   - Validation: required fields, `score_given ≥ 0`,
     `score_maximum` required when `score_given` present

3. **`Ltix.GradeService.Result`** — struct, `from_json/1`
   - Read-only parsing
   - Extension handling

**Acceptance criteria**:
- [x] `LineItem.from_json/1` and `to_json/1` round-trip correctly
- [x] `Score.new/1` validates all required fields and constraints
- [x] `Score.to_json/1` serializes enums to PascalCase [AGS §3.4.7, §3.4.8]
- [x] `Score.new/1` auto-generates ISO 8601 timestamp with microseconds
      and `Z` suffix [AGS §3.4.9]
- [x] All unrecognized JSON keys round-trip through from/to_json (including non-URL keys)

### Phase 2: Service Module

5. **`Ltix.GradeService`** — `AdvantageService` implementation + `authenticate/2`
   - `endpoint_from_claims/1`, `validate_endpoint/1`, `scopes/1`
   - Dual-path authenticate (LaunchContext / Registration)

6. **Line item operations** — `list_line_items/2`, `get_line_item/2`,
   `create_line_item/2`, `update_line_item/2`, `delete_line_item/2`
   - HTTP calls via `Req`
   - Pagination via `Ltix.Pagination` for `list_line_items`
   - Scope checks before each operation

7. **Score and result operations** — `post_score/3`, `get_results/3`
   - URL derivation from line item `id`
   - Pagination for results
   - Coupled flow defaults (use endpoint `lineitem` URL)

**Acceptance criteria**:
- [x] `authenticate/2` from LaunchContext requests scopes from
      `AgsEndpoint.scope` [AGS §3.1]
- [x] `list_line_items/2` sends correct Accept header and pagination
      [AGS §3.2.1]
- [x] `list_line_items/2` passes filter parameters (`resource_link_id`,
      `resource_id`, `tag`) [AGS §3.2.4]
- [x] `create_line_item/2` POSTs to `lineitems` URL and returns the
      platform's response with assigned `id` [AGS §3.2.5]
- [x] `update_line_item/2` PUTs the full line item to its `id` URL
      [AGS §3.2.6]
- [x] `delete_line_item/2` sends DELETE to the line item URL
- [x] `post_score/3` POSTs to `{lineitem}/scores` with correct
      Content-Type [AGS §3.4]
- [x] `get_results/3` GETs `{lineitem}/results` with pagination
      [AGS §3.3]
- [x] Each function checks the appropriate scope before making HTTP calls
- [x] Coupled flow: `post_score/3` and `get_results/3` default to the
      endpoint's `lineitem` URL when no explicit line item given
- [x] URL derivation preserves query parameters on line item URLs

### Phase 3: Documentation

8. **`guides/grade-service.md`** — Grade Service (AGS)
   - What AGS is and the two workflows (coupled vs programmatic)
   - Authentication from LaunchContext and Registration
   - Coupled flow: posting scores with the launch's line item
   - Programmatic flow: creating and managing line items
   - Reading results
   - Score construction: activity/grading progress, timestamps
   - Multi-service authentication (AGS + NRPS in one token)
   - Common patterns: migrating from Basic Outcomes [AGS §4.5],
     managing multiple line items [AGS §4.8]

9. **Module docs** — `@moduledoc` / `@doc` on all public modules
   and functions

10. **Existing docs updates**
    - `lib/ltix.ex` — add AGS section to facade moduledoc
    - `mix.exs` — add modules to doc groups, guide to extras
    - `guides/advantage-services.md` — add AGS examples

**Acceptance criteria**:
- [x] Guide covers both coupled and programmatic flows with examples
- [x] Guide includes score construction patterns for common use cases
- [x] All public functions have `@doc` with examples

---

## 10. Test Strategy

### Unit Tests
- `LineItem` — from_json/to_json, validation, extensions
- `Score` — new/1 validation, to_json serialization, enum mapping,
  timestamp generation, submission object
- `Result` — from_json, extensions
- URL derivation helper — path appending, query parameter preservation

### Integration Tests (Stubbed HTTP)
- Full coupled flow: authenticate → post_score (using endpoint `lineitem`)
- Full programmatic flow: authenticate → list_line_items → create →
  post_score → get_results → update → delete
- Pagination: list_line_items and get_results follow `rel="next"`
- Scope enforcement: each operation returns `ScopeMismatch` without
  the correct scope
- Multi-service: single token covering AGS + NRPS scopes
- Error paths: platform returns 401/403, malformed JSON, unexpected
  Content-Type

### Stubbing Pattern
Use `Req.Test.stub/2` for the token endpoint, line items endpoint,
scores endpoint, and results endpoint. Follow the same pattern as
`MembershipsService` tests.

---

## 11. Resolved Questions

1. **Module structure**: Single `Ltix.GradeService` module, not three
   separate service modules. The three AGS services are tightly coupled
   through line item URLs and share authentication. One module is simpler
   for users.

2. **Naming**: `GradeService` not `AgsService`, following the
   `MembershipsService` precedent. The claim struct stays as
   `AgsEndpoint` (internal name, already exists).

3. **Scopes are claim-driven**: `scopes/1` returns the claim's `scope`
   array as-is. The platform decides what the tool can do. No
   library-side scope defaults or overrides.

4. **Score timestamp auto-generation**: `Score.new/1` generates a
   timestamp if not provided. This prevents the most common developer
   mistake (forgetting the timestamp) while still allowing explicit
   control for testing or replays.

5. **Coupled flow defaults**: `post_score/3` and `get_results/3`
   default to the endpoint's `lineitem` URL when no explicit line item
   is given. This makes the simple case (one line item per link) a
   one-liner.

6. **PUT is full replacement**: `update_line_item/2` takes a full
   `%LineItem{}` struct. The caller is expected to GET first, modify,
   then PUT. No PATCH support (the spec doesn't define it).

7. **No streaming for line items or results**: Unlike NRPS rosters
   which can have thousands of members, line item lists and result
   sets for a single line item are typically small. `list_line_items/2`
   and `get_results/3` eagerly follow all pages and return flat lists.
   If this proves insufficient, streaming can be added later without
   breaking changes.

8. **Extensions**: All unrecognized JSON keys are captured in an
   `extensions` map and round-tripped through serialization. The spec
   requires extension keys to be fully qualified URLs [AGS §3.1.2],
   but we capture all unknown keys to ensure lossless round-trips
   (robustness principle — platforms may include non-URL keys).
   See §12 for known platform extensions.

9. **No result container**: AGS result responses are plain JSON arrays
   (unlike NRPS which has `context` and `id` fields). `get_results/2`
   returns a plain `[Result.t()]` list — no wrapper needed since lists
   are already enumerable.

---

## 12. Platform Extensions

The AGS spec allows extension properties on line items, scores, and
results via URL-keyed JSON fields [AGS §3.1.2]. The `extensions` map on
each struct captures these automatically. No special struct fields are
needed — tools set/read extensions through the map.

Canvas is the most widely deployed LMS and defines several extensions
worth documenting:

### 12.1 Canvas Line Item Extensions

**`https://canvas.instructure.com/lti/submission_type`** (on create):
Sets the Canvas assignment's submission type when a new line item creates
a placeholder assignment.

```json
{
  "scoreMaximum": 100,
  "label": "Quiz 1",
  "https://canvas.instructure.com/lti/submission_type": {
    "type": "external_tool",
    "external_tool_url": "https://my.tool.url/launch"
  }
}
```

Values for `type`: `"none"` or `"external_tool"`. When `"external_tool"`,
`external_tool_url` specifies the launch URL.

**`https://canvas.instructure.com/lti/launch_url`** (on read):
Canvas returns the line item's launch URL when `include[]=launch_url` is
passed as a query parameter on GET requests (show and list). This is
read-only. The `list_line_items` and `get_line_item` schemas should
accept an `include` option to support this.

### 12.2 Canvas Score Extensions

**`https://canvas.instructure.com/lti/submission`** (on POST):
Rich submission metadata that extends the standard `submission` field.

```json
{
  "https://canvas.instructure.com/lti/submission": {
    "new_submission": true,
    "preserve_score": false,
    "prioritize_non_tool_grade": false,
    "submission_type": "online_url",
    "submission_data": "https://example.com/student-work",
    "submitted_at": "2017-04-14T18:54:36.736+00:00",
    "content_items": [
      {
        "type": "file",
        "url": "https://example.com/file.pdf",
        "title": "Submission File",
        "media_type": "application/pdf"
      }
    ]
  }
}
```

Key fields:
- `new_submission` — flag for new submission (defaults to `true` unless
  `submission_type` is `"none"`)
- `preserve_score` — prevent clearing an existing grade
- `prioritize_non_tool_grade` — prevent overwriting instructor grades
- `submission_type` — `none`, `basic_lti_launch`, `online_text_entry`,
  `external_tool`, `online_upload`, `online_url`
- `submission_data` — URL or body text (for applicable submission types)
- `content_items` — array of files to attach to the submission

### 12.3 Design Implications

These are all URL-keyed properties and flow through the `extensions` map
naturally. No special struct fields needed. Example usage:

```elixir
# Canvas submission type on line item create
Ltix.GradeService.create_line_item(client,
  label: "Quiz 1",
  score_maximum: 100,
  extensions: %{
    "https://canvas.instructure.com/lti/submission_type" => %{
      "type" => "external_tool",
      "external_tool_url" => "https://my.tool.url/launch"
    }
  }
)

# Canvas submission data on score POST
Score.new(
  user_id: "12345",
  score_given: 85,
  score_maximum: 100,
  activity_progress: :completed,
  grading_progress: :fully_graded,
  extensions: %{
    "https://canvas.instructure.com/lti/submission" => %{
      "new_submission" => true,
      "submission_type" => "online_url",
      "submission_data" => "https://example.com/student-work"
    }
  }
)
```

The guide (Phase 3, §9) should include a Canvas-specific section showing
these patterns, since most Ltix users will target Canvas.

**`include` query parameter**: Canvas supports `include[]=launch_url` on
line item GET/LIST. Add an `include` option to `list_line_items` and
`get_line_item`:

```elixir
@list_line_items_schema NimbleOptions.new!([
  # ... existing options ...
  include: [
    type: {:list, :string},
    default: [],
    doc: "Additional data to include (platform-specific). Canvas supports `\"launch_url\"`."
  ]
])
```

---

## 13. Open Questions

None. All design questions have been resolved (see §11).
