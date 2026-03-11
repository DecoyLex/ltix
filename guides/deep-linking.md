# Deep Linking

Deep linking lets a platform ask your tool to select content. Instead
of launching directly into an activity, the platform sends an
`LtiDeepLinkingRequest` and your tool responds with one or more content
items the platform should link to. This guide covers handling deep
linking launches, building content items, and sending responses back
to the platform.

## Handling a deep linking launch

Deep linking requests arrive through the same OIDC flow as regular
launches. Your existing login and launch endpoints work without
changes. The difference is in `message_type`:

```elixir
def launch(conn, params) do
  state = get_session(conn, :lti_state)
  {:ok, context} = Ltix.handle_callback(params, state)

  case context.claims.message_type do
    "LtiDeepLinkingRequest" ->
      settings = context.claims.deep_linking_settings

      conn
      |> assign(:context, context)
      |> assign(:settings, settings)
      |> render(:content_picker)

    "LtiResourceLinkRequest" ->
      conn
      |> assign(:context, context)
      |> render(:launch)
  end
end
```

The `deep_linking_settings` struct tells you what the platform accepts:

```elixir
settings.accept_types
# => ["ltiResourceLink", "link"]

settings.accept_multiple
# => true

settings.accept_lineitem
# => true
```

Use these to tailor your selection UI. For example, hide the "create
assignment" option if `"ltiResourceLink"` is not in `accept_types`.

## Building content items

The most common content item is an LTI resource link, which tells the
platform to create a link that launches back into your tool:

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.LtiResourceLink.new(
  url: "https://tool.example.com/activities/123",
  title: "Chapter 3 Quiz"
)
```

Five content item types are available:

| Type | Module | When to use |
|------|--------|-------------|
| `ltiResourceLink` | `Ltix.DeepLinking.ContentItem.LtiResourceLink` | Activity that launches back into your tool |
| `link` | `Ltix.DeepLinking.ContentItem.Link` | External URL (article, documentation) |
| `file` | `Ltix.DeepLinking.ContentItem.File` | Downloadable file |
| `html` | `Ltix.DeepLinking.ContentItem.HtmlFragment` | Inline HTML the platform embeds |
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
{:ok, fragment} = Ltix.DeepLinking.ContentItem.HtmlFragment.new(
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

## Adding line items and custom parameters

LTI resource links can include a `line_item` to have the platform
auto-create a gradebook column. This connects deep linking to the
grade service, so you can post scores to that column later:

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.LtiResourceLink.new(
  url: "https://tool.example.com/quizzes/7",
  title: "Midterm Quiz",
  line_item: [score_maximum: 100, label: "Midterm Quiz"],
  custom: %{"quiz_id" => "7", "mode" => "graded"}
)
```

Set availability and submission windows with ISO 8601 timestamps:

```elixir
{:ok, link} = Ltix.DeepLinking.ContentItem.LtiResourceLink.new(
  url: "https://tool.example.com/assignments/5",
  title: "Homework 5",
  available: [
    start_date_time: "2025-03-01T00:00:00Z",
    end_date_time: "2025-03-31T23:59:59Z"
  ],
  submission: [
    end_date_time: "2025-03-15T23:59:59Z"
  ]
)
```

See [Building Content Items](cookbooks/building-content-items.md) for
more patterns.

## Sending the response

Once you have your content items, call `build_response/3` to create
the signed JWT:

```elixir
def submit_selection(conn, %{"selected_ids" => ids}) do
  context = get_session(conn, :dl_context)
  items = build_items_from_selection(ids)

  {:ok, response} = Ltix.DeepLinking.build_response(context, items,
    msg: "Selected #{length(items)} item(s)"
  )

  # POST response.jwt to response.return_url as the "JWT" form parameter
  html(conn, """
  <form method="post" action="#{response.return_url}">
    <input type="hidden" name="JWT" value="#{response.jwt}">
  </form>
  <script>document.forms[0].submit();</script>
  """)
end
```

`build_response/3` handles JWT construction and signing automatically.
It echoes the platform's `data` value from the settings, sets the
correct `iss`, `aud`, and `deployment_id` claims, and signs with
your tool's private key.

> #### Framework delivery {: .info}
>
> The auto-submit form POST above is shown for clarity. Your framework
> may provide helpers that handle this delivery automatically.

## Respecting platform constraints

`build_response/3` validates content items against the platform's
`deep_linking_settings` and returns an error if constraints are
violated:

```elixir
case Ltix.DeepLinking.build_response(context, items) do
  {:ok, response} ->
    # deliver response

  {:error, %Ltix.Errors.Invalid.ContentItemTypeNotAccepted{type: type}} ->
    # item type not in accept_types

  {:error, %Ltix.Errors.Invalid.ContentItemsExceedLimit{}} ->
    # multiple items when accept_multiple is false

  {:error, %Ltix.Errors.Invalid.LineItemNotAccepted{}} ->
    # line_item present when accept_lineitem is false
end
```

You can also check the settings before building items to tailor your
UI:

```elixir
settings = context.claims.deep_linking_settings

can_create_assignments? = "ltiResourceLink" in settings.accept_types
can_select_multiple? = settings.accept_multiple != false
can_attach_grades? = settings.accept_lineitem != false
```

## Custom content types

For one-off custom types, pass a raw map with a `"type"` key:

```elixir
custom_item = %{
  "type" => "https://vendor.example.com/custom_type",
  "data" => "some-payload"
}

{:ok, response} = Ltix.DeepLinking.build_response(context, [custom_item])
```

For reusable custom types, define a struct and implement the
`Ltix.DeepLinking.ContentItem` protocol:

```elixir
defmodule MyApp.ProctoredExam do
  defstruct [:url, :title, :duration_minutes]

  defimpl Ltix.DeepLinking.ContentItem do
    def item_type(_item), do: "https://myapp.example.com/proctored_exam"

    def to_json(item) do
      %{
        "type" => "https://myapp.example.com/proctored_exam",
        "url" => item.url,
        "title" => item.title,
        "https://myapp.example.com/duration" => item.duration_minutes
      }
    end
  end
end
```

In both cases, the platform's `accept_types` must include the custom
type string.

## Testing

### Testing your controller

Simulate a deep linking launch against your controller endpoints, the
same way the [Testing LTI Launches](cookbooks/testing-lti-launches.md)
cookbook tests regular launches:

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

When testing code that builds content items from your app's data, skip
the OIDC flow and construct the context directly with
`build_launch_context/2`:

```elixir
test "builds quiz items from selected activities", %{platform: platform} do
  context = Ltix.Test.build_launch_context(platform,
    message_type: :deep_linking,
    deep_linking_settings: %{accept_types: ["ltiResourceLink"]}
  )

  activities = [
    %{id: 1, title: "Quiz 1", max_score: 50},
    %{id: 2, title: "Quiz 2", max_score: 100}
  ]

  items = MyApp.DeepLinking.build_items(activities)
  {:ok, response} = Ltix.DeepLinking.build_response(context, items)

  assert response.return_url == context.claims.deep_linking_settings.deep_link_return_url
end
```

### Verifying response content

Use `Ltix.Test.verify_deep_linking_response/2` to decode the signed JWT
and assert on its content:

```elixir
test "response JWT contains the selected items", %{platform: platform} do
  context = Ltix.Test.build_launch_context(platform,
    message_type: :deep_linking
  )

  {:ok, link} = Ltix.DeepLinking.ContentItem.LtiResourceLink.new(
    url: "https://tool.example.com/quiz/1",
    title: "Quiz 1",
    line_item: [score_maximum: 100]
  )

  {:ok, response} = Ltix.DeepLinking.build_response(context, [link])
  {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, response.jwt)

  [item] = claims["https://purl.imsglobal.org/spec/lti-dl/claim/content_items"]
  assert item["type"] == "ltiResourceLink"
  assert item["lineItem"]["scoreMaximum"] == 100
end
```

## Next steps

- [Building Content Items](cookbooks/building-content-items.md):
  recipes for line items, custom parameters, extensions, and more
- [Grade Service](grade-service.md): posting scores to gradebook
  columns created through deep linking
- [Testing LTI Launches](cookbooks/testing-lti-launches.md):
  more test patterns for both launch types
- `Ltix.DeepLinking`: full API reference
- `Ltix.DeepLinking.ContentItem.LtiResourceLink`: all options for
  the most common content item type
