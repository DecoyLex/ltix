# Deep Linking

Rules for implementing LTI Deep Linking flows, covering content selection, item construction, and response delivery.

## Launch type detection

The same `handle_callback/3` handles both launch types. Branch on message type.

```elixir
{:ok, launch} = Ltix.handle_callback(params, state)

case launch.claims.message_type do
  "LtiDeepLinkingRequest" -> render(conn, :content_picker, launch: launch)
  "LtiResourceLinkRequest" -> redirect(conn, external: launch.claims.target_link_uri)
end
```

## Content item types

Build items with `ContentItem.*.new/1`, which takes a keyword list or map, or with the raising `new!/1`. Unknown or invalid fields return `Ltix.Errors.Invalid.InvalidField`.

- `Ltix.DeepLinking.ContentItem.LTIResourceLink` - activity that launches back into your tool
- `Ltix.DeepLinking.ContentItem.Link` - external URL (article, docs page)
- `Ltix.DeepLinking.ContentItem.File` - downloadable file with optional expiry
- `Ltix.DeepLinking.ContentItem.HTMLFragment` - inline HTML the platform embeds
- `Ltix.DeepLinking.ContentItem.Image` - image for direct rendering

Date and time fields, such as `File`'s `expires_at` and a resource link's `available` and `submission` windows, take `DateTime` structs.

- **Never** pass a plain map to `build_response/3`. For another kind of content, follow [Custom content item type](https://ltix.hexdocs.pm/building-content-items.md#custom-content-item-type).
- **Never** pass `extensions:` to a content item's `new/1`. Pass a vendor property by its `:name`. [Vendor property](https://ltix.hexdocs.pm/building-content-items.md#vendor-property) has an example. A plugin in `config :ltix, plugins:` must declare it.

## Platform constraints

Before building items, check what the platform accepts.

```elixir
settings = launch.claims.deep_linking_settings
settings.accept_types          # ["ltiResourceLink", "link", ...]
settings.accept_multiple       # true, false, or nil
settings.accept_line_item      # true, false, or nil
settings.accept_presentation_document_targets  # ["iframe", "window", ...]
settings.accept_media_types    # "image/*,application/pdf" or nil
```

`build_response/3` validates items against these constraints and returns an error for each violation (see Errors below). Several violations are grouped in `Ltix.Errors.Invalid`.

## Building LTI resource links with line items

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
- `link.line_item` is an `%Ltix.DeepLinking.LineItem{}`. `line_item` also accepts a map or a `%Ltix.GradeService.LineItem{}` without platform-assigned fields such as `id`.
- Leave out `line_item` when `settings.accept_line_item` is `false`.

## Building the response

```elixir
{:ok, response} = Ltix.DeepLinking.build_response(launch, [link],
  message: "Content selected successfully"
)
```

- Pass a list of items (or `[]` for cancellation).
- Options are `:message`, `:log`, `:error_message`, and `:error_log`. Unknown or invalid options raise `ArgumentError`.
- `:plugins` replaces the plugins the launch ran with.
- `build_response!/3` raises on error.
- Returns `{:ok, %Ltix.DeepLinking.Response{}}` with the signed `jwt` and the platform's `return_url`.
- To add a claim to the response, follow [Add claims to Deep Linking responses](https://ltix.hexdocs.pm/writing-deep-linking-plugins.md#add-claims-to-deep-linking-responses).

## Delivering the response

The platform requires a POST with the signed JWT. Use an auto-submit form rendered from a HEEx template. **Never** interpolate `return_url` into an HTML string.

```heex
<form id="deep-link-response" method="post" action={@response.return_url}>
  <input type="hidden" name="JWT" value={@response.jwt} />
  <noscript>
    <button type="submit">Return to platform</button>
  </noscript>
</form>
<script>document.getElementById("deep-link-response").submit();</script>
```

## Errors

Errors about one item include its `index` in the list you passed.

- `InvalidMessageType` - `build_response/3` called on a non-deep-linking launch
- `InvalidContentItem` when an item is not a content item of a type the plugins declare, or the items are not a list
- `ContentItemTypeNotAccepted` - item type not in `settings.accept_types`
- `ContentItemsExceedLimit` - multiple items when `settings.accept_multiple` is `false`
- `LineItemNotAccepted` - line item on content item when `settings.accept_line_item` is `false`
- `PresentationTargetNotAccepted` when an item's `iframe`, `window`, or `embed` is not in `settings.accept_presentation_document_targets`
- `MediaTypeNotAccepted` when a file's `media_type` does not match `settings.accept_media_types`
