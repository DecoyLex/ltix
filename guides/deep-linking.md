# Deep Linking

Deep linking lets a platform ask your tool to select content. The platform sends an `LtiDeepLinkingRequest` and your tool responds with one or more content items the platform should link to. This guide covers handling deep linking launches, building content items, and sending responses back to the platform.

## Handling a deep linking launch

Deep linking requests use the same OIDC flow as regular launches. Your existing login and launch endpoints work without changes. The difference is in `message_type`.

```elixir
def launch(conn, params) do
  state = get_session(conn, :lti_state)
  {:ok, launch} = Ltix.handle_callback(params, state)

  case launch.claims.message_type do
    "LtiDeepLinkingRequest" ->
      launch_id = MyApp.Launches.put(launch)

      conn
      |> put_session(:deep_linking_launch_id, launch_id)
      |> assign(:settings, launch.claims.deep_linking_settings)
      |> render(:content_picker)

    "LtiResourceLinkRequest" ->
      conn
      |> assign(:launch, launch)
      |> render(:launch)
  end
end
```

Sending the response later needs the launch, so keep it on the server and put only its ID in the session. `MyApp.Launches` stands for any server-side store with an expiry, such as an ETS table, Cachex, or a database table. Don't put the launch itself in the session. It has the user's identity and course data, and Phoenix session cookies are signed, not encrypted.

The `deep_linking_settings` struct lists what the platform accepts.

```elixir
settings.accept_types
# => ["ltiResourceLink", "link"]

settings.accept_multiple
# => true

settings.accept_line_item
# => true
```

Use these to adjust your selection UI. For example, hide the "create assignment" option if `"ltiResourceLink"` is not in `accept_types`.

## Building content items

The most common content item is an LTI resource link, which has the platform create a link that launches back into your tool.

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
  url: "https://tool.example.com/activities/123",
  title: "Chapter 3 Quiz"
)
```

Five content item types are available.

| Type | Module | When to use |
|------|--------|-------------|
| `ltiResourceLink` | `Ltix.DeepLinking.ContentItem.LTIResourceLink` | Activity that launches back into your tool |
| `link` | `Ltix.DeepLinking.ContentItem.Link` | External URL (article, documentation) |
| `file` | `Ltix.DeepLinking.ContentItem.File` | Downloadable file |
| `html` | `Ltix.DeepLinking.ContentItem.HTMLFragment` | Inline HTML the platform embeds |
| `image` | `Ltix.DeepLinking.ContentItem.Image` | Image for direct rendering |

```elixir
# External URL
{:ok, link} = Ltix.DeepLinking.ContentItem.Link.new(
  url: "https://docs.example.com/guide",
  title: "Setup Guide"
)

# Downloadable file
{:ok, file} = Ltix.DeepLinking.ContentItem.File.new(
  url: "https://tool.example.com/exports/report.pdf",
  title: "Lab Report Template",
  media_type: "application/pdf"
)

# Inline HTML
{:ok, fragment} = Ltix.DeepLinking.ContentItem.HTMLFragment.new(
  html: "<iframe src=\"https://tool.example.com/embed/42\"></iframe>",
  title: "Interactive Widget"
)

# Image
{:ok, image} = Ltix.DeepLinking.ContentItem.Image.new(
  url: "https://tool.example.com/images/diagram.png",
  title: "System Architecture",
  width: 800,
  height: 600
)
```

## Adding line items and custom properties

LTI resource links can include a `line_item` to ask the platform to create a line item for the link. The platform can ignore the request. When it creates the line item, post scores to it with the grade service. `link.line_item` is an `Ltix.DeepLinking.LineItem`.

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
  url: "https://tool.example.com/quizzes/7",
  title: "Midterm Quiz",
  line_item: [score_maximum: 100, label: "Midterm Quiz"],
  custom: %{"quiz_id" => "7", "mode" => "graded"}
)
```

Set availability and submission windows with `DateTime` values.

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
  url: "https://tool.example.com/assignments/5",
  title: "Homework 5",
  available: [
    start_date_time: ~U[2025-03-01 00:00:00Z],
    end_date_time: ~U[2025-03-31 23:59:59Z]
  ],
  submission: [
    end_date_time: ~U[2025-03-15 23:59:59Z]
  ]
)
```

See [Building Content Items](cookbooks/building-content-items.md) for more patterns.

## Sending the response

Once you have your content items, call `build_response/3` to create the signed JWT and render the response template.

```elixir
def submit_selection(conn, %{"selected_ids" => ids}) do
  {:ok, launch} = MyApp.Launches.fetch(get_session(conn, :deep_linking_launch_id))
  items = build_items_from_selection(ids)

  {:ok, response} = Ltix.DeepLinking.build_response(launch, items,
    message: "Selected #{length(items)} item(s)"
  )

  render(conn, :deep_linking_response, response: response)
end
```

Then use the response in your template.

```heex
<form id="deep-link-response" method="post" action={@response.return_url}>
  <input type="hidden" name="JWT" value={@response.jwt} />
  <noscript>
    <button type="submit">Return to platform</button>
  </noscript>
</form>
<script>document.getElementById("deep-link-response").submit();</script>
```

## Respecting platform constraints

`build_response/3` validates content items against the platform's `deep_linking_settings` and returns an error if constraints are violated. Errors about a single item include its `index` in the list you passed.

```elixir
case Ltix.DeepLinking.build_response(launch, items) do
  {:ok, response} ->
    render(conn, :deep_linking_response, response: response)

  {:error, %Ltix.Errors.Invalid.ContentItemTypeNotAccepted{index: index, type: type}} ->
    # item type not in accept_types
    show_error(conn, index, type)

  {:error, %Ltix.Errors.Invalid.ContentItemsExceedLimit{}} ->
    # multiple items when accept_multiple is false
    show_error(conn, :too_many_items)

  {:error, %Ltix.Errors.Invalid.LineItemNotAccepted{index: index}} ->
    # line_item present when accept_line_item is false
    show_error(conn, index, :line_item)

  {:error, %Ltix.Errors.Invalid.PresentationTargetNotAccepted{index: index, target: target}} ->
    # the item has an iframe, window, or embed not in accept_presentation_document_targets
    show_error(conn, index, target)

  {:error, %Ltix.Errors.Invalid.MediaTypeNotAccepted{index: index, media_type: media_type}} ->
    # the file's media_type does not match accept_media_types, such as "image/*"
    show_error(conn, index, media_type)

  {:error, %Ltix.Errors.Invalid{errors: errors}} ->
    # several of the above at once
    show_errors(conn, errors)
end
```

You can also check the settings before building items to adjust your UI.

```elixir
settings = launch.claims.deep_linking_settings

can_create_assignments? = "ltiResourceLink" in settings.accept_types
can_select_multiple? = settings.accept_multiple != false
can_attach_grades? = settings.accept_line_item != false
```

## Custom content types

Declare each custom type with `use Ltix.DeepLinking.ContentItemType`, and add it to a plugin. `build_response/3` returns `Ltix.Errors.Invalid.InvalidContentItem` for anything else, including a plain map. See [Building Content Items](cookbooks/building-content-items.md#custom-content-item-type).

## Testing

### Testing your controller

Simulate a deep linking launch against your controller endpoints, the same way the [Testing LTI Launches](cookbooks/testing-lti-launches.md) cookbook tests regular launches.

```elixir
test "deep linking launch renders content picker", %{conn: conn, platform: platform} do
  conn = post(conn, ~p"/lti/login", Ltix.Test.login_params(platform))
  state = get_session(conn, :lti_state)
  nonce = Ltix.Test.extract_nonce(redirected_to(conn, 302))

  conn =
    conn
    |> recycle()
    |> Plug.Test.init_test_session(%{lti_state: state})
    |> post(
      ~p"/lti/launch",
      Ltix.Test.launch_params(platform,
        nonce: nonce,
        state: state,
        message_type: :deep_linking
      )
    )

  assert html_response(conn, 200) =~ "Select content"
end
```

### Testing content selection logic

When testing code that builds content items from your app's data, skip the OIDC flow and build the launch directly with `Ltix.Test.build_launch/2`.

```elixir
test "builds quiz items from selected activities", %{platform: platform} do
  launch = Ltix.Test.build_launch(platform,
    message_type: :deep_linking,
    deep_linking_settings: %{accept_types: ["ltiResourceLink"]}
  )

  activities = [
    %{id: 1, title: "Quiz 1", max_score: 50},
    %{id: 2, title: "Quiz 2", max_score: 100}
  ]

  items = MyApp.DeepLinking.build_items(activities)
  {:ok, response} = Ltix.DeepLinking.build_response(launch, items)

  assert response.return_url == launch.claims.deep_linking_settings.deep_link_return_url
end
```

### Verifying response content

Use `Ltix.Test.verify_deep_linking_response/2` to decode the signed JWT and assert on its content.

```elixir
test "response JWT contains the selected items", %{platform: platform} do
  launch = Ltix.Test.build_launch(platform,
    message_type: :deep_linking
  )

  {:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
    url: "https://tool.example.com/quiz/1",
    title: "Quiz 1",
    line_item: [score_maximum: 100]
  )

  {:ok, response} = Ltix.DeepLinking.build_response(launch, [link])
  {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, response.jwt)

  [item] = claims["https://purl.imsglobal.org/spec/lti-dl/claim/content_items"]
  assert item["type"] == "ltiResourceLink"
  assert item["lineItem"]["scoreMaximum"] == 100
end
```

## Next steps

- [Building Content Items](cookbooks/building-content-items.md) - recipes for line items, custom properties, vendor properties, and more
- [Grade Service](grade-service.md) - posting scores to line items created through deep linking
- [Testing LTI Launches](cookbooks/testing-lti-launches.md) - more test patterns for both launch types
- [Writing Deep Linking Plugins](writing-deep-linking-plugins.md#add-claims-to-deep-linking-responses) - adding claims to the response
- `Ltix.DeepLinking` - full API reference
- `Ltix.DeepLinking.ContentItem.LTIResourceLink` - all options for the most common content item type
