# Deep Linking v2.0 Implementation Plan

**Scope**: Tool-side Deep Linking v2.0. Given a platform launch with
`message_type` = `LtiDeepLinkingRequest`, the tool can present a content
selection UI, build content items, sign a response JWT, and redirect the
user back to the platform with the selected items.

**Spec references**:
- `[DL §X]` → LTI Deep Linking v2.0
  (https://www.imsglobal.org/spec/lti-dl/v2p0/)
- `[Sec §X]` → 1EdTech Security Framework v1.0
  (https://www.imsglobal.org/spec/security/v1p0/)
- `[Core §X]` → LTI Core Specification v1.3
  (https://www.imsglobal.org/spec/lti/v1p3/)
- `[AGS §X]` → LTI Assignment and Grade Services v2.0
  (https://www.imsglobal.org/spec/lti-ags/v2p0/)

**Prerequisites**: LTI 1.3 Core launch flow (already implemented). The
`DeepLinkingSettings` claim is already parsed from launch JWTs
(`Ltix.LaunchClaims.DeepLinkingSettings`). JWK management
(`Ltix.JWK`), Registration with `tool_jwk`, and the OAuth infrastructure
are all in place.

**Approach**: TDD. Each module is developed test-first. All modules use
`Zoi` for schema validation, struct construction, and documentation
generation.

---

## 1. How Deep Linking Differs from Advantage Services

Deep Linking is fundamentally different from NRPS and AGS:

| Aspect | NRPS / AGS | Deep Linking |
|--------|-----------|--------------|
| Flow | OAuth 2.0 client credentials → HTTP API calls | OIDC message flow → JWT form POST response |
| Direction | Tool calls platform API | Tool redirects user back to platform |
| Authentication | Bearer token | Signed JWT (tool's private key) |
| Data exchange | JSON API responses | Content items embedded in JWT |
| Timing | After launch, asynchronous | During launch, synchronous |

Deep Linking does NOT implement the `AdvantageService` behaviour. It does
not use OAuth tokens, does not make HTTP API calls, and does not interact
with `Ltix.OAuth.Client`. Instead, it extends the existing OIDC launch
flow to accept a second message type (`LtiDeepLinkingRequest`) and
provides a response builder that signs a JWT. The actual form POST
delivery (auto-submit HTML form) is a framework concern, left to
packages like `ltix_phoenix`.

---

## 2. Callback Changes

The existing `Ltix.OIDC.Callback` hardcodes `LtiResourceLinkRequest` as
the only valid `message_type`. Deep Linking requires accepting
`LtiDeepLinkingRequest` with different validation rules.

### 2.1 Message Type Validation

**Current code** (`Ltix.OIDC.Callback.validate_message_type/1`):

```elixir
defp validate_message_type(claims) do
  case claims[@lti <> "message_type"] do
    "LtiResourceLinkRequest" -> :ok
    nil -> {:error, MissingClaim.exception(...)}
    other -> {:error, InvalidClaim.exception(...)}
  end
end
```

**Change**: Accept both message types, returning the type for downstream
branching:

```elixir
defp validate_message_type(claims) do
  case claims[@lti <> "message_type"] do
    "LtiResourceLinkRequest" -> {:ok, "LtiResourceLinkRequest"}
    "LtiDeepLinkingRequest" -> {:ok, "LtiDeepLinkingRequest"}
    nil -> {:error, MissingClaim.exception(claim: "message_type", spec_ref: "Core §5.3.1")}
    other -> {:error, InvalidClaim.exception(claim: "message_type", ...)}
  end
end
```

### 2.2 Message-Specific Claim Validation

The validation rules differ by message type:

| Claim | `LtiResourceLinkRequest` | `LtiDeepLinkingRequest` |
|-------|--------------------------|------------------------|
| `message_type` | REQUIRED, `"LtiResourceLinkRequest"` | REQUIRED, `"LtiDeepLinkingRequest"` |
| `version` | REQUIRED, `"1.3.0"` | REQUIRED, `"1.3.0"` |
| `deployment_id` | REQUIRED | REQUIRED [DL §4.4.4] |
| `target_link_uri` | REQUIRED | REQUIRED (tool's DL endpoint) |
| `resource_link` | REQUIRED [Core §5.3.5] | NOT present [DL §4.4] |
| `roles` | REQUIRED [Core §5.3.7] | OPTIONAL [DL §4.4.9] |
| `sub` | REQUIRED (unless `allow_anonymous`) [Core §5.3.6] | OPTIONAL [DL §4.4.5] |
| `deep_linking_settings` | N/A | REQUIRED [DL §4.4.1] |

> [DL §4.4]: "The platform sends the same message parameters in the deep
> linking request message as it would in the resource link launch request
> message with the exception of the resource link claim, along with some
> additional parameters."

**Refactored validation flow**:

```elixir
defp validate_required_lti_claims(claims, opts) do
  with {:ok, message_type} <- validate_message_type(claims),
       :ok <- validate_version(claims),
       :ok <- validate_present(claims, @lti <> "deployment_id", "deployment_id", "Core §5.3.3"),
       :ok <- validate_present(claims, @lti <> "target_link_uri", "target_link_uri", "Core §5.3.4"),
       :ok <- validate_message_specific_claims(message_type, claims, opts) do
    :ok
  end
end

defp validate_message_specific_claims("LtiResourceLinkRequest", claims, opts) do
  with :ok <- validate_resource_link(claims),
       :ok <- validate_roles_present(claims) do
    validate_sub(claims, opts)
  end
end

defp validate_message_specific_claims("LtiDeepLinkingRequest", claims, _opts) do
  validate_deep_linking_settings_present(claims)
end
```

For `LtiDeepLinkingRequest`:
- `resource_link` is NOT validated (not present in DL requests)
- `roles` is NOT validated (optional per [DL §4.4.9])
- `sub` is NOT validated (optional per [DL §4.4.5])
- `deep_linking_settings` IS validated as present

**`validate_deep_linking_settings_present/1`**: Checks that the
`deep_linking_settings` claim key is present in the raw JWT claims. The
actual parsing into `%DeepLinkingSettings{}` happens later in
`LaunchClaims.from_json/1`, which already validates `deep_link_return_url`
is present.

```elixir
@dl_settings_key "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings"

defp validate_deep_linking_settings_present(claims) do
  case claims[@dl_settings_key] do
    %{} -> :ok
    _ -> {:error, MissingClaim.exception(claim: "deep_linking_settings", spec_ref: "DL §4.4.1")}
  end
end
```

### 2.3 Public API — No Change

`Ltix.handle_callback/3` continues to return `{:ok, %LaunchContext{}}`.
The caller branches on `context.claims.message_type`:

```elixir
{:ok, context} = Ltix.handle_callback(params, state, opts)

case context.claims.message_type do
  "LtiDeepLinkingRequest" ->
    # Show content selection UI, then build_response
    settings = context.claims.deep_linking_settings
    # ...

  "LtiResourceLinkRequest" ->
    # Normal launch flow
    # ...
end
```

No new public functions on `Ltix`. No new return types.

### 2.4 DeepLinkingSettings Validation Enhancement

The existing `DeepLinkingSettings.from_json/1` only validates
`deep_link_return_url` is present. Per [DL §4.4.1], `accept_types` and
`accept_presentation_document_targets` are also required.

**Change**: Add validation for both required array fields:

```elixir
def from_json(%{"deep_link_return_url" => url, "accept_types" => types,
                "accept_presentation_document_targets" => targets} = json)
    when is_list(types) and is_list(targets) do
  {:ok, %__MODULE__{deep_link_return_url: url, accept_types: types, ...}}
end
```

Missing `accept_types` → `MissingClaim` error referencing [DL §4.4.1].
Missing `accept_presentation_document_targets` → same.

**Tests** (§2):
- `handle_callback/3` succeeds with `LtiDeepLinkingRequest` message type
- `handle_callback/3` succeeds with `LtiResourceLinkRequest` (unchanged)
- DL request without `resource_link` claim succeeds
- DL request without `roles` claim succeeds
- DL request without `sub` claim succeeds
- DL request without `deep_linking_settings` returns `MissingClaim` error
- DL request with `deep_linking_settings` missing `deep_link_return_url` returns error
- DL request with `deep_linking_settings` missing `accept_types` returns error
- DL request with `deep_linking_settings` missing `accept_presentation_document_targets` returns error
- Resource link request without `resource_link` still fails (unchanged)
- Resource link request without `roles` still fails (unchanged)
- Unrecognized message type returns `InvalidClaim` error (unchanged)

---

## 3. Content Item Types

The DL spec defines five content item types [DL §3]. Each is represented
as a struct with a Zoi-validated constructor (`new/1`) and a serializer
(`to_json/1`).

All content items are outbound (tool → platform). The tool constructs
them; the library serializes them into the response JWT. There is no
inbound parsing (`from_json/1`) because the tool never receives content
items — it creates them.

**Type extensions** [DL §3.6]: The spec allows enriching any content
item type with additional properties keyed by fully qualified URLs.
Each content item struct includes an `extensions` field
(`Zoi.map(Zoi.string(), Zoi.any())`, default `%{}`) that is merged
into the top-level JSON output on serialization — the same pattern
used by `GradeService.Score`, `GradeService.LineItem`, and
`LaunchClaims`.

### 3.1 Shared Sub-Structures

Several content item types share icon, thumbnail, window, and iframe
sub-structures. These are represented as plain maps (not structs) for
simplicity. Zoi map schemas validate their shape at construction time.

**Icon / Thumbnail** [DL §3.1, §3.2, §3.3, §3.5]:

```elixir
@icon_schema Zoi.map(%{
  url: Zoi.string(description: "Fully qualified URL to the image.") |> Zoi.required(),
  width: Zoi.integer(description: "Width in pixels."),
  height: Zoi.integer(description: "Height in pixels.")
})
```

**Window** [DL §3.1, §3.2]:

```elixir
@window_schema Zoi.map(%{
  target_name: Zoi.string(description: "Name of the target window."),
  width: Zoi.integer(description: "Width in pixels."),
  height: Zoi.integer(description: "Height in pixels."),
  window_features: Zoi.string(description: "Comma-separated window features per window.open().")
})
```

**Iframe** [DL §3.1, §3.2]:

```elixir
# For Link type (src is required for iframes on links)
@link_iframe_schema Zoi.map(%{
  src: Zoi.string(description: "URL to embed as the iframe src.") |> Zoi.required(),
  width: Zoi.integer(description: "Width in pixels."),
  height: Zoi.integer(description: "Height in pixels.")
})

# For LtiResourceLink type (no src — platform uses the resource link URL)
@resource_link_iframe_schema Zoi.map(%{
  width: Zoi.integer(description: "Width in pixels."),
  height: Zoi.integer(description: "Height in pixels.")
})
```

**Embed** [DL §3.1]:

```elixir
@embed_schema Zoi.map(%{
  html: Zoi.string(description: "HTML fragment to embed.") |> Zoi.required()
})
```

**Serialization**: Codecs map snake_case struct fields to camelCase
JSON keys: `target_name` → `targetName`,
`window_features` → `windowFeatures`. The codec definition is the
single source of truth for key naming — no hand-written mapping in
`to_json/1`.

### 3.2 `Ltix.DeepLinking.ContentItem.Link`

**Spec basis**: [DL §3.1] A fully qualified URL to a resource hosted on
the internet.

**Schema, struct, and constructor**:

```elixir
@schema Zoi.struct(__MODULE__, %{
  url: Zoi.string(description: "Fully qualified URL of the resource.") |> Zoi.required(),
  title: Zoi.string(description: "Plain text title or heading."),
  text: Zoi.string(description: "Plain text description."),
  icon: @icon_schema,
  thumbnail: @icon_schema,
  embed: @embed_schema,
  window: @window_schema,
  iframe: @link_iframe_schema,
  extensions:
    Zoi.map(Zoi.string(), Zoi.any(),
      description: "Extension properties keyed by fully qualified URLs."
    )
    |> Zoi.default(%{})
})

@type t :: unquote(Zoi.type_spec(@schema))
@enforce_keys Zoi.Struct.enforce_keys(@schema)
defstruct Zoi.Struct.struct_fields(@schema)

@spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
def new(opts) do
  case Zoi.parse(@schema, Map.new(opts)) do
    {:ok, link} -> {:ok, link}
    {:error, errors} -> {:error, Zoi.ParseError.exception(errors: errors)}
  end
end
```

All other content item modules follow this same pattern: `@schema`
drives `@type`, `@enforce_keys`, `defstruct`, and `new/1`.

**`to_json/1`**: Defined via a Zoi codec that maps struct fields to
camelCase JSON keys. The codec is the single source of truth for
serialization — no hand-written key mapping. `extensions` are merged
into the top-level output via `Map.merge/2`, same pattern as
`GradeService.Score`.

**Tests**:
- `new/1` with `url` only succeeds
- `new/1` without `url` returns validation error
- `new/1` with all optional fields succeeds
- `new/1` defaults `extensions` to `%{}`
- `to_json/1` includes `"type" => "link"`
- `to_json/1` serializes `icon` with `url`, `width`, `height`
- `to_json/1` serializes `window` with camelCase keys (`targetName`, `windowFeatures`)
- `to_json/1` serializes `iframe` with `src`, `width`, `height`
- `to_json/1` excludes `nil` fields
- `to_json/1` merges `extensions` into top-level output

### 3.3 `Ltix.DeepLinking.ContentItem.LtiResourceLink`

**Spec basis**: [DL §3.2] A link to an LTI resource, usually delivered
by the same tool.

**Line item sub-structure** [DL §3.2, AGS §4.9]:

> [DL §3.2]: "A lineItem object that indicates this activity is expected
> to receive scores; the platform may automatically create a corresponding
> line item when the resource link is created."

```elixir
@line_item_schema Zoi.map(%{
  score_maximum: Zoi.number(description: "Maximum score (positive decimal, must be > 0).")
                 |> Zoi.positive() |> Zoi.required(),
  label: Zoi.string(description: "Line item label. Defaults to the content item's title."),
  resource_id: Zoi.string(description: "Tool-provided resource identifier."),
  tag: Zoi.string(description: "Qualifier tag (e.g., \"grade\", \"originality\")."),
  grades_released: Zoi.boolean(description: "Whether the platform should release grades to learners.")
})
```

**Custom parameters** [DL §3.2]:

> "A map of key/value custom parameters. Those parameters MUST be included
> in the LtiResourceLinkRequest payload."

Map values must be strings. `null` is not a valid value.

**Available / Submission** [DL §3.2]:

> `startDateTime` (optional): ISO 8601 date and time when the link
> becomes accessible.
> `endDateTime` (optional): ISO 8601 date and time when the link stops
> being accessible.

```elixir
@time_window_schema Zoi.map(%{
  start_date_time: Zoi.string(description: "ISO 8601 start date/time."),
  end_date_time: Zoi.string(description: "ISO 8601 end date/time.")
})
```

**Schema, struct, and constructor**:

```elixir
@schema Zoi.struct(__MODULE__, %{
  url: Zoi.string(description: "Launch URL. If absent, platform uses the tool's base URL."),
  title: Zoi.string(description: "Plain text title."),
  text: Zoi.string(description: "Plain text description."),
  icon: @icon_schema,
  thumbnail: @icon_schema,
  window: @window_schema,
  iframe: @resource_link_iframe_schema,
  custom: Zoi.map(Zoi.string(), Zoi.string()) |> Zoi.description("Custom parameters for the launch."),
  line_item: @line_item_schema,
  available: @time_window_schema,
  submission: @time_window_schema,
  extensions:
    Zoi.map(Zoi.string(), Zoi.any(),
      description: "Extension properties keyed by fully qualified URLs."
    )
    |> Zoi.default(%{})
})

@type t :: unquote(Zoi.type_spec(@schema))
@enforce_keys Zoi.Struct.enforce_keys(@schema)
defstruct Zoi.Struct.struct_fields(@schema)

# Same parse → Zoi.ParseError pattern as Link.
@spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
def new(opts \\ [])
```

No required fields — the spec makes everything optional for
`ltiResourceLink`, since the platform can use the tool's base launch URL
if `url` is absent.

**`to_json/1`**: Via codec. Returns a map with `"type" =>
"ltiResourceLink"`. Codec handles camelCase key mapping for all
sub-structures: `score_maximum` → `scoreMaximum`,
`resource_id` → `resourceId`, `grades_released` → `gradesReleased`,
`start_date_time` → `startDateTime`, `end_date_time` → `endDateTime`.
`extensions` are merged into the top-level output via `Map.merge/2`.

**Tests**:
- `new/1` with no arguments succeeds (all optional)
- `new/1` with `url`, `title`, `custom` succeeds
- `new/1` with `custom` containing non-string values returns error
- `new/1` with `line_item` validates `score_maximum` > 0
- `new/1` with `line_item` missing `score_maximum` returns error
- `new/1` defaults `extensions` to `%{}`
- `to_json/1` includes `"type" => "ltiResourceLink"`
- `to_json/1` serializes `custom` map as-is
- `to_json/1` serializes `lineItem` with camelCase keys
- `to_json/1` serializes `available` / `submission` with camelCase keys
- `to_json/1` excludes `nil` / absent fields
- `to_json/1` with only `line_item` and no `url` produces valid output
- `to_json/1` merges `extensions` into top-level output

### 3.4 `Ltix.DeepLinking.ContentItem.File`

**Spec basis**: [DL §3.3] A resource to be transferred from the tool and
stored/processed by the platform.

> [DL §3.3]: "The URL to the resource should be considered short lived
> and the platform must process the file within a short time frame
> (within minutes)."

**Schema, struct, and constructor**:

Note: `media_type` is not in the §3.3 property table but is present in
the Appendix B example — a spec inconsistency. Included for interop.

```elixir
@schema Zoi.struct(__MODULE__, %{
  url: Zoi.string(description: "URL of the file (may be short-lived).") |> Zoi.required(),
  title: Zoi.string(description: "Plain text title."),
  text: Zoi.string(description: "Plain text description."),
  icon: @icon_schema,
  thumbnail: @icon_schema,
  media_type: Zoi.string(description: "MIME type of the file (e.g., \"application/pdf\")."),
  expires_at: Zoi.string(description: "ISO 8601 expiration time for the URL."),
  extensions:
    Zoi.map(Zoi.string(), Zoi.any(),
      description: "Extension properties keyed by fully qualified URLs."
    )
    |> Zoi.default(%{})
})

@type t :: unquote(Zoi.type_spec(@schema))
@enforce_keys Zoi.Struct.enforce_keys(@schema)
defstruct Zoi.Struct.struct_fields(@schema)

# Same parse → Zoi.ParseError pattern as Link.
@spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
def new(opts)
```

**`to_json/1`**: Via codec. `"type" => "file"`. Codec maps
`media_type` → `"mediaType"`, `expires_at` → `"expiresAt"`.
`extensions` are merged into the top-level output via `Map.merge/2`.

**Tests**:
- `new/1` with `url` succeeds
- `new/1` without `url` returns error
- `to_json/1` includes `"type" => "file"`
- `to_json/1` serializes `media_type` as `"mediaType"`
- `to_json/1` serializes `expires_at` as `"expiresAt"`
- `to_json/1` merges `extensions` into top-level output

### 3.5 `Ltix.DeepLinking.ContentItem.HtmlFragment`

**Spec basis**: [DL §3.4] An HTML fragment to be embedded in an HTML
document.

> [DL §3.4]: "If the HTML fragment renders a single resource which is
> also addressable directly, the tool SHOULD use the `link` type with an
> `embed` code."

**Schema, struct, and constructor**:

```elixir
@schema Zoi.struct(__MODULE__, %{
  html: Zoi.string(description: "HTML fragment to embed.") |> Zoi.required(),
  title: Zoi.string(description: "Plain text title."),
  text: Zoi.string(description: "Plain text description."),
  extensions:
    Zoi.map(Zoi.string(), Zoi.any(),
      description: "Extension properties keyed by fully qualified URLs."
    )
    |> Zoi.default(%{})
})

@type t :: unquote(Zoi.type_spec(@schema))
@enforce_keys Zoi.Struct.enforce_keys(@schema)
defstruct Zoi.Struct.struct_fields(@schema)

# Same parse → Zoi.ParseError pattern as Link.
@spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
def new(opts)
```

**`to_json/1`**: Via codec. `"type" => "html"`. No camelCase keys
needed (all fields are single-word). `extensions` are merged into the
top-level output via `Map.merge/2`.

**Tests**:
- `new/1` with `html` succeeds
- `new/1` without `html` returns error
- `to_json/1` includes `"type" => "html"` and `"html"` field
- `to_json/1` merges `extensions` into top-level output

### 3.6 `Ltix.DeepLinking.ContentItem.Image`

**Spec basis**: [DL §3.5] A URL pointing to an image that SHOULD be
rendered directly using the HTML `img` tag.

**Schema, struct, and constructor**:

```elixir
@schema Zoi.struct(__MODULE__, %{
  url: Zoi.string(description: "Fully qualified URL of the image.") |> Zoi.required(),
  title: Zoi.string(description: "Plain text title."),
  text: Zoi.string(description: "Plain text description."),
  icon: @icon_schema,
  thumbnail: @icon_schema,
  width: Zoi.integer(description: "Image width in pixels."),
  height: Zoi.integer(description: "Image height in pixels."),
  extensions:
    Zoi.map(Zoi.string(), Zoi.any(),
      description: "Extension properties keyed by fully qualified URLs."
    )
    |> Zoi.default(%{})
})

@type t :: unquote(Zoi.type_spec(@schema))
@enforce_keys Zoi.Struct.enforce_keys(@schema)
defstruct Zoi.Struct.struct_fields(@schema)

# Same parse → Zoi.ParseError pattern as Link.
@spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
def new(opts)
```

**`to_json/1`**: Via codec. `"type" => "image"`. No camelCase keys
needed (all fields are single-word). `extensions` are merged into the
top-level output via `Map.merge/2`.

**Tests**:
- `new/1` with `url` succeeds
- `new/1` without `url` returns error
- `to_json/1` includes `"type" => "image"`, `"width"`, `"height"`
- `to_json/1` merges `extensions` into top-level output

### 3.7 Custom Content Item Types

> [DL §3.7]: "When a new type is added, it must to the minimum contain a
> `type` property and a value that uniquely identifies the new type. To
> avoid collisions, the value must be a fully qualified URL unless
> specified otherwise by IMS Global."

The `build_response/3` function accepts raw maps alongside struct-based
content items. A raw map must contain a `"type"` key:

```elixir
items = [
  lti_resource_link,
  %{"type" => "https://www.example.com/custom_type", "data" => "somedata"}
]
```

This provides an escape hatch for proprietary or experimental content
types without requiring library changes.

### 3.8 Content Item Serialization Dispatch

A private function in `Ltix.DeepLinking` dispatches serialization based
on struct type, with a raw map fallback:

```elixir
defp serialize_item(%Link{} = item), do: Link.to_json(item)
defp serialize_item(%LtiResourceLink{} = item), do: LtiResourceLink.to_json(item)
defp serialize_item(%File{} = item), do: File.to_json(item)
defp serialize_item(%HtmlFragment{} = item), do: HtmlFragment.to_json(item)
defp serialize_item(%Image{} = item), do: Image.to_json(item)
defp serialize_item(%{"type" => _} = raw_map), do: raw_map
```

No protocol needed. The set of standard types is fixed by the spec, and
custom types use raw maps. If extensibility demand emerges (unlikely),
a protocol can be added later without breaking changes.

---

## 4. Response Builder

### 4.1 `Ltix.DeepLinking.Response` — Response Struct

A simple struct holding the signed JWT and the platform's return URL:

```elixir
defstruct [:jwt, :return_url]

@type t :: %__MODULE__{
  jwt: String.t(),
  return_url: String.t()
}
```

### 4.2 `Ltix.DeepLinking.build_response/3` — Build the Response JWT

**Spec basis**: [DL §4.5] Deep linking response message; [Sec §5.2]
Tool-Originating Messages.

> [DL §2.3]: "After encoding the deep linking return message as a JWT,
> the tool MUST always perform this redirection using an auto-submitted
> form as an HTTP POST request using the `JWT` parameter."

```elixir
@build_response_schema Zoi.keyword(%{
  msg: Zoi.string(description: "User-facing message to show on return to the platform."),
  log: Zoi.string(description: "Log message for the platform."),
  error_message: Zoi.string(description: "User-facing error message."),
  error_log: Zoi.string(description: "Error log message for the platform.")
})

@spec build_response(LaunchContext.t(), [content_item()], keyword()) ::
  {:ok, Response.t()} | {:error, Exception.t()}
def build_response(%LaunchContext{} = context, items \\ [], opts \\ [])
```

**`content_item()` type**: Any content item struct (`%Link{}`,
`%LtiResourceLink{}`, etc.) or a raw map with a `"type"` key.

**Flow**:

1. Validate opts with `Zoi`
2. Verify `context.claims.message_type == "LtiDeepLinkingRequest"`
   — return `InvalidMessageType` error if not
3. Extract `deep_linking_settings` from claims
4. Validate content items against settings (see §4.4)
5. Serialize content items via `serialize_item/1`
6. Build JWT claims (see §4.3)
7. Sign JWT with `context.registration.tool_jwk`
8. Return `{:ok, %Response{jwt: jwt, return_url: deep_link_return_url}}`

**Example usage**:

```elixir
{:ok, context} = Ltix.handle_callback(params, state)

{:ok, link} = Ltix.DeepLinking.ContentItem.LtiResourceLink.new(
  url: "https://tool.example.com/activity/123",
  title: "Quiz 1",
  custom: %{"quiz_id" => "123"},
  line_item: [score_maximum: 100, label: "Quiz 1"]
)

{:ok, response} = Ltix.DeepLinking.build_response(context, [link],
  msg: "Successfully selected 1 item"
)

# response.jwt is the signed JWT
# response.return_url is the platform's deep_link_return_url
# Deliver via auto-submit form POST (framework-specific, e.g. ltix_phoenix)
```

### 4.3 JWT Construction

**Spec basis**: [DL §4.5] response message claims; [Sec §5.2]
tool-originating message signing.

The response JWT contains these claims:

| Claim | Value | Source | Spec |
|-------|-------|--------|------|
| `iss` | Tool's `client_id` | `context.registration.client_id` | [Sec §5.2.2] |
| `aud` | Platform's issuer URL | `context.registration.issuer` | [DL §4.5.1] |
| `exp` | Current time + 300s | Generated | [Sec §5.2.2] |
| `iat` | Current time | Generated | [Sec §5.2.2] |
| `nonce` | Fresh UUID | Generated | [Sec §5.2.2] |
| `azp` | Platform's issuer URL | `context.registration.issuer` | [Sec §5.2.2] ¹ |
| `deployment_id` | Deployment ID | `context.deployment.deployment_id` | [DL §4.5.4] |
| `message_type` | `"LtiDeepLinkingResponse"` | Constant | [DL §4.5.2] |
| `version` | `"1.3.0"` | Constant | [DL §4.5.3] |
| `content_items` | Serialized items array | From items parameter | [DL §4.5.6] |
| `data` | Opaque value from request | `settings.data` | [DL §4.5.5] |
| `msg` | User message | From opts | [DL §4.5.7] |
| `log` | Log message | From opts | [DL §4.5.8] |
| `errormsg` | Error message | From opts `:error_message` | [DL §4.5.9] |
| `errorlog` | Error log | From opts `:error_log` | [DL §4.5.10] |

¹ **`azp` value**: The DL spec's Appendix B example incorrectly shows
`azp` set to the tool's `client_id` (matching `iss`). This contradicts
[Sec §5.2.2], which says for tool-originating messages: "If present,
\[`azp`\] MUST contain the same value as in the `aud` Claim." The
platform validation rule [Sec §5.2.3 rule 5] confirms: "the Platform
SHOULD verify that its Issuer URL is the Claim Value." The `azp` claim
means "authorized party — the party to which the JWT was issued." The
tool issues the JWT *to* the platform, so `azp` = platform's issuer URL
= `aud`. We follow the normative text, not the buggy example.
Although `azp` is optional and redundant when `aud` is a single value,
we include it per the robustness principle — be conservative in what you
send. Some platforms may check for it, and sending a correct value costs
nothing.

> [DL §4.5.1]: "the required `aud` must contain the case-sensitive URL
> used by the Platform to identify itself as an Issuer, that is the `iss`
> value in the Deep Linking request message."

> [DL §4.5.5]: "The `data` value must match the value of the `data`
> property of the `deep_linking_settings` claim from the
> `LtiDeepLinkingRequest` message. This claim is required if present in
> LtiDeepLinkingRequest message."

The `data` field is automatically echoed from `settings.data` — the
caller does not need to (and cannot) set it manually.

**JOSE header**: `{"alg": "RS256", "kid": "<kid_from_tool_jwk>"}`.
Uses the `kid` from `registration.tool_jwk`.

**Signing**: Uses `JOSE.JWT.sign/3` with the tool's private key, same
pattern as `Ltix.OAuth.ClientCredentials` for client assertions.

**Sketch**:

```elixir
defp build_jwt_claims(context, items_json, opts) do
  now = System.system_time(:second)
  settings = context.claims.deep_linking_settings
  reg = context.registration

  claims = %{
    "iss" => reg.client_id,
    "aud" => reg.issuer,
    "exp" => now + 300,
    "iat" => now,
    "nonce" => generate_nonce(),
    "azp" => reg.issuer,
    @lti_prefix <> "deployment_id" => context.deployment.deployment_id,
    @lti_prefix <> "message_type" => "LtiDeepLinkingResponse",
    @lti_prefix <> "version" => "1.3.0",
    @dl_prefix <> "content_items" => items_json
  }

  claims
  |> maybe_put(@dl_prefix <> "data", settings.data)
  |> maybe_put(@dl_prefix <> "msg", Keyword.get(opts, :msg))
  |> maybe_put(@dl_prefix <> "log", Keyword.get(opts, :log))
  |> maybe_put(@dl_prefix <> "errormsg", Keyword.get(opts, :error_message))
  |> maybe_put(@dl_prefix <> "errorlog", Keyword.get(opts, :error_log))
end
```

### 4.4 Content Item Validation Against Settings

Before serializing, `build_response/3` validates content items against
the platform's `deep_linking_settings`:

1. **Type check**: Each item's type must be in `accept_types`.
   An `ltiResourceLink` item is rejected if `"ltiResourceLink"` is not
   in `accept_types`.

2. **Multiplicity check**: If `accept_multiple` is explicitly `false`,
   at most one item may be returned. More than one returns
   `ContentItemsExceedLimit`.

3. **Line item check**: If an `ltiResourceLink` includes a `line_item`
   and `accept_lineitem` is explicitly `false`, return
   `LineItemNotAccepted`. Note: the spec says line items will be
   "ignored", not that the tool must not send them. This is stricter
   than required — we prefer to fail early rather than silently send
   data the platform will discard.

> [DL §4.4.1 `accept_lineitem`]: "False indicates line items will be
> ignored. True indicates the platform will create a line item when
> creating the resource link."

Validation runs by default. An empty items list is always valid (the
tool may return no items).

**Tests**:
- Items with types in `accept_types` pass validation
- Item with type not in `accept_types` returns `ContentItemTypeNotAccepted` error
- Multiple items when `accept_multiple: false` returns `ContentItemsExceedLimit` error
- Single item when `accept_multiple: false` succeeds
- Multiple items when `accept_multiple: true` succeeds
- Multiple items when `accept_multiple` is nil succeeds (default: allow)
- LtiResourceLink with `line_item` when `accept_lineitem: false` returns `LineItemNotAccepted` error
- LtiResourceLink with `line_item` when `accept_lineitem: true` succeeds
- LtiResourceLink with `line_item` when `accept_lineitem` is nil succeeds (no assumption)
- Empty items list always succeeds
- Raw map items validated by `"type"` key

---

## 5. Error Types

New Splode errors for deep linking business-logic failures. Zoi
validation errors from content item `new/1` constructors are wrapped in
`Zoi.ParseError` (a proper exception with `message/1`), preserving the
`{:error, exception}` API contract.

### 5.1 `Ltix.Errors.Invalid.InvalidMessageType`

Raised when `build_response/3` is called with a `LaunchContext` that
is not a deep linking request.

```elixir
use Splode.Error, fields: [:message_type, :spec_ref], class: :invalid

def message(%{message_type: mt}) do
  "Expected LtiDeepLinkingRequest but got #{mt}; build_response requires a deep linking launch"
end
```

### 5.2 `Ltix.Errors.Invalid.ContentItemTypeNotAccepted`

Raised when a content item's type is not in the platform's
`accept_types` list.

```elixir
use Splode.Error, fields: [:type, :accept_types, :spec_ref], class: :invalid

# spec_ref: "DL §4.4.1"
def message(%{type: type, accept_types: accepted}) do
  "Content item type #{inspect(type)} is not accepted; platform accepts: #{inspect(accepted)}"
end
```

### 5.3 `Ltix.Errors.Invalid.ContentItemsExceedLimit`

Raised when multiple items are returned but `accept_multiple` is `false`.

```elixir
use Splode.Error, fields: [:count, :spec_ref], class: :invalid

# spec_ref: "DL §4.4.1"
def message(%{count: count}) do
  "#{count} content items returned but platform does not accept multiple items"
end
```

### 5.4 `Ltix.Errors.Invalid.LineItemNotAccepted`

Raised when a content item includes a `line_item` but the platform's
`accept_lineitem` is `false`.

```elixir
use Splode.Error, fields: [:spec_ref], class: :invalid

# spec_ref: "DL §4.4.1"
def message(_) do
  "Content item includes a line_item but the platform does not accept line items"
end
```

---

## 6. Test Helpers

### 6.1 `Ltix.Test.build_launch_context/2` — Deep Linking Support

Extend the existing `build_launch_context/2` to support DL contexts:

```elixir
context = Ltix.Test.build_launch_context(platform,
  message_type: :deep_linking,
  deep_linking_settings: %{
    accept_types: ["ltiResourceLink", "link"],
    accept_multiple: true,
    auto_create: true
  }
)
```

**Changes**:

When `message_type: :deep_linking` (or
`message_type: "LtiDeepLinkingRequest"`):
- `message_type` set to `"LtiDeepLinkingRequest"`
- `resource_link` set to `nil` (not present in DL requests)
- `deep_linking_settings` populated from the option map, with sensible
  defaults:
  - `deep_link_return_url` defaults to
    `"https://platform.example.com/deep_links"`
  - `accept_types` defaults to
    `["ltiResourceLink", "link", "file", "html", "image"]`
  - `accept_presentation_document_targets` defaults to
    `["iframe", "window", "embed"]`

```elixir
defp build_deep_linking_settings(nil) do
  # Default settings for testing
  %DeepLinkingSettings{
    deep_link_return_url: "https://platform.example.com/deep_links",
    accept_types: ["ltiResourceLink", "link", "file", "html", "image"],
    accept_presentation_document_targets: ["iframe", "window", "embed"],
    accept_multiple: true
  }
end

defp build_deep_linking_settings(map) when is_map(map) do
  %DeepLinkingSettings{
    deep_link_return_url:
      Map.get(map, :deep_link_return_url, "https://platform.example.com/deep_links"),
    accept_types:
      Map.get(map, :accept_types, ["ltiResourceLink", "link", "file", "html", "image"]),
    accept_presentation_document_targets:
      Map.get(map, :accept_presentation_document_targets, ["iframe", "window", "embed"]),
    accept_media_types: Map.get(map, :accept_media_types),
    accept_multiple: Map.get(map, :accept_multiple, true),
    accept_lineitem: Map.get(map, :accept_lineitem),
    auto_create: Map.get(map, :auto_create),
    title: Map.get(map, :title),
    text: Map.get(map, :text),
    data: Map.get(map, :data)
  }
end
```

### 6.2 `Ltix.Test.launch_params/2` — Deep Linking Launch

Extend `launch_params/2` to build DL launch JWTs:

```elixir
launch_params = Ltix.Test.launch_params(platform,
  nonce: nonce,
  state: state,
  message_type: :deep_linking,
  deep_linking_settings: %{accept_types: ["ltiResourceLink"]}
)
```

When `message_type: :deep_linking`:
- `message_type` claim set to `"LtiDeepLinkingRequest"`
- `resource_link` claim omitted
- `deep_linking_settings` claim included
- `roles` claim optional (include if provided, omit if not)

### 6.3 `Ltix.Test.verify_deep_linking_response/2` — Response Verification

A test helper to verify the tool's DL response JWT. Decodes and verifies
the JWT using the tool's public key, then returns the parsed claims:

```elixir
@spec verify_deep_linking_response(Platform.t(), String.t()) ::
  {:ok, map()} | {:error, term()}
def verify_deep_linking_response(%Platform{} = platform, jwt)
```

This lets test code assert on the response:

```elixir
{:ok, response} = Ltix.DeepLinking.build_response(context, [item])

{:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, response.jwt)
assert claims["https://purl.imsglobal.org/spec/lti/claim/message_type"] == "LtiDeepLinkingResponse"

content_items = claims["https://purl.imsglobal.org/spec/lti-dl/claim/content_items"]
assert length(content_items) == 1
assert hd(content_items)["type"] == "ltiResourceLink"
```

---

## 7. Directory Structure (New Files)

```
lib/
  ltix/
    deep_linking.ex                          # Public API: build_response
    deep_linking/
      response.ex                            # %Response{jwt, return_url}
      content_item/
        link.ex                              # %Link{} + new/1, to_json/1
        lti_resource_link.ex                 # %LtiResourceLink{} + new/1, to_json/1
        file.ex                              # %File{} + new/1, to_json/1
        html_fragment.ex                     # %HtmlFragment{} + new/1, to_json/1
        image.ex                             # %Image{} + new/1, to_json/1
    errors/
      invalid/
        invalid_message_type.ex              # build_response on non-DL context
        content_item_type_not_accepted.ex    # item type not in accept_types
        content_items_exceed_limit.ex        # multiple items when accept_multiple=false
        line_item_not_accepted.ex            # line_item when accept_lineitem=false
test/
  ltix/
    deep_linking_test.exs                    # build_response, validation
    deep_linking/
      content_item/
        link_test.exs                        # Link new/to_json
        lti_resource_link_test.exs           # LtiResourceLink new/to_json
        file_test.exs                        # File new/to_json
        html_fragment_test.exs               # HtmlFragment new/to_json
        image_test.exs                       # Image new/to_json
  ltix/
    oidc/
      callback_deep_linking_test.exs         # Callback with DL message type
```

---

## 8. Implementation Order

Dependencies flow top-down. Each phase leaves the library in a working,
testable state.

### Phase 0: Callback Changes

1. **`DeepLinkingSettings.from_json/1` validation** — validate
   `accept_types` and `accept_presentation_document_targets` as required
   [DL §4.4.1]

2. **`Ltix.OIDC.Callback` message type handling** — accept
   `LtiDeepLinkingRequest`, branch validation per message type

3. **`Ltix.Test` extensions** — support `message_type: :deep_linking` in
   `build_launch_context/2` and `launch_params/2`

**Acceptance criteria**:
- [x] `handle_callback/3` succeeds with `LtiDeepLinkingRequest` JWT
- [x] DL requests without `resource_link` and `roles` claims succeed
- [x] DL requests without `deep_linking_settings` return `MissingClaim`
- [x] `DeepLinkingSettings.from_json/1` validates `accept_types` and
      `accept_presentation_document_targets` as required [DL §4.4.1]
- [x] `build_launch_context(platform, message_type: :deep_linking)`
      produces a DL context with `deep_linking_settings` populated
- [x] Existing resource link launch tests pass unchanged

### Phase 1: Content Item Types (no JWT, no HTTP)

4. **`Ltix.DeepLinking.ContentItem.Link`** — struct, `new/1`, `to_json/1`
5. **`Ltix.DeepLinking.ContentItem.LtiResourceLink`** — struct, `new/1`,
   `to_json/1`
6. **`Ltix.DeepLinking.ContentItem.File`** — struct, `new/1`, `to_json/1`
7. **`Ltix.DeepLinking.ContentItem.HtmlFragment`** — struct, `new/1`,
   `to_json/1`
8. **`Ltix.DeepLinking.ContentItem.Image`** — struct, `new/1`,
   `to_json/1`

Pure data construction and serialization. No side effects, no JWT
signing. Each module is independent.

**Acceptance criteria**:
- [X] Each content item type serializes to the correct JSON structure
      with `"type"` field [DL §3.1–§3.5]
- [X] Zoi validates required fields (e.g., `url` for Link,
      `html` for HtmlFragment)
- [X] Sub-structures serialize to camelCase (`scoreMaximum`,
      `targetName`, `startDateTime`, etc.)
- [X] `nil` / absent optional fields are excluded from JSON output
- [X] `LtiResourceLink.new/1` validates `line_item.score_maximum` > 0
- [X] Custom parameter map values must be strings [DL §3.2]

### Phase 2: Response Builder

9. **Error types** — `InvalidMessageType`, `ContentItemTypeNotAccepted`,
   `ContentItemsExceedLimit`, `LineItemNotAccepted`

10. **`Ltix.DeepLinking.Response`** — struct

11. **`Ltix.DeepLinking.build_response/3`** — content item validation,
    JWT construction, signing

12. **`Ltix.Test.verify_deep_linking_response/2`** — JWT verification
    helper for tests

**Acceptance criteria**:
- [x] `build_response/3` returns `{:ok, %Response{}}` with signed JWT
      and return URL
- [x] JWT `iss` = `client_id`, `aud` = platform issuer [DL §4.5.1]
- [x] JWT includes `deployment_id` from context [DL §4.5.4]
- [x] JWT `message_type` = `"LtiDeepLinkingResponse"` [DL §4.5.2]
- [x] JWT `version` = `"1.3.0"` [DL §4.5.3]
- [x] `data` echoed from `deep_linking_settings.data` [DL §4.5.5]
- [x] `data` omitted when not present in settings [DL §4.5.5]
- [x] Content items serialized into
      `https://purl.imsglobal.org/spec/lti-dl/claim/content_items` array
      [DL §4.5.6]
- [x] Empty items list produces empty `content_items` array
- [x] `msg`, `log`, `error_message`, `error_log` opts map to JWT claims
      `msg`, `log`, `errormsg`, `errorlog` [DL §4.5.7–§4.5.10]
- [x] JWT signed with `registration.tool_jwk` using RS256 [Sec §5.2]
- [x] JOSE header includes `kid` from tool JWK [Sec §6.3]
- [x] `build_response/3` on non-DL context returns `InvalidMessageType`
- [x] Items with types not in `accept_types` return
      `ContentItemTypeNotAccepted`
- [x] Multiple items when `accept_multiple: false` return
      `ContentItemsExceedLimit`
- [x] Line items when `accept_lineitem: false` return
      `LineItemNotAccepted`
- [x] `verify_deep_linking_response/2` decodes and verifies the JWT

### Phase 3: Documentation

13. **`guides/deep-linking.md`** — Deep Linking guide
    - What deep linking is and the workflow
    - Handling `LtiDeepLinkingRequest` launches
    - Building content items (each type with examples)
    - Building and sending the response
    - Validation: `accept_types`, `accept_multiple`, `accept_lineitem`
    - Line item declaration through deep linking [AGS §4.9]
    - Custom content item types
    - Testing deep linking flows

14. **Module docs** — `@moduledoc` / `@doc` on all public modules and
    functions
    - `Ltix.DeepLinking`
    - `Ltix.DeepLinking.Response`
    - All content item modules

15. **Existing docs updates**
    - `lib/ltix.ex` — add Deep Linking section to moduledoc
    - `mix.exs` — add modules to doc groups, guide to extras
    - Update launch flow docs to mention DL message type

---

## 9. Test Strategy

### Unit Tests
- `DeepLinkingSettings.from_json/1` — validates required fields
- Each content item `new/1` — Zoi validation, required vs
  optional fields
- Each content item `to_json/1` — JSON structure, camelCase keys, nil
  exclusion
- Sub-structure serialization — icon, thumbnail, window, iframe, embed
- Content item validation against settings — type checks, multiplicity,
  line item acceptance
- JWT claim construction — all required claims present, data echoing,
  optional claims

### Integration Tests (Full OIDC Flow)
- Full DL launch: `handle_login → handle_callback` with
  `LtiDeepLinkingRequest` JWT
- DL launch with all optional claims (context, roles, custom)
- DL launch without `roles` and `sub` (both optional for DL)
- DL launch → `build_response` → verify JWT claims and signature
- Round-trip: DL launch → build content items → build response → verify
  response JWT contains correct content items and echoed data

### Callback Compatibility Tests
- Resource link launches continue to work unchanged
- DL requests without `resource_link` succeed
- DL requests without `deep_linking_settings` fail with clear error
- Mixed: same tool endpoint handles both message types via branching

### Test Helpers
- `build_launch_context(platform, message_type: :deep_linking)` —
  constructs DL context with settings
- `launch_params(platform, message_type: :deep_linking)` — builds DL
  launch JWT
- `verify_deep_linking_response(platform, jwt)` — decodes and verifies
  response JWT

---

## 10. Resolved Questions

1. **Deep Linking is not an AdvantageService**: It uses OIDC message
   flow, not OAuth + HTTP APIs. No `AdvantageService` behaviour, no
   `Ltix.OAuth.Client`, no `authenticate/2`. The tool signs a JWT with
   its private key and redirects via form POST.

2. **Module naming**: `Ltix.DeepLinking` (not `Ltix.DeepLinkingService`)
   because it's not an Advantage service in the OAuth sense. The lack of
   `Service` suffix signals this difference. Content items are nested
   under `Ltix.DeepLinking.ContentItem.*`.

3. **No content item protocol**: Pattern matching + raw map fallback
   handles serialization dispatch. The five standard types are fixed by
   the spec. Custom types use raw maps [DL §3.7]. A protocol can be
   added later if needed.

4. **`data` echoing is automatic**: `build_response/3` reads
   `settings.data` from the context and includes it in the JWT when
   present. The caller cannot set or override it — this prevents
   accidentally breaking the platform's CSRF/state tracking.

5. **Callback changes are minimal**: `Ltix.handle_callback/3` returns
   the same `{:ok, %LaunchContext{}}` for both message types. The caller
   branches on `context.claims.message_type`. No new public functions
   on `Ltix`.

6. **Validation is on by default**: `build_response/3` validates content
   items against `deep_linking_settings` (type acceptance, multiplicity,
   line item acceptance). The spec says the platform defines what it
   accepts; the library enforces those constraints. This prevents
   submitting items that the platform will reject.

7. **No HTML generation in Ltix**: The auto-submit form POST
   ([DL §2.3]) is a framework concern. Ltix returns a `%Response{}`
   with the signed JWT and return URL; delivering it via HTML form is
   left to framework-specific packages like `ltix_phoenix`.

8. **No `from_json/1` on content items**: Content items are outbound
   only (tool → platform). The tool never receives content items — it
   creates them. Only `new/1` and `to_json/1` are needed.

9. **Sub-structures are plain maps, not structs**: Icon, thumbnail,
   window, iframe, embed, line_item, available, and submission are
   represented as keyword lists in constructors and plain maps in JSON.
   Defining structs for each would add complexity without benefit — these
   are simple nested objects with 2-4 fields each.

10. **`accept_types` / `accept_presentation_document_targets` validation**:
    The current `DeepLinkingSettings.from_json/1` only validates
    `deep_link_return_url`. Both `accept_types` and
    `accept_presentation_document_targets` are required per [DL §4.4.1].
    Fixing this is included as Phase 0 step 1.

11. **Zoi for schema validation**: All modules use Zoi. `Zoi.struct/3`
    schemas are the single source of truth: they drive `@type`,
    `@enforce_keys`, `defstruct`, validation (`new/1`), and
    serialization (`to_json/1` via codecs). Zoi validation errors are
    wrapped in `Zoi.ParseError` (a proper exception), preserving the
    `{:error, exception}` API contract. Business-logic errors (type
    acceptance, multiplicity, line item acceptance) remain Splode errors.

12. **No `accept_media_types` validation**: The platform's
    `accept_media_types` setting (e.g., `"image/*,text/html"`) is not
    validated against File item `media_type` values. Media type matching
    with wildcards and parameters is complex, and the platform will
    reject invalid types anyway. Not worth the complexity.

13. **Type extensions via `extensions` field** [DL §3.6]: Standard
    content item types can be enriched with custom properties keyed by
    fully qualified URLs. Each content item struct carries an
    `extensions` field (`%{String.t() => term()}`, default `%{}`) that
    is merged into the top-level JSON output on serialization. This is
    the same pattern used by `GradeService.Score`,
    `GradeService.LineItem`, and `LaunchClaims`.

---

## 11. Open Questions

None. All design questions have been resolved (see §10).
