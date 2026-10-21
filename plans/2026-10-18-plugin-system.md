# Plugin System Specification

## Overview

Ltix becomes a plugin system. A plugin is a module that declares what it provides and what it extends. Ltix's own functionality ships as bundled plugins that go through the same mechanism as third-party plugins.

LTI Advantage keeps growing. Submission Review, Proctoring, Dynamic Registration, and Platform Notification Service add message types, claims, scopes, and properties, and vendors add their own. This document follows one example, a library that adds Submission Review. It needs five things.

This document describes the system as it should be. It is not an implementation plan.

### Scope

In scope is everything a library contributes to Ltix, such as a new LTI specification, a vendor's additions, or a new message type.

Out of scope is everything an application does to integrate Ltix. This covers the storage adapter, `Ltix.Registerable` and `Ltix.Deployable`, global configuration such as `:max_token_age`, and telemetry.

## Terms

| Term | Meaning |
|---|---|
| Plugin | A module that implements `Ltix.Plugin` and returns a `%Ltix.Plugin{}` |
| Plugin set | The plugins in effect for one call into Ltix |
| Document | The state of one call into Ltix. Plugins' steps run over it in order, any step can halt it, and the caller gets it back |
| Provider | A module that a plugin provides. It defines a document or type and the contract its extenders implement |
| Hook | The behaviours a provider requires of its extenders |
| Extender | A module that implements one or more providers' hooks |
| Building block | A behaviour shared across providers' hooks, such as `Ltix.Step` and `Ltix.Ordered` |

## Plugins

- **Provides.** A provider defines a document or a type. Its hook is the behaviours its extenders implement.
- **Extends.** An extender implements one or more providers' hooks.
- **Depends on.** A dependency is another plugin that resolution adds before this one.

```elixir
defmodule Lti1p4 do
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Ltix.Plugin.new(name: "LTI 1.4", version: "1.0")
    |> Ltix.Plugin.depend_on(Lti1p3p1)
    |> Ltix.Plugin.extend(Lti1p4.Launch)
    |> Ltix.Plugin.provide(Lti1p4.MCP)
  end
end
```

- `Ltix.Plugin.new/1` takes `name:` and `version:`. They describe the plugin in error messages.
- `Ltix.Plugin.provide/2` takes the plugin struct and a provider module.
- `Ltix.Plugin.extend/2` takes the plugin struct and an extender as `Module` or `{Module, opts}`. The targets come from the providers the module `use`s, so the plugin never names them. The plugin can build the extender's options from its own, as in `extend(plugin, {AshLti.Claims, resource: opts[:resource]})`.
- `Ltix.Plugin.depend_on/2` takes the plugin struct and another plugin module. A profile is a plugin whose manifest is only `depend_on/2` calls.
- The builders raise `ArgumentError` for a module that isn't a provider, an extender, or a plugin, as each expects.
- A plugin is listed as `Module` or `{Module, opts}`. The options are passed to the callback, so a plugin's manifest can depend on them. A plugin that needs several configurations takes a list in its options and adds one extender entry for each.
- Each listing adds its own extender entries, and each entry runs with its own options. The providers in a plugin set are a set of modules, so a plugin listed twice provides each module once.

The manifest is readable without running any document. Ltix reads it to collect a plugin set's providers and extenders. Providers read it for data that applies outside a call, such as the message types and scopes in a Dynamic Registration request, the notice types for PNS handler registration, and the content item types checked against `accept_types`.

## Registration

- Ltix's default plugins always load. No option removes them. `Ltix.DefaultPlugins` depends on each one and comes first in plugin order, before configured and call-site plugins. Listing a default plugin gives it options without moving it.
- `config :ltix, plugins: [...]` sets the plugins for every call.
- `plugins:` at a call replaces the configured list.
- When a call is given a `%Ltix.Launch{}`, `plugins:` defaults to the launch's `plugins` field. Passing `plugins:` replaces it.
- An `%Ltix.OAuth.Client{}` keeps the plugin set it was authenticated with in its `plugins` field. Its refreshes run with it, and calls given the client, such as `Ltix.MembershipsService.list_members/2`, default `plugins:` to it.
- A call without a launch, such as a background job using stored endpoints, uses its `plugins:` option, or the configured list when the option is absent.
- A listing that includes a module that isn't a plugin raises `Ltix.Errors.Invalid.InvalidOption` for `:plugins`.

## Resolution

`Ltix.PluginSet.resolve/1` builds a plugin set from a listing, resolves the configured listing for `nil`, and returns a plugin set it is given, such as a launch's.

- **Dependencies.** Resolution walks dependencies depth first. Each plugin module appears once in plugin order, at the position where the listing first includes it or where the first plugin that depends on it is placed, and its dependencies come before it. A plugin gets a manifest for each time the listing includes it, each built with that listing's options, and an unlisted dependency gets `[]`. Options come only from the application's listing.
- **Extender entries.** Each manifest adds its extender entries. `init/1` runs once for each entry that implements `Ltix.Step` and extends a provider in the set.
- **Providers.** The providers of all manifests form a set of modules, in plugin order.
- **Order.** Each provider's extender entries are kept in plugin order, and sorted by `Ltix.Ordered` when the provider's hook includes it. `Ltix.PluginSet.extenders/2` returns them.
- **Resolution hook.** A provider may define the optional `resolve/1` callback from `Ltix.Provider`. It runs once per plugin set, in plugin order, and returns `{:ok, data}`, which `Ltix.PluginSet.data/2` returns, or `{:error, conflicts}`. Each provider's `resolve/1` can read the data of the providers before it.
- **Conflicts.** A conflict is an `%Ltix.PluginSet.Conflict{}` with the `parties` in conflict and a `reason`. Dependency cycles are conflicts whose parties are the plugins in the cycle, and a plugin that depends on itself is one. Resolution returns `{:error, %Ltix.Errors.Unknown.InvalidPluginSet{}}` with every conflict, and its message lists each party with the name and version of each plugin that includes it. `Ltix.PluginSet.Conflict.duplicates/3` returns a conflict for each value that several modules declare.
- **Caching.** Resolved plugin sets, and resolution errors, are kept in `:persistent_term`, keyed by the normalized listing, so a listing is resolved once.

## Documents

A document is the state of one call into Ltix that several specifications or vendors add to. Plugins' steps run over it in order, any step can halt it, and the caller gets it back.

| Document | Created by | Notes |
|---|---|---|
| Login | Login initiation | Platform storage adds parameters and keeps state in the platform's frame |
| Launch | The authentication response | `%Ltix.Launch{}` |
| Notice | Each notice in a PNS envelope | One document per notice. The envelope is not a document. A notice is not a launch |
| Tool message | Building a tool-signed message | The Deep Linking response and Proctoring Start Assessment |
| Service resource | One service request or response body | Line items, scores, results, ACS requests, and Dynamic Registration payloads. Each specification defines its resource types the way it defines message types |
| Client assertion | Requesting an access token | Specifications and vendors add claims and scopes |

Browser postMessages are not documents, because nothing in the browser calls into Ltix.

Login and launch are separate HTTP requests. Data from login is available to the launch the same way as in 0.2. Login returns `state`, the application stores it in its session and passes it to the callback, and the launch checks it and the nonce derived from it and the registration.

The bundled plugins provide these documents. A plugin can provide a new one, such as `Lti1p4.MCP`, which other plugins can then extend.

### `%Ltix.Login{}`

`Ltix.handle_login/3` resolves the plugin set, builds the login, runs its steps with `Ltix.Step.run/1`, and returns `{:ok, %{redirect_uri: url, state: state}}` or `{:error, exception}` as in 0.2. Its hook is `[Ltix.Step, Ltix.Ordered]`.

| Field | Contents |
|---|---|
| `params` | The login request's parameters |
| `private` | Library data, with keys prefixed by the library's name. Ltix's keys have the call's inputs, the registration and source registration, the state, and the authentication request URL |
| `errors` | Errors collected by steps |
| `plugins` | The plugin set the login runs with |

Its default steps check the parameters and look up the registration before the phase `Ltix.Login.RegistrationFound`, and build the authentication request after it. A phase is a step that changes nothing. Plugins order their steps against phases, and the other default steps are internal.

### `%Ltix.Launch{}`

`%Ltix.Launch{}` replaces both `LaunchContext` and `LaunchClaims`. It follows `%Plug.Conn{}`.

| Field | Contents |
|---|---|
| `registration` | The registration the launch was verified against |
| `deployment` | The deployment the launch belongs to |
| `source_registration` | The application's own record that `registration` was built from |
| `source_deployment` | The application's own record that `deployment` was built from |
| `claims` | Parsed claims, keyed by short name. This field has the role Plug gives `assigns` |
| `raw` | The claims as received, including claims no plugin declares |
| `endpoints` | The endpoint of each service the platform grants, keyed by service module |
| `private` | Library data, with keys prefixed by the library's name |
| `errors` | Errors collected by steps |
| `plugins` | The plugin set the launch ran with |

`Ltix.handle_callback/3` resolves the plugin set, builds the launch, runs its steps with `Ltix.Step.run/1`, and returns `{:ok, launch}` or `{:error, exception}` as in 0.2. Its hook is `[Ltix.Step, Ltix.Ordered]`.

The Core plugin provides `Ltix.Launch` and extends it with its default steps and four phases, in this order. Plugins order their steps against the phases. Each default step declares its place against the phases with `before?/1` and `after?/1`.

1. Steps check the authentication response and its state, look up the registration, and verify the ID token and its nonce. Verifying the ID token writes `raw`.
2. `Ltix.Launch.Verified`. The message is authentic and comes from a known registration.
3. `Ltix.Launch.ClaimsReceived`. A plugin step ordered after `Ltix.Launch.Verified` and before this phase can rewrite `raw` or write claims of its own.
4. A step runs `Ltix.Claims`, writes `claims` and `endpoints`, and runs the claims' checks.
5. `Ltix.Launch.ClaimsParsed`.
6. Steps check that a plugin declares the message type and that the launch has the claims its validator requires (see Message Types).
7. `Ltix.Launch.Validated`.
8. A step looks up the deployment.

A security check that fails halts the launch, so no claim is parsed from a message Ltix hasn't verified. A step ordered after `Ltix.Launch.Verified` and before `Ltix.Launch.ClaimsReceived` can change `raw` and write `claims`, which parsing merges the parsed claims into, and a step ordered after `Ltix.Launch.ClaimsParsed` reads the parsed claims. Claim parsing records the errors of malformed claims and of failed checks, combined into one error, and the launch continues, so they are reported with the claims the message type is missing. A malformed claim that isn't lenient counts as present when the required claims are checked, so it is reported once. The deployment lookup looks up nothing for a launch with errors, so the storage adapter only sees the deployment ID of a launch whose claims pass, as in 0.2. `Ltix.Test.build_launch/2` runs the launch's steps with `Ltix.Step.run/2`, leaving out the security checks before `Ltix.Launch.Verified` and the deployment lookup.

### `%Ltix.ClientAssertion{}`

`Ltix.OAuth.authenticate/2` and `Ltix.OAuth.Client.refresh/1` run the client assertion's steps with `Ltix.Step.run/2` before Ltix signs the client assertion. `Ltix.Core` provides it. Its hook is `[Ltix.Step, Ltix.Ordered]`.

| Field | Contents |
|---|---|
| `endpoints` | The endpoints of the services the token is for, keyed by service module |
| `scopes` | The scopes to request |
| `claims` | The claims steps add to the client assertion |
| `errors` | Errors collected by steps |

Steps only add scopes and claims.

- **Endpoints.** `authenticate/2` takes `services:` with a launch and reads their endpoints from `launch.endpoints`, or takes stored endpoints as `endpoints:` in the registration form. It reports services missing from the launch with `ServiceNotAvailable` before running the document, so nothing is signed. Each endpoint is checked with the `c:Ltix.Claim.new/1` of the claim that declares its service's endpoint, and an endpoint for a service no claim declares is `ServiceNotAvailable`.
- **Order.** The document starts with only the requested endpoints, so every step sees them and none needs `after?/1`. When services resolved endpoints in their own steps, an unordered vendor step lost its scope on the first access token but not on refreshes.
- **Signing.** After the steps run, Ltix adds the claims the client assertion requires, which replace a step's claims of the same name, signs the claims through the storage adapter, and requests the deduplicated scopes. A document with errors is not signed, and the call returns the errors combined.
- **OAuth clients.** The client keeps the plugin set and the endpoints. `force_refresh/1` rebuilds the document with them, so the first access token, a refresh, and the registration form request the same scopes and send the same claims. `require_all_scopes` checks the document's scopes against the granted ones.

The NRPS plugin's `Ltix.MembershipsService.AddScope` adds the NRPS scope when its endpoint is present, and the AGS plugin's `Ltix.GradeService.AddScopes` adds the endpoint claim's `scope` array.

## Providers

A provider is a module that writes `use Ltix.Provider`. It contains three things.

1. **The document or type it defines**, such as the `%Ltix.Launch{}` struct.
2. **Its hook**, the contract its extenders implement.
3. **Its entry point and its own steps.** The entry point is the function an application calls. It builds the document, runs the provider's steps and its extenders in order, and returns the document.

```elixir
defmodule Ltix.Launch do
  use Ltix.Provider, hook: [Ltix.Step, Ltix.Ordered]
  defstruct [...]
end

defmodule Ltix.GradeService.LineItem do
  use Ltix.Provider, hook: [Ltix.Property]
  use Ltix.Type, json_keys: :camel_case, fields: [...]
end
```

Each provider is entirely responsible for defining the semantics of its document. That includes which plugin set a child document uses, whether the provider creates the child during a call, such as each line item in a page of results, or the application builds it and passes it in, such as content items given to a Deep Linking response.

- `hook:` lists the building blocks the provider requires.
- An extender's `use` options are passed to each building block in the hook, as in `use Ltix.Claim, claim: "...", name: :tenant`.
- A provider that defines its own `@callback`s has them added to its hook automatically.
- A provider may define `resolve/1` to build per-set data and report conflicts (see Resolution).
- Each provider defines what extending it means. `Ltix.GradeService.LineItem` decides what happens when two extenders add the same property.
- A provider decides how finely it can be extended by choosing which modules it provides. Submission Review can add `submissionReview` to the AGS line item because the AGS plugin provides `Ltix.GradeService.LineItem`. The line item inside a Deep Linking `ltiResourceLink` is a separate definition with fewer fields, so it is extended through its own provider module.

## Extenders

An extender `use`s each provider it extends. `use` adds the provider's hook to the module and records the provider as a target.

```elixir
defmodule AddTenant do
  use Ltix.Login
  use Ltix.Launch

  def init(opts), do: Keyword.fetch!(opts, :tenant)

  def call(%Ltix.Login{} = login, tenant), do: ...
  def call(%Ltix.Launch{} = launch, tenant), do: ...

  def after?(VerifyToken), do: true
  def after?(_), do: false
end
```

- **One module, several documents.** A module can extend several providers, as `AddTenant` extends login and launch. Providers whose hooks share `Ltix.Step` get one `call/2` with a clause for each document.
- **Building blocks are declared once.** A module that uses two ordered hooks declares `Ltix.Ordered` once and gets one set of defaults.
- **Absent providers.** Extending a provider that no plugin in the call's plugin set provides does nothing. A plugin can extend a provider whether or not the application lists the plugin that provides it. When a provider is absent, none of its documents are built, so its extenders have nothing to do. The same holds for `after?/1` and `before?/1` naming a module that is not running. A plugin that needs a provider depends on the plugin that provides it with `depend_on/2`.
- **Conflicting callbacks.** If two providers define their own callbacks with the same name, a module that extends both gets Elixir's "conflicting behaviours" warning. That module is split into one module per provider. A contract that several providers share belongs in a building block.

## Building Blocks

Building blocks are public, so third-party providers build their hooks from the same pieces as bundled providers.

### `Ltix.Step`

```elixir
@callback init(opts :: term()) :: term()
@callback call(document :: struct(), opts :: term()) ::
            {:ok, struct()} | {:error, Exception.t()} | {:halt, Exception.t()}
```

Options work as they do in Plug. `init/1` runs once for each extender entry when a plugin set that provides the step's document is resolved, and its result is the `opts` passed to every `call/2`. The default `init/1` returns its options unchanged.

A step takes a document and returns one of three results. It is the contract for providers that run extenders as steps over a document, such as login and launch.

- `{:ok, document}` passes the updated document to the next step.
- `{:error, error}` adds the error to the document's `errors` and runs the next step.
- `{:halt, error}` adds the error to the document's `errors` and runs no further steps.

`Ltix.Step.run/1` runs a document's steps from its plugin set. `Ltix.Step.run/2` runs the extender entries it's given, such as part of a document's steps.

### `Ltix.Ordered`

```elixir
@callback before?(module()) :: boolean()
@callback after?(module()) :: boolean()
```

Both default to `false`. Only providers whose extenders run in order include `Ltix.Ordered` in their hook. A content item type's extenders add properties and have no order, so its provider leaves it out.

Ordering works the way Spark sorts transformers.

- An edge goes from one module to another when either declares it with `before?/1` or `after?/1`.
- When both directions are declared for a pair, there is no edge.
- Each extender entry is sorted on its own, so a module listed twice runs twice. Entries in one cycle run in plugin order. Every edge between entries that do not share a cycle still holds.

A module can only be ordered relative to another module, so each phase is its own module. `before?/1` and `after?/1` name modules as atoms, so renaming a phase is a breaking change for plugins that order against it. The other default steps are internal, so they can be renamed, split, or reordered within their phases.

### `Ltix.Property`

```elixir
@callback property() :: String.t()
@callback parse(json :: term(), opts :: term()) :: {:ok, term()} | {:error, term()}
@callback serialize(value :: term(), opts :: term()) :: term()
@callback writes() :: [:create | :update]
```

A property extender declares one JSON property, parses it, and serializes it. `parse/2` and `serialize/2` default to returning their value, and `writes/0` defaults to `[:create, :update]`. `parse/2` receives the options of the extender entry and returns `{:error, reason}` for a value it can't parse, where the reason is a message, an exception, or the errors `Zoi.parse/2` returns.

`Ltix.Property.conflicts/2` returns a conflict for each property that several of a provider's extenders declare, and `Ltix.Property.resolve/2` returns them as a `resolve/1` result. A provider whose hook includes `Ltix.Property` calls one of them from its `resolve/1`.

### `Ltix.Type`

`use Ltix.Type, fields: [...]` builds a type's struct from Zoi schemas for its standard fields, given as a keyword list in field order. It defines the struct, a typed `t`, and the enforced keys, and adds `extensions` and `unrecognized` as struct fields outside the Zoi schema, so options and generated docs leave them out. `metadata:` is passed to the struct's Zoi schema.

- `Ltix.Type.new/3` builds the struct from a keyword list or map. Nested keyword lists become maps, a field given `nil` counts as omitted, and missing required fields, unknown fields (`extensions:` among them), and invalid values are `InvalidField` errors.
- `Ltix.Type.from_json/3` parses JSON into the struct. A missing field with `Zoi.optional/1` or `Zoi.default/2` keeps its default, and so does a malformed one unless its metadata has `lenient: false`. A missing or malformed required field is an error. The property of each of the type's extenders in the plugin set, from `plugins:` or the configured plugins, is parsed with the extender's `parse/2` into `extensions`, and every `{:error, reason}` is reported with the other errors. Properties no field or extender declares go in `unrecognized`.
- `Ltix.Type.to_json/3` serializes the struct with a plugin set and a write operation. Unrecognized properties go in first, then standard fields, then the property of each extender entry that has an extension and whose `writes/0` includes the operation, so standard fields replace unrecognized properties of the same name, and declared properties replace both. The `:read` operation includes every property, as a platform sends the type, which `Ltix.Test`'s stubs use. It leaves out `nil` standard fields and `nil` values inside them, and sends a `DateTime` in ISO 8601.
- A field's JSON name is its name, or its camelCase form with `json_keys: :camel_case`, or `json_key:` from the field schema's metadata. Inside a field, the keys a nested map's schema declares follow the same style and take `json_key:` too. Keys the schema doesn't declare, such as custom property names, are sent as written.
- A field schema checks the field's value in the struct, so `new/3` takes Elixir values. `from_json:` in a field schema's metadata turns the JSON value into one, as `{:ok, value}` or `{:error, reason}`, before `from_json/3` parses it with the schema, and `to_json:` turns the value into its JSON. A line item's date times use both, and are sent in UTC. A score's `activityProgress` and timestamps use `to_json:`. A `from_json:` function of two arguments also takes `from_json/3`'s options, so a field can parse a nested value with the plugin set, as a membership container's members and a member's messages do.
- `lenient: false` in the metadata of a field with `Zoi.optional/1` or `Zoi.default/2` makes a malformed value an error. A `to_json:` function of two arguments also takes the plugin set, so a member's messages are serialized with `Ltix.Claims.serialize/2`.
- An extender declares its property name with `name:` on its `use`. A type's `extensions` are keyed by property name, and `Ltix.Type.new/3` takes property values by name with the type's fields.
- `Ltix.Type.fields/1` returns the field schemas in field order.

Object claims, content item types, the grade service's line items, scores, and results, and the memberships service's members and membership containers build their structs with it.

## Grade Service Types

The AGS plugin, `Ltix.GradeService`, provides itself, `Ltix.GradeService.LineItem`, `Ltix.GradeService.Score`, and `Ltix.GradeService.Result`, and extends its endpoint claim and its `Ltix.GradeService.AddScopes` client assertion step. Each of the three types is a provider with hook `[Ltix.Property]` whose struct `Ltix.Type` builds with `json_keys: :camel_case`, and each reports two extenders declaring one property or one name with `Ltix.Property.resolve/2` as its `resolve/1`.

```elixir
defmodule Canvas.SubmissionType do
  use Ltix.GradeService.LineItem, name: :canvas_submission_type

  @impl Ltix.Property
  def property, do: "https://canvas.instructure.com/lti/submission_type"

  @impl Ltix.Property
  def writes, do: [:create]
end
```

- **Plugin sets.** Every grade service call that parses or serializes resolves `plugins:`, or the OAuth client's plugin set when it's absent, and parses and serializes with it. `delete_line_item/2` takes no `plugins:`.
- **Write operations.** `create_line_item/3` serializes with `:create` and `update_line_item/3` with `:update`, so a property whose `writes/0` excludes the operation is left out. `post_score/3` serializes with `:create`. Reads parse every declared property.
- **Unrecognized properties.** A line item read from the platform keeps the properties no extender declares in `unrecognized`, and an update sends them back unchanged.
- **Creating with properties.** `create_line_item/3` takes a `%Ltix.GradeService.LineItem{}`, or the line item's fields and property names as options. `Ltix.GradeService.Score.new/1` takes property names with the score's fields.
- **Errors.** A property whose `parse/2` fails fails the call, with an error about `line_item.<property>` or `result.<property>`.

## Memberships Service Types

The NRPS plugin, `Ltix.MembershipsService`, provides itself, `Ltix.MembershipsService.Member`, and `Ltix.MembershipsService.MembershipContainer`, and extends its endpoint claim and its `Ltix.MembershipsService.AddScope` client assertion step. Both types are providers with hook `[Ltix.Property]` whose structs `Ltix.Type` builds, and each reports two extenders declaring one property with `Ltix.Property.resolve/2` as its `resolve/1`.

- **Plugin sets.** `list_members/2` and `stream_members/2` resolve `plugins:`, or the OAuth client's plugin set when it's absent, and parse each membership container with `Ltix.Type.from_json/3` and that plugin set. A body that isn't an object with a `members` array is `MalformedResponse`.
- **Members.** Each of a container's `members` is parsed with `Ltix.Type.from_json/3` and the plugin set, and its messages are then checked. The first member that fails fails the call. A member that isn't an object is a missing `user_id` and `roles`.
- **Context.** A container's `context` is parsed with `Ltix.Type.from_json/3` and the plugin set, so it has the properties plugins declare on `Ltix.Claims.Context`.
- **Messages.** Each of a member's messages is parsed with `Ltix.Claims.parse/2` and the plugin set, and fails the call when a claim that isn't lenient is malformed. Each then runs `Ltix.Claims.check/3` with its `message_type`, and no validator. A message without `roles` is checked with the member's roles, because the platform sends a member's roles on the member, and the member's launches would include them.
- **Errors.** A property whose `parse/2` fails fails the call, with an error about `member.<property>` or `membership.<property>`.

## Declared Claims

A single extender declares and parses each claim. `Ltix.Claim` is a provider whose hook is `[Ltix.Property, Ltix.Claim.Declaration]`, so a declared claim is an `Ltix.Property` whose `property/0` is the claim's URI.

```elixir
defmodule Ltix.Claims.LaunchPresentation do
  use Ltix.Claim,
    claim: "https://purl.imsglobal.org/spec/lti/claim/for_user",
    name: :for_user,
    fields: [user_id: Zoi.string()]
end
```

- **One declaring module.** Each claim URI, short name, and service has one declaring module. To change a standard claim, a plugin adds a property, a check, or an override, and the rest of the claim keeps Ltix's behavior. Plugins share a claim through a common dependency.
- **Declared claims are providers.** A claim with `fields:` takes properties, so a plugin can add a `launch_presentation` property from a later Core revision without touching the rest of the claim. A scalar claim's hook is empty.
- **Every declared claim is a key.** `claims` has a key for each claim the plugin set declares, `nil` when the message doesn't have it, or `[]` for `roles`. 0.2's `%Ltix.LaunchClaims{}` worked the same way. Code reads claims with dot syntax. A required claim that's `nil`, or `[]` for `roles`, is missing unless the platform sent it and the claim has `strict: true`, so a platform's `roles: []` counts as present.
- **The `strict` option.** A malformed claim fails the launch by default. When a claim is declared with `strict: false`, a malformed value is `nil` in `claims` and the launch continues. Claims Core doesn't require in any message are declared with `strict: false`, because a platform's mistake in a claim the tool may not read shouldn't block the launch. `azp` uses the default, because token verification checks it, and so does `custom`.
- **Endpoint claims.** A claim with `service/0` also fills `endpoints`.

`Ltix.Claims` collects every declared claim once per plugin set and reports conflicts at resolution.

OIDC claims keep 0.2's spelled-out short names, such as `:subject`, so 0.2 code that reads them still works. LTI claims use their URI's last segment, such as `:for_user`. Errors name a claim by its registered JWT name, such as `sub`, when it has one.

### Checks and overrides

A check is a rule about a parsed claim's value. Checks run after every claim is parsed, and only on claims present, so a check that reads another claim needs no ordering.

- **A claim's own check** is its declaring module's `check/2`.
- **Added checks** come from `Ltix.Claims.Check`, in listed message types or all of them.
- **Overrides** from `Ltix.Claims.Override` replace one check within listed message types.

Overrides are scoped to message types, because a check one message type doesn't need still protects every other launch. A plugin whose message type accepts `role_scope_mentor` without the Mentor role replaces Core's check there, and resource link launches keep it. `Ltix.Claims.overrides/1` lists every replaced check.

## Message types

A message type's module calls `use Ltix.Launch.MessageType` and returns an `Ltix.Validator`.

```elixir
defmodule Review.Request do
  use Ltix.Launch.MessageType

  @impl Ltix.Launch.MessageType
  def validator do
    new("LtiSubmissionReviewRequest")
    |> required(:resource_link)
    |> required(:for_user)
    |> optional(:roles)
  end
end
```

A validator is a list of statements, each one plugin's requirement for one claim. A statement can have a condition, such as `option(:allow_anonymous)`. `optional/3` records that the message type accepts a claim, which lists the claim in the module's "Claims" table. Other plugins add statements with contributions. A contribution extends the message type's module, or `Ltix.Launch.EveryMessageType`.

Statements combine all at once, so plugin order doesn't matter.

- Any applicable statement or default that requires a claim makes it required. `optional/3` can't weaken another plugin's requirement by accident.
- `override/3` makes a required claim optional. Two overrides of one claim in one message type conflict. That way one module is always responsible for a weakened requirement.
- `defaults/2` sets a baseline that statements can only tighten. `Ltix.Core.RequiredClaims` requires `version`, `deployment_id`, and `target_link_uri` this way.

Conditions are data, which lets `Ltix.Validator.describe/1` write each statement as a sentence for that table.

`use` evaluates `validator/0` while the module compiles, before the module's own functions exist. `validator/0` can therefore call only other modules.

`Ltix.Launch.MessageType`'s hook is one behaviour, `Ltix.Launch.MessageType.Definition`. `Definition` calls `use Ltix.Provider` in each message type's module, which makes every message type a provider without a special case in `Ltix.Provider`. `resolve/1` builds each validator once per plugin set. It also builds one for undeclared message types from the contributions to `EveryMessageType`, which lets a launch with an undeclared message type report its missing claims too.

Ltix has its own validator because combining statements needs order-independent merging, single-owner overrides, and a description of each statement, and Zoi has none of these. `Zoi.extend` drops refinements, silently replaces a field another schema declared, and fails on raw claims' string keys. Zoi still defines the shapes of claims and fields.

## Content item types

A content item type calls `use Ltix.DeepLinking.ContentItemType`, and is a provider with hook `[Ltix.Property]`.

```elixir
defmodule Ltix.DeepLinking.ContentItem.File do
  use Ltix.DeepLinking.ContentItemType,
    type: "file",
    fields: [
      url: Zoi.string(description: "URL to download the file."),
      title: title(),
      media_type: Zoi.string(description: "Media type of the file.") |> Zoi.optional(),
      expires_at: Zoi.datetime(description: "When the download URL expires.") |> Zoi.optional()
      # ...
    ]

  @impl Ltix.DeepLinking.ContentItemType
  def check(%__MODULE__{media_type: media_type}, %Ltix.DeepLinking.Settings{accept_media_types: accepted}) do
    if accepted?(media_type, accepted), do: :ok, else: {:error, ...}
  end

  # An exact match, `type/*`, or `*/*`, ignoring case and parameters. Passes when either side is `nil`.
  defp accepted?(media_type, accepted), do: # ...
end
```

- **What `use` generates.** The struct through `Ltix.Type` with `json_keys: :camel_case` and the `type` string in the schema's `metadata:`, overridable `new/1` and `new!/1` built on `Ltix.Type.new/3`, and a Fields section appended to the moduledoc at `@before_compile`, unless the moduledoc is `false`.
- **Shared fields.** `Ltix.DeepLinking.ContentItemType.Fields` has `title/1`, `text/1`, `icon/1`, `thumbnail/1`, `window/1`, `iframe/1` (`src: true` adds a required `src`), and `embed/1`. `use` imports them. `Ltix.Type.object/2` builds the schema of any other nested object.
- **API.** `Ltix.DeepLinking.ContentItemType.type/1` and `fields/1` return a content item type's `type` string and field schemas.
- **Checks.** `Ltix.DeepLinking.build_response/3` rejects any item that isn't a struct of a content item type in the plugin set, plain maps among them, with `InvalidContentItem`. It checks each content item's own `type` against `accept_types`, each of its `window`, `iframe`, and `embed` in the JSON against `accept_presentation_document_targets`, and then the optional `check/2` callback, which receives the content item and the `%Ltix.DeepLinking.Settings{}`. `File` checks `accept_media_types`, and `LTIResourceLink` checks `accept_line_item`. `accept_multiple` applies to the whole response, and its error has the index of the first content item over the limit. Errors Ltix builds about one content item have its index, and Ltix sets the `index` of a `check/2` error when the error has the field and it is `nil`.
- **Serializing.** `build_response/3` serializes each content item with `Ltix.Type.to_json/3`, the plugin set, and the `:create` operation, then puts in `type`.
- **Resolution.** `Ltix.DeepLinking.Response.resolve/1` collects the `type` string of each provider that extends `Ltix.DeepLinking.ContentItemType`, keyed by module. It reports two modules declaring one `type` and two extenders declaring one property on one content item type.
- **Plugin sets.** `build_response/3` uses the launch's plugin set, and `plugins:` replaces it.

## Rules

- **No replacing providers.** A plugin cannot replace or remove what another plugin provides. A different flow, such as another login mechanism, is a new provider that the application calls.
- **No provider collisions.** Providers and targets are modules, and module names are unique. The providers in a plugin set are a set of modules, so plugins that provide the same module provide it once. When two steps write the same key in a document, such as a claim, the later write remains, because document data is maps. A provider with its own callbacks defines how its extenders' contributions combine. Extenders of a provider without `Ltix.Ordered` run in plugin order. Two modules declaring one claim URI, short name, service endpoint, message type, or content item type fail at resolution, and so do a validator statement or an added check about a claim no module declares and two extenders declaring one property on one object claim, content item type, line item, score, result, member, or membership container.
- **Overrides.** `Ltix.Validator.override/3` is the only way a plugin makes a claim optional that another plugin requires, and `Ltix.Claims.Override` is the only way it replaces a check another plugin defines, each within named message types. Two modules overriding one claim, or one check, in one message type fail at resolution.
- **Providers have no short names.** Every provider and target is named by its module.

## Replacing 0.2's Extension Points

| 0.2 extension point | Replacement |
|---|---|
| `Ltix.LaunchClaims.Parser`, `:claim_parsers` | A declared claim, an extender of `Ltix.Claim`. For a standard claim, an extender of the object claim for each property, an `Ltix.Claims.Check`, or an `Ltix.Claims.Override` |
| `Ltix.LaunchClaims.Role.Parser`, `:role_parsers` | Removed. Roles are the URIs the platform sent, checked with `Ltix.Role` |
| `Ltix.AdvantageService` | A plugin with an endpoint claim, which implements `service/0` and `new/1`, and an `Ltix.ClientAssertion` step that adds the service's scopes |
| `Ltix.DeepLinking.ContentItem` protocol | A content item type provided by a plugin, and extenders of existing types |
| `extensions:` on scores, line items, and content items, and `extensions` on members | Extenders of the provider modules for those types, and `unrecognized` for properties no extender declares |

## Not Yet Decided

- **The contract of each of Ltix's providers.** This covers notice, tool message, and service resources.

## Spike for Hooks

A prototype in a single `.exs` file tested the provider and hook design. It compiles without warnings and prints the output shown after the code.

Two facts about Elixir shaped the design.

- A module that declares two behaviours defining the same callback gets "conflicting behaviours found. Callback function call/2 is defined by both A and B". This is why steps share one `Ltix.Step` behaviour.
- When two `use` macros both declare the same behaviour, the module gets "the behaviour Ordered has been declared twice" for each callback. This is why building blocks declare themselves once.

`Ltix.Hook.declare_once/2` in the spike is the helper that declares a behaviour once. The shipped building blocks follow the spike, and add `use` option pass-through, the optional `resolve/1`, and `Ltix.Step.run/1`, which reads the steps from the document's `plugins` field. The shipped `Ltix.Step` has no `init_all/1`, because resolution runs `init/1`.

```elixir
# ---- Ltix building blocks -------------------------------------------------

defmodule Ltix.Hook do
  # Declares a behaviour on the using module at most once.
  defmacro declare_once(behaviour, do: defaults) do
    quote do
      unless unquote(behaviour) in Module.get_attribute(__MODULE__, :behaviour, []) do
        @behaviour unquote(behaviour)
        unquote(defaults)
      end
    end
  end
end

defmodule Ltix.Step do
  @callback init(opts :: term) :: term
  @callback call(document :: struct, opts :: term) ::
              {:ok, struct} | {:error, Exception.t()} | {:halt, Exception.t()}

  defmacro __using__(_) do
    quote do
      require Ltix.Hook

      Ltix.Hook.declare_once Ltix.Step do
        def init(opts), do: opts
        defoverridable init: 1
      end
    end
  end

  # Runs once per entry when the plugin set is resolved, as Plug runs `init/1`.
  def init_all(entries), do: Enum.map(entries, fn {mod, opts} -> {mod, mod.init(opts)} end)

  # `{:error, e}` records the error and continues. `{:halt, e}` records it and stops.
  def run(document, steps) do
    Enum.reduce_while(steps, document, fn {mod, opts}, doc ->
      case mod.call(doc, opts) do
        {:ok, doc} -> {:cont, doc}
        {:error, error} -> {:cont, %{doc | errors: doc.errors ++ [error]}}
        {:halt, error} -> {:halt, %{doc | errors: doc.errors ++ [error]}}
      end
    end)
  end
end

defmodule Ltix.Ordered do
  @callback before?(module) :: boolean
  @callback after?(module) :: boolean

  defmacro __using__(_) do
    quote do
      require Ltix.Hook

      Ltix.Hook.declare_once Ltix.Ordered do
        def before?(_), do: false
        def after?(_), do: false
        defoverridable before?: 1, after?: 1
      end
    end
  end

  # Sorts like Spark. An edge exists when either side declares it, and none when both directions are declared.
  # Each entry is its own vertex, so a module listed twice runs twice. Entries in one cycle run in plugin
  # order. Every edge between entries outside a shared cycle holds.
  def sort(entries) do
    module = entries |> Enum.with_index(fn {mod, _opts}, i -> {i, mod} end) |> Map.new()
    ids = Map.keys(module)

    edges =
      for a <- ids,
          b <- ids,
          module[a] != module[b],
          first?(module[a], module[b]) and not first?(module[b], module[a]),
          do: {a, b}

    graph = :digraph.new()
    Enum.each(ids, &:digraph.add_vertex(graph, &1))
    Enum.each(edges, fn {a, b} -> :digraph.add_edge(graph, a, b) end)
    cycles = :digraph_utils.strong_components(graph)
    :digraph.delete(graph)

    groups = cycles |> Enum.map(&Enum.sort/1) |> Enum.sort_by(&hd/1)
    group_of = for group <- groups, id <- group, into: %{}, do: {id, group}

    group_edges =
      for {a, b} <- edges, group_of[a] != group_of[b], uniq: true, do: {group_of[a], group_of[b]}

    groups
    |> take_ready(group_edges, [])
    |> List.flatten()
    |> Enum.map(&Enum.at(entries, &1))
  end

  defp first?(a, b), do: a.before?(b) or b.after?(a)

  # Groups form an acyclic graph, so one group is always ready. Ties go to plugin order.
  defp take_ready([], _edges, sorted), do: Enum.reverse(sorted)

  defp take_ready(groups, edges, sorted) do
    ready? = fn group -> not Enum.any?(edges, fn {a, b} -> b == group and a in groups end) end
    next = Enum.find(groups, ready?)
    take_ready(List.delete(groups, next), edges, [next | sorted])
  end
end

defmodule Ltix.Provider do
  # `use Ltix.Provider, hook: [...]` makes a module something plugins can extend.
  # Extenders write `use ThatModule`, which declares each hook block once, adds the
  # provider's own callbacks when it defines any, and records the provider.
  defmacro __using__(opts) do
    quote bind_quoted: [hook: Keyword.get(opts, :hook, [])] do
      @ltix_hook hook
      def __ltix_hook__, do: @ltix_hook

      defmacro __using__(_opts), do: Ltix.Provider.__extender__(__MODULE__, @ltix_hook)
    end
  end

  def __extender__(provider, hook) do
    own =
      if function_exported?(provider, :behaviour_info, 1),
        do: quote(do: @behaviour(unquote(provider)))

    uses = for block <- hook, do: quote(do: use(unquote(block)))

    quote do
      unless Module.has_attribute?(__MODULE__, :ltix_extends) do
        Module.register_attribute(__MODULE__, :ltix_extends, accumulate: true, persist: true)
      end

      @ltix_extends unquote(provider)
      unquote(own)
      unquote_splicing(uses)
    end
  end
end

# ---- Bundled providers ----------------------------------------------------

defmodule Ltix.Login do
  use Ltix.Provider, hook: [Ltix.Step, Ltix.Ordered]
  defstruct params: %{}, private: %{}, errors: []
end

defmodule Ltix.Launch do
  use Ltix.Provider, hook: [Ltix.Step, Ltix.Ordered]
  defstruct claims: %{}, private: %{}, errors: []
end

defmodule Ltix.GradeService.LineItem do
  # Unordered provider with its own contract.
  use Ltix.Provider
  @callback properties() :: [{String.t(), atom}]
end

# ---- Third-party extenders ------------------------------------------------

defmodule AddTenant do
  use Ltix.Login
  use Ltix.Launch

  def init(opts), do: Keyword.fetch!(opts, :tenant)

  def call(%Ltix.Login{} = login, tenant), do: {:ok, put_in(login.private[:add_tenant], tenant)}
  def call(%Ltix.Launch{} = launch, tenant), do: {:ok, put_in(launch.claims[:tenant], tenant)}

  def after?(VerifyToken), do: true
  def after?(_), do: false
end

defmodule VerifyToken do
  use Ltix.Launch
  def call(launch, _), do: {:ok, put_in(launch.private[:verified], true)}
end

defmodule RejectUnverified do
  use Ltix.Launch
  def call(%{private: %{verified: true}} = launch, _), do: {:ok, launch}
  def call(_launch, _), do: {:halt, RuntimeError.exception("unverified")}
end

defmodule SubmissionReview.LineItem do
  use Ltix.GradeService.LineItem
  def properties, do: [{"submissionReview", :submission_review}]
end

# ---- Run ------------------------------------------------------------------

steps = Ltix.Step.init_all(Ltix.Ordered.sort([{AddTenant, tenant: "acme"}, {VerifyToken, []}]))
IO.inspect(Enum.map(steps, &elem(&1, 0)), label: "launch order")
IO.inspect(Ltix.Step.run(struct(Ltix.Launch), steps), label: "launch")
IO.inspect(Ltix.Step.run(struct(Ltix.Login), Ltix.Step.init_all([{AddTenant, tenant: "acme"}])), label: "login")
IO.inspect(Ltix.Step.run(struct(Ltix.Launch), Ltix.Step.init_all([{RejectUnverified, []}, {AddTenant, tenant: "acme"}])), label: "halted launch")

for mod <- [AddTenant, VerifyToken, SubmissionReview.LineItem] do
  attrs = mod.module_info(:attributes)
  IO.inspect({mod, for({:behaviour, [b]} <- attrs, do: b), for({:ltix_extends, [p]} <- attrs, do: p)})
end
```

The run prints this.

```
launch order: [VerifyToken, AddTenant]
launch: %Ltix.Launch{claims: %{tenant: "acme"}, private: %{verified: true}, errors: []}
login: %Ltix.Login{params: %{}, private: %{add_tenant: "acme"}, errors: []}
halted launch: %Ltix.Launch{
  claims: %{},
  private: %{},
  errors: [%RuntimeError{message: "unverified"}]
}
{AddTenant, [Ltix.Step, Ltix.Ordered], [Ltix.Login, Ltix.Launch]}
{VerifyToken, [Ltix.Step, Ltix.Ordered], [Ltix.Launch]}
{SubmissionReview.LineItem, [Ltix.GradeService.LineItem],
 [Ltix.GradeService.LineItem]}
```

The output shows four things.

- `AddTenant` extends login and launch with one `call/2`, declares `Ltix.Step` and `Ltix.Ordered` once each, and records both providers in `@ltix_extends`. That attribute is what `Ltix.Plugin.extend/2` reads.
- `AddTenant`'s `after?(VerifyToken)` overrides the default and orders it after `VerifyToken`.
- `RejectUnverified` returns `{:halt, RuntimeError.exception("unverified")}`, so the error is recorded and `AddTenant` never runs.
- `SubmissionReview.LineItem` declares only the line item provider's own behaviour and has no ordering callbacks.

Each provider writes `use Ltix.Provider` first. A provider's own callbacks are found when an extender compiles, so they can be declared after `use`. A provider listed in its own `hook:` would `use` itself and deadlock compilation, which is why a provider's own callbacks join its hook automatically.
