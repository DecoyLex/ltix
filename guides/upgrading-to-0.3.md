# Upgrading to 0.3

Ltix 0.3 builds every feature on plugins. Every tool needs two changes, [`Ltix.Launch`](#ltix-launch-replaces-launchcontext-and-launchclaims) and [role URIs](#roles-are-uris). The other sections apply only when your tool uses what they name.

```elixir
# mix.exs
{:ltix, "~> 0.3"}
```

On 0.1, follow [Upgrading to 0.2](upgrading-to-0.2.md) first.

## Launches

### `Ltix.Launch` replaces `LaunchContext` and `LaunchClaims`

`Ltix.handle_callback/3` returns an `%Ltix.Launch{}`. Your storage adapter's records are in `source_registration` and `source_deployment`. `registration` and `deployment` are now the `Ltix.Registration` and `Ltix.Deployment` built from them, and `claims` is a map keyed by short name.

```elixir
# 0.2
{:ok, context} = Ltix.handle_callback(params, state)
user = MyApp.Accounts.get_user(context.registration.id, context.claims.subject)

# 0.3
{:ok, launch} = Ltix.handle_callback(params, state)
user = MyApp.Accounts.get_user(launch.source_registration.id, launch.claims.subject)
```

Pass the launch wherever you passed the launch context, such as to `authenticate/2` and `Ltix.DeepLinking.build_response/3`.

| 0.2 | 0.3 |
|---|---|
| `%Ltix.LaunchContext{}` | `%Ltix.Launch{}` |
| `context.registration` | `launch.source_registration` |
| `context.deployment` | `launch.source_deployment` |
| `context.claims` | `launch.claims` |
| `claims.extensions` | `launch.raw`, or `launch.claims` for a claim a plugin declares |
| `claims.ags_endpoint` | `Ltix.Launch.get_endpoint(launch, Ltix.GradeService)` |
| `claims.memberships_endpoint` | `Ltix.Launch.get_endpoint(launch, Ltix.MembershipsService)` |
| `Ltix.LaunchClaims.Context` | `Ltix.Claims.Context` |
| `Ltix.LaunchClaims.ResourceLink` | `Ltix.Claims.ResourceLink` |
| `Ltix.LaunchClaims.ToolPlatform` | `Ltix.Claims.ToolPlatform` |
| `Ltix.LaunchClaims.LaunchPresentation` | `Ltix.Claims.LaunchPresentation` |
| `Ltix.LaunchClaims.LIS` | `Ltix.Claims.LIS` |
| `Ltix.LaunchClaims.AGSEndpoint` | `Ltix.GradeService.Endpoint` |
| `Ltix.LaunchClaims.MembershipsEndpoint` | `Ltix.MembershipsService.Endpoint` |
| `Ltix.LaunchClaims.DeepLinkingSettings` | `Ltix.DeepLinking.Settings` |
| `LaunchClaims.from_json/2` | `Ltix.Claims.parse/2` |
| each claim's `from_json/1` | the claim module's `parse/2` |
| `Ltix.LaunchClaims.Context.to_map/1` | `Ltix.Type.to_json/3` |

Claim structs have two new fields, `extensions` for properties plugins parse and `unrecognized` for the rest.

`Ltix.Claims.parse/2` takes a plugin set and returns the endpoints too. Like 0.2's `from_json/2`, it doesn't run checks. `Ltix.PluginSet.resolve(nil)` returns the plugin set of your configured plugins.

```elixir
{:ok, plugins} = Ltix.PluginSet.resolve(nil)
{:ok, claims, _endpoints} = Ltix.Claims.parse(raw_claims, plugins)
```

### `:claim_parsers` is removed

Declare each claim in a plugin. Passing `:claim_parsers` raises `Ltix.Errors.Invalid.InvalidOption`, and Ltix ignores the `Ltix.LaunchClaims` configuration.

```elixir
# 0.2
config :ltix, Ltix.LaunchClaims,
  claim_parsers: %{"https://lms.example.com/claim/session" => &MyApp.Session.parse/1}

context.claims.extensions["https://lms.example.com/claim/session"]

# 0.3
defmodule MyApp.Session do
  use Ltix.Claim,
    claim: "https://lms.example.com/claim/session",
    name: :session,
    fields: [id: Zoi.string()]
end

defmodule MyApp.LtiPlugin do
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Ltix.Plugin.new(name: "My App")
    |> Ltix.Plugin.add(MyApp.Session)
  end
end

# config/config.exs
config :ltix, plugins: [MyApp.LtiPlugin]

launch.claims.session.id
```

A malformed value for a declared claim fails the launch. When you declare the claim with `strict: false`, a malformed value is the claim's `:default`, or `nil` without one, and the launch continues. See [Declare a claim](writing-claim-and-launch-plugins.md#declare-a-claim). A claim whose value needs only a Zoi schema needs no module, as [Declare a claim with a schema](writing-claim-and-launch-plugins.md#declare-a-claim-with-a-schema) shows.

A parser for a standard claim can't become a declared claim, because Ltix already declares it. Split it into a module for each property it parsed, an `Ltix.Claims.Check` for each rule it added, and an `Ltix.Claims.Override` for each check it replaced. See [Add a property to a claim](writing-claim-and-launch-plugins.md#add-a-property-to-a-claim), [Check a claim](writing-claim-and-launch-plugins.md#check-a-claim), and [Replace a check](writing-claim-and-launch-plugins.md#replace-a-check).

### `organization` and `actual_user` are parsed

Read them from `launch.claims.organization` and `launch.claims.actual_user`, where 0.2 had them in `claims.extensions`. They're `Ltix.Claims.Organization` and `Ltix.Claims.ActualUser` structs.

### A malformed `resource_link` or `deep_linking_settings` fails every launch

In 0.2, a malformed `resource_link` failed only resource link launches, and malformed `deep_linking_settings` only Deep Linking requests. Now either fails every launch. Your code doesn't change.

### A role-scope mentor launch requires the Mentor role

A launch with subject identifiers in `role_scope_mentor` fails with `Ltix.Errors.Invalid.InvalidClaim` unless `roles` has the Mentor context role or one of its sub-roles. To accept such launches from a platform, override `Ltix.Claims.RoleScopeMentor` in a message type. See [Replace a check](writing-claim-and-launch-plugins.md#replace-a-check). In tests, add the Mentor role.

```elixir
Ltix.Test.build_launch(platform,
  roles: [Ltix.Role.context_mentor()],
  claims: %{"https://purl.imsglobal.org/spec/lti/claim/role_scope_mentor" => ["user-2"]}
)
```

### `build_launch_context/2` is now `Ltix.Test.build_launch/2`

`build_launch/2` also runs claim checks and requires the message type's claims. It raises when a check fails or a required claim is missing. Pass `allow_anonymous: true` where you build a resource link launch with `subject: nil`.

### Member messages are claim maps

A member's `message` is a list of claim maps keyed by short name, where 0.2 had `%Ltix.LaunchClaims{}` structs. Read a claim with `message.custom`. Claims no plugin declares are left out, and a message that fails a claim check fails `list_members/2` and `stream_members/2`.

`Ltix.Test.stub_list_members/2` now sends members' messages. Build a member's `message` as a list of claim maps, such as `[%{custom: %{"course" => "1"}}]`.

## Services

### `Ltix.AdvantageService` is removed

A custom service is a plugin. Move `validate_endpoint/1` to your endpoint claim's `new/1`, and `scopes/1` to a client assertion step. Until an enabled plugin declares the endpoint claim, `Ltix.OAuth.authenticate/2` returns `Ltix.Errors.Invalid.ServiceNotAvailable` for the service.

```elixir
# 0.2
defmodule MyApp.AttendanceService do
  @behaviour Ltix.AdvantageService

  @impl true
  def validate_endpoint(%MyApp.AttendanceEndpoint{}), do: :ok
  def validate_endpoint(_), do: {:error, InvalidEndpoint.exception(service: __MODULE__)}

  @impl true
  def scopes(%MyApp.AttendanceEndpoint{}), do: ["https://lms.example.com/scope/attendance"]
end

# 0.3
defmodule MyApp.AttendanceEndpoint do
  use Ltix.Claim,
    claim: "https://lms.example.com/claim/attendance",
    name: :attendance_endpoint,
    strict: false,
    service: MyApp.AttendanceService,
    fields: [attendance_url: Zoi.string()]

  @impl Ltix.Claim
  def new(attributes), do: {:ok, struct!(__MODULE__, attributes)}
end

defmodule MyApp.AttendanceScope do
  use Ltix.ClientAssertion

  @impl Ltix.Step
  def call(%{endpoints: %{MyApp.AttendanceService => _endpoint}} = assertion, _opts) do
    {:ok, update_in(assertion.scopes, &(&1 ++ ["https://lms.example.com/scope/attendance"]))}
  end

  def call(assertion, _opts), do: {:ok, assertion}
end

defmodule MyApp.LtiPlugin do
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Ltix.Plugin.new(name: "My App")
    |> Ltix.Plugin.add(MyApp.AttendanceEndpoint)
    |> Ltix.Plugin.add(MyApp.AttendanceScope)
  end
end

# config/config.exs
config :ltix, plugins: [MyApp.LtiPlugin]
```

Your service module keeps its functions, and `Ltix.OAuth.Client.request/3` still sends its requests. If you keyed a token cache on `scopes(endpoint)`, key it on the service module, and authenticate with `require_all_scopes: true`. See [Building a Custom Advantage Service](cookbooks/custom-advantage-service.md) and [Token Caching and Reuse](cookbooks/token-caching-and-reuse.md).

### Ltix's services drop their `AdvantageService` callbacks

`Ltix.GradeService` and `Ltix.MembershipsService` no longer have `endpoint_from_claims/1`, `validate_endpoint/1`, or `scopes/1`. Read a launch's endpoint with `Ltix.Launch.get_endpoint/2`, and a grade service endpoint's scopes from its `scopes` field. Check a stored endpoint with its module's `new/1`, such as `Ltix.GradeService.Endpoint.new/1`.

## Grade and memberships services

### `extensions:` is replaced by property names

`create_line_item/3` raises `Ltix.Errors.Invalid.InvalidOption` for `extensions:`, and `Score.new/1` returns `Ltix.Errors.Invalid.InvalidField`. Enable a plugin that declares the property, then pass the property by its name.

```elixir
# 0.2
{:ok, item} =
  Ltix.GradeService.create_line_item(client,
    label: "Essay",
    score_maximum: 100,
    extensions: %{"https://canvas.instructure.com/lti/submission_type" => %{"type" => "none"}}
  )

# 0.3
# config/config.exs
config :ltix, plugins: [MyApp.Canvas]

{:ok, item} =
  Ltix.GradeService.create_line_item(client,
    label: "Essay",
    score_maximum: 100,
    canvas_submission_type: %{type: "none"}
  )
```

[Writing a Canvas Grade Plugin](cookbooks/canvas-grade-plugin.md) builds `MyApp.Canvas`.

### Undeclared properties are in `unrecognized`

In 0.2, line items, results, and members kept unparsed properties in `extensions`, under their JSON names. They're now in `unrecognized`, and `extensions` has the properties plugins declare, keyed by property name.

```elixir
# 0.2
member.extensions["https://lms.example.com/student_number"]

# 0.3
member.unrecognized["https://lms.example.com/student_number"]
```

To send a property without a plugin, set it in the line item's `unrecognized`, keyed by JSON name. Ltix sends it when it creates or updates the line item.

```elixir
# 0.2
Ltix.GradeService.create_line_item(client,
  label: "Essay",
  score_maximum: 100,
  extensions: %{"https://lms.example.com/rubric" => "rubric-7"}
)

# 0.3
item = %Ltix.GradeService.LineItem{
  label: "Essay",
  score_maximum: 100,
  unrecognized: %{"https://lms.example.com/rubric" => "rubric-7"}
}

Ltix.GradeService.create_line_item(client, item)
```

### `from_json/1`, `to_map/1`, and the JSON encoders are removed

Line items, scores, results, members, and membership containers lose these. Parse with `Ltix.Type.from_json/3` and serialize with `Ltix.Type.to_json/3`.

```elixir
# 0.2
{:ok, item} = Ltix.GradeService.LineItem.from_json(json)
json = Ltix.GradeService.LineItem.to_map(item)

# 0.3
{:ok, item} = Ltix.Type.from_json(Ltix.GradeService.LineItem, json)
json = Ltix.Type.to_json(item)
```

Encode line items and scores with `to_json/3` where you used `JSON` or `Jason`.

### Members default to active

A `%Ltix.MembershipsService.Member{}` you build has a `status` of `:active`, where 0.2 had `nil`.

## Roles

### Roles are URIs

`Ltix.LaunchClaims.Role` is now `Ltix.Role`, and `roles` on launches and members are the URIs the platform sent, in its order. They include the roles 0.2 left out and listed in `unrecognized_roles`. Role parsers are gone, and passing `:role_parsers` raises `Ltix.Errors.Invalid.InvalidOption`.

| 0.2 | 0.3 |
|---|---|
| `Ltix.LaunchClaims.Role` | `Ltix.Role` |
| `%Role{}` | the role's URI |
| `Role.from_atom(:instructor)` | `Role.context_instructor()` |
| `Role.from_atom(:learner)` | `Role.context_learner()` |
| `Role.from_atom(:content_developer)` | `Role.context_content_developer()` |
| `Role.from_atom(:mentor)` | `Role.context_mentor()` |
| `Role.from_atom(:context_administrator)` | `Role.context_administrator()` |
| `Role.from_atom(:teaching_assistant)` | `Role.instructor_teaching_assistant()` |
| `Role.from_atom(:administrator)` | `Role.institution_administrator()` |
| `Role.from_atom(:faculty)` | `Role.institution_faculty()` |
| `Role.from_atom(:student)` | `Role.institution_student()` |
| `Role.from_atom(:staff)` | `Role.institution_staff()` |
| `Role.from_atom(:test_user)` | `Role.system_test_user()` |
| `Role.has_role?/3`, `Role.has_role?/4` | `Role.has?/2` |
| `Role.parse/2`, `Role.parse_all/2`, `Role.to_uri/2`, `Role.to_uri!/2` | removed |
| `Role.context_roles/1`, `Role.institution_roles/1`, `Role.system_roles/1` | kept, taking and returning URIs |
| `Ltix.LaunchClaims.Role.LIS`, `Ltix.LaunchClaims.Role.Parser`, `:role_parsers` | removed |
| `unrecognized_roles` | removed |

The checks, such as `instructor?/1` and `learner?/1`, keep their names and take the list of URIs.

```elixir
# 0.2
alias Ltix.LaunchClaims.Role
Role.instructor?(context.claims.roles)
Role.has_role?(roles, :system, :test_user)
Role.has_role?(roles, :context, :instructor, :grader)

# 0.3
alias Ltix.Role
Role.instructor?(launch.claims.roles)
Role.has?(roles, Role.system_test_user())
Role.has?(roles, Role.instructor_grader())
```

`has?/2` matches one role in any of its forms, and doesn't match its sub-roles. Check a platform's own role by its URI, as in `Role.has?(roles, "https://lms.example.com/roles#CourseDesigner")`.

### Checks match deprecated forms and every sub-role

`administrator?/1` returns `true` for `person#Administrator`, which means both the institution and the system Administrator role. `instructor?/1`, `learner?/1`, `mentor?/1`, `content_developer?/1`, and `context_administrator?/1` return `true` for every sub-role of their role, including ones the LIS vocabulary doesn't list. If a user with `person#Administrator` must not count as an institution administrator, check for the URI itself.

```elixir
Role.institution_administrator() in roles
```

### Filters keep `person#Administrator`, `person#None`, and unlisted roles

0.2's `system_roles/1` kept the deprecated `person#Administrator` and `person#None` roles, and `institution_roles/1` didn't. Now both keep them.

Each filter also keeps every role under its URI prefix, even one the LTI specification doesn't list, such as `institution/person#Dean`. 0.2 put these in `unrecognized_roles`. `Ltix.Role` lists the URI prefixes each filter keeps.

To keep only the roles you name, including their deprecated forms, filter with `has?/2`.

```elixir
accepted = [Role.institution_faculty(), Role.institution_staff()]
Enum.filter(roles, fn role -> Enum.any?(accepted, &Role.has?([role], &1)) end)
```

### Role options take URIs

The `:role` filter of `list_members/2` and `stream_members/2`, and the `:roles` option of the test helpers, take URIs. Atoms and `%Role{}` structs raise `Ltix.Errors.Invalid.InvalidOption`.

```elixir
# 0.2
Ltix.MembershipsService.list_members(client, role: :learner)
Ltix.Test.build_launch_context(platform, roles: [:instructor, :teaching_assistant])

# 0.3
Ltix.MembershipsService.list_members(client, role: Ltix.Role.context_learner())
Ltix.Test.build_launch(platform,
  roles: [Ltix.Role.context_instructor(), Ltix.Role.instructor_teaching_assistant()]
)
```

## Deep Linking

### Content items must be content item types

`Ltix.DeepLinking.build_response/3` returns `Ltix.Errors.Invalid.InvalidContentItem` for a plain map or for your own struct. The `Ltix.DeepLinking.ContentItem` protocol is removed. Declare each custom type with `use Ltix.DeepLinking.ContentItemType`, and add it to a plugin.

```elixir
# 0.2
defmodule MyApp.ProctoredExam do
  defstruct [:url, :title, :duration_minutes]

  defimpl Ltix.DeepLinking.ContentItem do
    def to_map(exam) do
      %{
        "type" => "https://myapp.example.com/proctored_exam",
        "url" => exam.url,
        "title" => exam.title,
        "durationMinutes" => exam.duration_minutes
      }
    end
  end
end

exam = %MyApp.ProctoredExam{url: url, title: "Final Exam", duration_minutes: 90}

# 0.3
defmodule MyApp.ProctoredExam do
  use Ltix.DeepLinking.ContentItemType,
    type: "https://myapp.example.com/proctored_exam",
    fields: [
      url: Zoi.string(),
      title: title(),
      duration_minutes: Zoi.integer()
    ]
end

defmodule MyApp.LtiPlugin do
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Ltix.Plugin.new(name: "My App")
    |> Ltix.Plugin.add(MyApp.ProctoredExam)
  end
end

# config/config.exs
config :ltix, plugins: [MyApp.LtiPlugin]

exam = MyApp.ProctoredExam.new!(url: url, title: "Final Exam", duration_minutes: 90)
```

`use` imports shared fields such as `title()`, and fields are sent under their camelCase names. See [Building Content Items](cookbooks/building-content-items.md#custom-content-item-type).

### `extensions:` on content items is replaced by property names

A content item's `new/1` returns `Ltix.Errors.Invalid.InvalidField` for `extensions:`. Enable a plugin that declares the property, then pass the property by its name.

```elixir
# 0.2
LTIResourceLink.new(
  title: "Proctored Exam",
  extensions: %{"https://vendor.example.com/proctoring" => %{"required" => true}}
)

# 0.3
# config/config.exs
config :ltix, plugins: [MyApp.Proctoring]

LTIResourceLink.new(title: "Proctored Exam", proctoring: %{required: true})
```

[Add a property to a content item type](writing-deep-linking-plugins.md#add-a-property-to-a-content-item-type) shows how to declare one.

### `ContentItem.to_map/1` is removed

In tests, read the content items from the signed response with `Ltix.Test.verify_deep_linking_response/2`, under the `https://purl.imsglobal.org/spec/lti-dl/claim/content_items` claim.

### A resource link's line item is an `Ltix.DeepLinking.LineItem`

`link.line_item` is an `%Ltix.DeepLinking.LineItem{}` where 0.2 kept a map. Read its fields with dot access, such as `link.line_item.score_maximum`. Map patterns still match.

## Errors

### Some error messages changed

Update code that matches on error messages. Your tests show the new text.

- The messages of `Ltix.Errors.Security.AuthenticationFailed`, `Ltix.Errors.Security.KidNotFound`, `Ltix.Errors.Unknown.KeySetNotStarted`, and `Ltix.Errors.Invalid.CoupledLineItem` changed.
- An error about a claim a plugin declares refers to the claim by its short name, such as `session`, where a 0.2 claim parser's error used its URI.

### Errors don't include a spec reference

An error's message doesn't end with the section of the specification its check comes from, such as `[Sec §5.1.3 step 7]`, and errors don't have a `spec_ref` field. Update code that reads `spec_ref` or matches on error messages.

## New in 0.3

- [Plugins](writing-plugins.md) extend Ltix. A tool that enables none works as before. When enabled plugins conflict, a call returns `Ltix.Errors.Unknown.InvalidPluginSet`.
- Plugins declare message types. `Ltix.ResourceLinkRequest` and `Ltix.DeepLinkingRequest` require the same claims as in 0.2. The test helpers also take a message type string as `message_type:`.
- An OAuth client uses the plugins it was authenticated with. If your launches pass `plugins:` to `Ltix.handle_callback/3`, pass the same plugins to `authenticate/2` in background jobs.
- Plugins can add claims to Deep Linking responses. `%Ltix.DeepLinking.Response{}` has new fields beside `jwt` and `return_url`.
- `Ltix.Errors.Invalid.ContentItemsExceedLimit` has the `index` of the first content item over the limit.
