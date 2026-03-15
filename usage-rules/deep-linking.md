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

Build items with `ContentItem.*.new/1`:

- `Ltix.DeepLinking.ContentItem.LtiResourceLink` — activity that launches back into your tool
- `Ltix.DeepLinking.ContentItem.Link` — external URL (article, docs page)
- `Ltix.DeepLinking.ContentItem.File` — downloadable file with optional expiry
- `Ltix.DeepLinking.ContentItem.HtmlFragment` — inline HTML the platform embeds
- `Ltix.DeepLinking.ContentItem.Image` — image for direct rendering

## Platform Constraints

Before building items, check what the platform accepts:

```elixir
settings = context.claims.deep_linking_settings
settings.accept_types         # ["ltiResourceLink", "link", ...]
settings.accept_multiple      # true or false
settings.accept_lineitem      # true or false
```

`build_response/3` validates items against these constraints and returns errors if violated
(`ContentItemTypeNotAccepted`, `ContentItemsExceedLimit`, `LineItemNotAccepted`).

## Building LTI Resource Links with Line Items

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.LtiResourceLink.new(
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

- `line_item.score_maximum` is required and must be positive.
- Only include `line_item` if `settings.accept_lineitem` is `true`.

## Building the Response

```elixir
{:ok, response} = Ltix.DeepLinking.build_response(context, [link],
  msg: "Content selected successfully"
)
```

- Pass a list of items (or `[]` for cancellation).
- Options: `:msg`, `:log`, `:error_message`, `:error_log`.
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

- `InvalidMessageType` — `build_response/3` called on a non-deep-linking context
- `ContentItemTypeNotAccepted` — item type not in `settings.accept_types`
- `ContentItemsExceedLimit` — multiple items when `settings.accept_multiple` is `false`
- `LineItemNotAccepted` — line item on content item when `settings.accept_lineitem` is `false`
