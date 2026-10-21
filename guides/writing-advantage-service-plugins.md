# Writing Advantage Service Plugins

A plugin can add an [Advantage service](advantage-services.md). It can also add properties to the line items, scores, and results of `Ltix.GradeService`, and to the members and membership containers of `Ltix.MembershipsService`. [Writing Plugins](writing-plugins.md) covers writing and enabling a plugin.

Examples on this page build this plugin for a fictional proctoring service.

```elixir
defmodule Proctoring do
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Ltix.Plugin.new(name: "Proctoring", version: "1.0.0")
    |> Ltix.Plugin.add(Proctoring.Endpoint)
    |> Ltix.Plugin.add(Proctoring.Scope)
    |> Ltix.Plugin.add(Proctoring.Integrity)
    |> Ltix.Plugin.add(Proctoring.ExtraTime)
  end
end
```

## Add an Advantage service

A service plugin has two modules, an endpoint claim and a client assertion step. [Building a Custom Advantage Service](cookbooks/custom-advantage-service.md) builds a complete one, with its requests and tests.

### Declare the endpoint claim

An endpoint claim is an [object claim](writing-claim-and-launch-plugins.md#declare-an-object-claim) with a `:service` option, and it implements one more callback. `:service` is your service's module, usually the one with your request functions. That module needs no callbacks. `Ltix.Launch.get_endpoint/2` returns a launch's parsed endpoint for that module. `c:Ltix.Claim.new/1` builds an endpoint from its fields and rejects one the service can't call.

```elixir
defmodule Proctoring.Endpoint do
  use Ltix.Claim,
    claim: "https://proctor.example.com/claim/endpoint",
    name: :proctoring_endpoint,
    strict: false,
    service: Proctoring.EventsService,
    fields: [events_url: Zoi.string()]

  @impl Ltix.Claim
  def new(attributes) do
    case attributes[:events_url] do
      "https://" <> _rest = url ->
        {:ok, %__MODULE__{events_url: url}}

      url ->
        {:error,
         Ltix.Errors.Invalid.InvalidField.exception(
           struct: __MODULE__,
           field: :events_url,
           value: url,
           reason: "must be an HTTPS URL"
         )}
    end
  end
end
```

`Ltix.OAuth.authenticate/2` checks every endpoint with `new/1` before it requests a token, including endpoints your application stored.

### Add the service's scope to token requests

A client assertion step adds the scopes a token request asks for, and any claims the platform requires in the client assertion.

```elixir
defmodule Proctoring.Scope do
  use Ltix.ClientAssertion

  @scope "https://proctor.example.com/scope/events"

  @impl Ltix.Step
  def call(%{endpoints: %{Proctoring.EventsService => _endpoint}} = assertion, _opts) do
    {:ok, update_in(assertion.scopes, &(&1 ++ [@scope]))}
  end

  def call(assertion, _opts), do: {:ok, assertion}
end
```

- `endpoints` has the endpoints the token is for, keyed by service, before any step runs.
- `scopes` and `claims` start empty. Ltix requests a scope once, however many steps add it.
- Ltix adds the claims every client assertion requires, such as `iss` and `aud`, after the steps run. They replace a step's claims with the same names.

Token refreshes run the same steps and request the same scopes.

## Add a property to line items, scores, or results

Add a property to `Ltix.GradeService.LineItem`, `Ltix.GradeService.Score`, or `Ltix.GradeService.Result` with the type's `add_property/2`.

```elixir
def plugin(_opts) do
  Ltix.Plugin.new(name: "Proctoring", version: "1.0.0")
  |> Ltix.GradeService.LineItem.add_property(
    property: "https://proctor.example.com/integrity",
    name: :proctoring_integrity,
    schema: Zoi.map(%{level: Zoi.string()}, coerce: true),
    writes: [:create]
  )
end
```

- `property:` is the property's JSON name.
- `name:` is the property's name in the application's code.
- `schema:` parses the JSON value into the value an application reads. With `coerce: true`, `Zoi.map/2` converts the JSON's string keys to atoms. A value that doesn't match makes the call that read the property return an error. Without `schema:`, the value is the JSON value.
- `writes:` lists the write operations that send the property. `create_line_item/3` and `post_score/3` are `:create` operations, and `update_line_item/3` is `:update`. For a property the platform accepts only on a new line item, pass `[:create]`, and for a read-only property, `[]`. It defaults to `[:create, :update]`.

Only `property:` and `name:` are required. An application passes the value by name and reads it from `extensions`.

```elixir
{:ok, item} =
  Ltix.GradeService.create_line_item(client,
    label: "Final exam",
    score_maximum: 100,
    proctoring_integrity: %{level: "high"}
  )

item.extensions.proctoring_integrity
#=> %{level: "high"}
```

A property whose value needs code to convert, beyond a Zoi schema, is a module that `use`s the type's module with the same options and implements `c:Ltix.Property.parse/2` or `c:Ltix.Property.serialize/2`. [Writing a Canvas Grade Plugin](cookbooks/canvas-grade-plugin.md) builds a complete property plugin with both kinds.

## Add a property to members or membership containers

Plugins add properties to `Ltix.MembershipsService.Member` and `Ltix.MembershipsService.MembershipContainer` the same way as to line items.

```elixir
|> Ltix.MembershipsService.Member.add_property(
  property: "https://proctor.example.com/extra_time",
  name: :proctoring_extra_time,
  schema: Zoi.integer()
)
```

```elixir
member.extensions.proctoring_extra_time
#=> 30
```

Ltix doesn't send members to platforms. A member property module needs `serialize/2` only for `Ltix.Test.stub_list_members/2`.

A membership container's `context` is an `Ltix.Claims.Context`. To add a property to it, [add a property to the claim](writing-claim-and-launch-plugins.md#add-a-property-to-a-claim).

## Test properties on service types

This test uses the setup from [Test a plugin](writing-plugins.md#test-a-plugin).

The service stubs in `Ltix.Test` serialize properties with the configured plugins. When your test passes `plugins:` to `Ltix.Test.build_launch/2`, pass the same `plugins:` to the stub.

```elixir
test "reads the integrity level", %{platform: platform} do
  url = "https://platform.example.com/lineitems/1"
  scope = "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem.readonly"
  Ltix.Test.stub_token_response(scopes: [scope])

  launch =
    Ltix.Test.build_launch(platform,
      ags_endpoint: %{line_item: url, scopes: [scope]},
      plugins: [Proctoring]
    )

  {:ok, client} = Ltix.GradeService.authenticate(launch)

  item = %Ltix.GradeService.LineItem{
    id: url,
    extensions: %{proctoring_integrity: %{level: "high"}}
  }

  Ltix.Test.stub_get_line_item(item, plugins: [Proctoring])

  assert {:ok, item} = Ltix.GradeService.get_line_item(client, line_item: url)
  assert item.extensions.proctoring_integrity == %{level: "high"}
end
```

## Next steps

- `Ltix.Property` and `Ltix.ClientAssertion` for the full contracts
