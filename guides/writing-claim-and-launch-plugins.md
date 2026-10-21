# Writing Claim and Launch Plugins

A plugin can declare the claims Ltix parses from a launch. [Writing Plugins](writing-plugins.md) covers writing and enabling a plugin.

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

## Next steps

- `Ltix.Claim` and `Ltix.Property` for the full contracts
- `Ltix.Launch` for the launch's fields and phases
- `Ltix.Core` for Core's claims and their short names
