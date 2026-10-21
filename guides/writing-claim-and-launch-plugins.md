# Writing Claim and Launch Plugins

A plugin can declare the claims Ltix parses from a launch, and accept new message types. [Writing Plugins](writing-plugins.md) covers writing and enabling a plugin.

## Declare a claim

Declare a claim with its URI as `claim:` and its short name as `name:`. Ltix parses it into `launch.claims` under the short name.

Examples in this section build this plugin for a fictional proctoring service. Add `{:zoi, "~> 0.17"}` to your dependencies.

```elixir
defmodule Proctoring do
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Ltix.Plugin.new(name: "Proctoring", version: "1.0.0")
    |> Ltix.Claim.add(
      claim: "https://proctor.example.com/claim/mode",
      name: :proctoring_mode,
      schema: Zoi.enum(["live", "recorded"])
    )
    |> Ltix.Plugin.add(Proctoring.Session)
    |> Ltix.Plugin.add(Proctoring.Exam)
  end
end
```

### Declare a claim with a schema

`Ltix.Claim.add/2` declares a claim whose value needs only a Zoi schema, such as a string, number, boolean, or list. The claim has no module of its own, so it's an anonymous claim. A launch with `"live"` as the mode claim has it in `launch.claims.proctoring_mode`.

Without `schema:`, the claim's value is its JSON value.

### Declare an object claim

A claim whose value is a JSON object lists its fields as Zoi schemas. Add `{:zoi, "~> 0.17"}` to your dependencies.

```elixir
defmodule Proctoring.Session do
  @moduledoc "The proctoring session the launch belongs to."

  use Ltix.Claim,
    claim: "https://proctor.example.com/claim/session",
    name: :proctoring_session,
    fields: [
      id: Zoi.string(description: "The session's ID."),
      started_at: Zoi.integer(description: "When the session started.") |> Zoi.optional(),
      room:
        Zoi.string(description: "The exam room.", metadata: [json_key: "room_name"])
        |> Zoi.optional()
    ]
end
```

`Ltix.Plugin.add/2` adds the claim's module. A claim of `{"id": "s-1", "started_at": 1700000000, "room_name": "A"}` parses to this.

```elixir
launch.claims.proctoring_session
#=> %Proctoring.Session{id: "s-1", started_at: 1700000000, room: "A", extensions: %{}, unrecognized: %{}}
```

- A field without `Zoi.optional/1` is required.
- A malformed value for an optional field becomes `nil`.
- `json_key:` metadata sets a field's JSON name.
- Properties no field declares are in `unrecognized`, under their JSON names.
- The moduledoc gets a Fields section with each field's `description:`.

### Declare a claim that needs code

A claim module can implement `c:Ltix.Property.parse/2` to convert a value beyond what a Zoi schema does, such as to look up a record.

```elixir
defmodule Proctoring.Exam do
  use Ltix.Claim,
    claim: "https://proctor.example.com/claim/exam",
    name: :proctoring_exam

  @impl Ltix.Property
  def parse(value, _opts) do
    with {:ok, id} <- Zoi.parse(Zoi.string(), value), do: Proctoring.Exams.fetch(id)
  end
end
```

`parse/2` returns `{:ok, value}` or `{:error, reason}`, where the reason is a string, an exception, or Zoi's errors.

### Malformed and missing claims

A malformed claim fails the launch with `Ltix.Errors.Invalid.InvalidClaim`. A claim that lacks a required field fails the launch with `Ltix.Errors.Invalid.MissingClaim`.

When a claim is declared with `strict: false`, a malformed value is its `default:`, or `nil`, in `launch.claims`, and the launch continues.

A claim the platform didn't send, or sent as `null`, is its `default:`, or `nil`, in `launch.claims`. `launch.raw` has every claim's JSON value, including claims no plugin declares.

### Share a claim between plugins

Enabling two plugins that declare the same claim URI or short name makes calls return an [`InvalidPluginSet`](writing-plugins.md#fix-a-plugin-set-that-fails-to-resolve) error. To share a claim, have both plugins [depend on](writing-plugins.md#depend-on-another-plugin) one plugin that declares it.

## Declare a message type

Each message type, such as `LtiResourceLinkRequest`, requires its own claims. Declare one with a module that calls `use Ltix.Launch.MessageType` and lists the claims it requires in `c:Ltix.Launch.MessageType.validator/0`, with calls such as `required(:for_user)`.

This plugin declares Submission Review's message type and its `for_user` claim.

```elixir
defmodule Review.Request do
  @moduledoc "A user opens a submission for review."

  use Ltix.Launch.MessageType

  @impl Ltix.Launch.MessageType
  def validator do
    new("LtiSubmissionReviewRequest")
    |> required(:resource_link)
    |> required(:for_user)
    |> optional(:roles)
  end
end

defmodule Review.ForUser do
  use Ltix.Claim,
    claim: "https://purl.imsglobal.org/spec/lti/claim/for_user",
    name: :for_user,
    fields: [user_id: Zoi.string()]
end

defmodule Review do
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Ltix.Plugin.new(name: "Submission Review", version: "1.0.0")
    |> Ltix.Plugin.add(Review.Request)
    |> Ltix.Plugin.add(Review.ForUser)
  end
end
```

- `required/3` and `optional/3` refer to claims by short name. One of the plugins a launch runs with must declare each claim they refer to.
- Every launch also requires `version`, `deployment_id`, and `target_link_uri`.
- A launch missing a required claim fails with `Ltix.Errors.Invalid.MissingClaim`. A launch whose message type no plugin declares fails with `Ltix.Errors.Invalid.InvalidClaim`.
- `validator/0` must have one clause, and must not call functions defined in its own module.
- The module's documentation gets a "Claims" table of its requirements.

### Require a claim under a condition

`required/3` and `optional/3` take a condition as `when:` or `unless:`.

```elixir
new("LtiResourceLinkRequest")
|> required(:subject, unless: option(:allow_anonymous))

new("LtiDeepLinkingRequest")
|> required(:context, when: includes(:deep_linking_settings, :accept_types, "ltiAssetProcessor"))
```

`option/1` is met when an `Ltix.handle_callback/3` option is `true`. `includes/3` is met when a field of an object claim includes a value. For any other rule, write a module that implements `Ltix.Validator.Condition`, and pass it alone or as `{module, args}`.

```elixir
defmodule Review.Graded do
  @behaviour Ltix.Validator.Condition

  @impl Ltix.Validator.Condition
  def met?(_args, claims, _opts), do: claims.ags_endpoint != nil

  @impl Ltix.Validator.Condition
  def describe(_args), do: "the launch has a grade service endpoint"
end
```

```elixir
new("LtiSubmissionReviewRequest")
|> required(:context, when: Review.Graded)
```

The "Claims" table shows this requirement as "Required when the launch has a grade service endpoint".

## Change the claims a message type requires

A module that changes another plugin's message type `use`s the message type's module and implements `c:Ltix.Launch.MessageType.Requirements.validator/1`. A plugin adds it with `Ltix.Plugin.add/2`.

```elixir
defmodule Review.RequireContext do
  use Ltix.ResourceLinkRequest

  @impl Ltix.Launch.MessageType.Requirements
  def validator(validator), do: required(validator, :context)
end
```

To change several message types, `use` each and match on the message type.

```elixir
defmodule Review.Context do
  use Ltix.ResourceLinkRequest
  use Ltix.DeepLinkingRequest

  @impl Ltix.Launch.MessageType.Requirements
  def validator(%{message_type: "LtiResourceLinkRequest"} = validator),
    do: required(validator, :context)

  def validator(%{message_type: "LtiDeepLinkingRequest"} = validator),
    do: optional(validator, :context)
end
```

`use Ltix.Launch.EveryMessageType` changes every message type.

```elixir
defmodule Review.Baseline do
  use Ltix.Launch.EveryMessageType

  @impl Ltix.Launch.MessageType.Requirements
  def validator(validator),
    do: defaults(validator, required: [:context], optional: [:tool_platform])
end
```

`defaults/2` states several claims in one call, the same as `required/3` and `optional/3` without conditions.

### How requirements combine

Plugin order doesn't change which claims a launch requires. `Ltix.Validator` has the full rules.

- A claim is required when any `required/3` call for it applies.
- Only `override/3` makes a required claim optional.

```elixir
defmodule Review.OptionalRoles do
  use Ltix.ResourceLinkRequest

  @impl Ltix.Launch.MessageType.Requirements
  def validator(validator), do: override(validator, :roles, :optional)
end
```

To see what a message type requires, print it with `Ltix.Validator.describe/1`. For a launch that ran with only the default plugins, `LtiResourceLinkRequest` prints this table.

```elixir
%{message_types: validators} = Ltix.PluginSet.data(launch.plugins, Ltix.Launch.MessageType)
IO.puts(Ltix.Validator.describe(validators["LtiResourceLinkRequest"]))
```

```
| Claim | Requirement | Stated by |
|---|---|---|
| `resource_link` | Required | `Ltix.ResourceLinkRequest` |
| `roles` | Required | `Ltix.ResourceLinkRequest` |
| `subject` | Required unless the `:allow_anonymous` option is set | `Ltix.ResourceLinkRequest` |
| `version` | Required | `Ltix.Core.RequiredClaims` |
| `deployment_id` | Required | `Ltix.Core.RequiredClaims` |
| `target_link_uri` | Required | `Ltix.Core.RequiredClaims` |
```

## Test claims and launch steps

These tests use the setup from [Test a plugin](writing-plugins.md#test-a-plugin).

`Ltix.Test.build_launch/2` builds a launch without a login or a signed token. It parses your plugin's claims, runs your [launch steps](writing-plugins.md#add-a-step), and checks the claims the message type requires. It raises when the launch fails. `claims:` merges raw claims over the ones it builds.

```elixir
test "parses the proctoring session", %{platform: platform} do
  launch =
    Ltix.Test.build_launch(platform,
      claims: %{"https://proctor.example.com/claim/session" => %{"id" => "s-1"}},
      plugins: [Proctoring]
    )

  assert launch.claims.proctoring_session.id == "s-1"
end
```

For your own message type, pass its string as `message_type:`, with the claims it requires.

```elixir
launch =
  Ltix.Test.build_launch(platform,
    message_type: "LtiSubmissionReviewRequest",
    claims: %{
      "https://purl.imsglobal.org/spec/lti/claim/resource_link" => %{"id" => "link-1"},
      "https://purl.imsglobal.org/spec/lti/claim/for_user" => %{"user_id" => "user-2"}
    },
    plugins: [Review]
  )
```

## Next steps

- `Ltix.Claim`, `Ltix.Validator`, and `Ltix.Property` for the full contracts
- `Ltix.Launch` for the launch's fields and phases
- `Ltix.Core` for Core's claims and their short names
