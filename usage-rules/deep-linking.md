# Deep Linking

Rules for implementing LTI Deep Linking flows — content selection, item construction,
and response delivery.

## Launch Type Detection

The same `handle_callback/3` handles both launch types. Branch on message type:

```elixir
{:ok, context} = Ltix.handle_callback(params, state)

case context.claims.message_type do
  "LtiDeepLinkingRequest" -> # show content picker UI
  "LtiResourceLinkRequest" -> # normal activity launch
end
```

## Content Item Types

Build items with `ContentItem.*.new/1`, which takes a keyword list or map, or with the raising `new!/1`. Unknown or invalid fields return `Ltix.Errors.Invalid.InvalidField`.

- `Ltix.DeepLinking.ContentItem.LTIResourceLink` — activity that launches back into your tool
- `Ltix.DeepLinking.ContentItem.Link` — external URL (article, docs page)
- `Ltix.DeepLinking.ContentItem.File` — downloadable file with optional expiry
- `Ltix.DeepLinking.ContentItem.HTMLFragment` — inline HTML the platform embeds
- `Ltix.DeepLinking.ContentItem.Image` — image for direct rendering

Date and time fields, such as `File`'s `expires_at` and a resource link's `available` and `submission` windows, take `DateTime` structs.

## Platform Constraints

Before building items, check what the platform accepts:

```elixir
settings = context.claims.deep_linking_settings
settings.accept_types          # ["ltiResourceLink", "link", ...]
settings.accept_multiple       # true or false
settings.accept_line_item      # true or false
settings.accept_presentation_document_targets  # ["iframe", "window", ...]
settings.accept_media_types    # "image/*,application/pdf" or nil
```

`build_response/3` validates items against these constraints and returns an error for each violation (see Errors below). Several violations are grouped in `Ltix.Errors.Invalid`.

## Building LTI Resource Links with Line Items

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
  url: "https://tool.example.com/quizzes/7",
  title: "Midterm Quiz",
  line_item: [
    score_maximum: 100,
    label: "Midterm Quiz",
    tag: "quiz",
    grades_released: true
  ],
  custom: %{"quiz_id" => "7", "mode" => "graded"}
)
```

- `line_item.score_maximum` is required and must be positive. A `label` must not be blank.
- `line_item` also accepts a map or a `%Ltix.GradeService.LineItem{}` without platform-assigned fields such as `id`.
- Only include `line_item` if `settings.accept_line_item` is `true`.

## Building the Response

```elixir
{:ok, response} = Ltix.DeepLinking.build_response(context, [link],
  message: "Content selected successfully"
)
```

- Pass a list of items (or `[]` for cancellation).
- Options: `:message`, `:log`, `:error_message`, `:error_log`. Unknown or invalid options raise `Ltix.Errors.Invalid.InvalidOption`.
- `build_response!/3` raises on error.
- Returns `%Response{jwt: signed_jwt, return_url: platform_url}`.

## Delivering the Response

The platform expects a POST with the signed JWT. Use an auto-submit form:

```elixir
html(conn, """
<form method="post" action="#{response.return_url}">
  <input type="hidden" name="JWT" value="#{response.jwt}">
</form>
<script>document.forms[0].submit();</script>
""")
```

## Errors

Errors about one item include its `index` in the list you passed.

- `InvalidMessageType` — `build_response/3` called on a non-deep-linking context
- `InvalidContentItem` when an item is not a content item or the items are not a list
- `ContentItemTypeNotAccepted` — item type not in `settings.accept_types`
- `ContentItemsExceedLimit` — multiple items when `settings.accept_multiple` is `false`
- `LineItemNotAccepted` — line item on content item when `settings.accept_line_item` is `false`
- `PresentationTargetNotAccepted` when an item's `iframe`, `window`, or `embed` is not in `settings.accept_presentation_document_targets`
- `MediaTypeNotAccepted` when a file's `media_type` does not match `settings.accept_media_types`
