# Plugin System Design

Every addition to Ltix goes through plugins, whether it comes from a library for another LTI specification, a vendor, or Ltix itself. This document explains why the plugin system has the shape it has. [Writing Plugins](../guides/writing-plugins.md) shows how to use it, and the module docs, such as `Ltix.PluginSet` and `Ltix.Type`, have each function's exact behavior. Terms follow [GLOSSARY.md](../GLOSSARY.md).

## Why Ltix has plugins

LTI Advantage keeps growing. Submission Review, Proctoring, Dynamic Registration, and Platform Notification Service add message types, claims, scopes, and properties, and vendors add their own. This document follows one example, a library that adds Submission Review. It needs five things.

1. Accept launches with the message type `LtiSubmissionReviewRequest`.
2. Parse the `for_user` claim, which identifies whose submission to show.
3. Require `resource_link` and `for_user` in those launches.
4. Send and read `submissionReview` on grade service line items.
5. Send `submissionReview` on the line item a Deep Linking resource link creates.

Ltix 0.2 had no way to add a message type, so the first item was impossible. The others each needed a different extension point, and each point had gaps.

| 0.2 extension point | What it lacked | Replacement |
|---|---|---|
| `Ltix.LaunchClaims.Parser`, `:claim_parsers` | A parser for a standard claim replaced all of Ltix's parsing and checks for that claim | A declared claim. For a standard claim, a property extender, an `Ltix.Claims.Check`, or an `Ltix.Claims.Override` |
| `Ltix.LaunchClaims.Role.Parser`, `:role_parsers` | A platform's own role needed a parser before a check could match it | Removed. Roles are the URIs the platform sent |
| `Ltix.AdvantageService` | A service could add scopes, but not client assertion claims | An endpoint claim and an `Ltix.ClientAssertion` step |
| `Ltix.DeepLinking.ContentItem` protocol | Ltix couldn't check a plain map's fields, and nothing could add a property to it | Content item types, and extenders of them |
| `extensions:` on scores, line items, and content items, and `extensions` on members | Maps keyed by JSON name that Ltix never parsed or checked | Property extenders, and `unrecognized` for undeclared properties |
| A `%Ltix.GradeService.LineItem{}` with `extensions` as a Deep Linking line item | `LTIResourceLink.new/1` rejected its extensions | Extenders of `Ltix.DeepLinking.LineItem` |

The plugin system replaces all of them with one model. Ltix's own Core, Deep Linking, AGS, and NRPS support are plugins built on it, and a library can do anything they do.

The plugin system covers what libraries add to Ltix. It leaves out how an application integrates Ltix, such as the storage adapter, `Ltix.Registerable`, global configuration, and telemetry. An application has one of each, and there's nothing to combine.

## Plugins, providers, and extenders

A plugin's `plugin/1` returns a manifest with three relationships.

- **Provides.** A provider defines a document or a type. Its hook is the behaviours its extenders implement.
- **Extends.** An extender implements one or more providers' hooks.
- **Depends on.** A dependency is another plugin that resolution adds before this one.

```elixir
defmodule Review do
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Ltix.Plugin.new(name: "Submission Review", version: "1.0.0")
    |> Ltix.Plugin.add(Review.Request)
    |> Ltix.Plugin.add(Review.ForUser)
    |> Ltix.Plugin.add(Review.SubmissionReview)
  end
end
```

`Review.Request` declares the message type. Every message type's module is a provider, so other plugins can change what Submission Review launches require. `Review.ForUser` declares `for_user`, and `Review.SubmissionReview` extends both line item providers.

A provider calls `use Ltix.Provider`. An extender calls `use` on each provider it extends. Message types and declared claims are both providers and extenders. Every provider and extender is added to a manifest with `Ltix.Plugin.add/2`, which reads its roles from the module. A manifest can't contradict them.

`add/2` raises `ArgumentError` for a module that is neither a provider nor an extender. `Ltix.Plugin.depend_on/2` raises it for a module that isn't a plugin. Both raise when resolution calls `plugin/1`, before any step runs.

The model follows two libraries Elixir developers know. A document and its steps follow `%Plug.Conn{}` and plugs, with `init/1` once and `call/2` per call. Step ordering follows Spark's transformer sorting.

A manifest is data that can be read without running a call. Providers collect information from manifests outside any call, such as the message types a Dynamic Registration plugin advertises, or the content item types Ltix checks against `accept_types`.

### Default plugins

`Ltix.Core` provides login, launch, and client assertions. `Ltix.DefaultPlugins` depends on `Ltix.Core`, `Ltix.DeepLinking`, `Ltix.GradeService`, and `Ltix.MembershipsService`. All five load first in every plugin set, and no option removes them. Enabling one gives it options without moving it.

The cost of building Ltix's features as plugins is that phase names, such as `Ltix.Launch.Verified`, are public API, because other steps order against them. A phase is a default step that changes nothing. Renaming one is a breaking change that no error reports, because ordering against a missing module has no effect. The other default steps are internal.

## Plugin sets

A plugin set is the plugins one call runs with.

| Call | Plugin set |
|---|---|
| Any call, by default | `config :ltix, plugins: [...]` |
| A call with `plugins:` | Those plugins |
| A call given a `%Ltix.Launch{}` | The launch's `plugins`, unless the call has `plugins:` |
| A call given an `%Ltix.OAuth.Client{}` | The client's `plugins`, unless the call has `plugins:` |

A launch and a client keep their plugin set, and later calls that take them use the same plugins. A Deep Linking response includes the content item properties of the plugins its launch ran with, such as `submissionReview` when the launch ran with `Review`. A client's refreshes request the same scopes as its first token.

### Resolution

`Ltix.PluginSet.resolve/1` always gives the same plugin set for the same enabled plugins.

1. **Plugin order.** Default plugins first, then the enabled plugins. Dependencies are added depth first. Each plugin module takes one place in plugin order, after its dependencies. That place is where resolution first reaches it.
2. **Manifests.** A plugin gets one manifest for each time the application enables it, built with that entry's options. A dependency the application doesn't enable gets `[]`. Only the application sets options, so one plugin can't configure another.
3. **Extender entries.** Each manifest adds its entries. A plugin enabled twice runs each of its steps twice. `init/1` runs once per step entry. A claim or property module has one declaration in the plugin set, because a claim has one parser and a property one serializer. Its entries with different options are a conflict. Identical entries count once, so two plugins can add the same claim module. A plugin runs a step in several configurations by taking a list in its options and adding an entry for each.
4. **Providers.** The providers of every manifest, once each, in plugin order.
5. **Order.** Each provider's entries keep plugin order, sorted by `Ltix.Ordered` when the hook includes it.
6. **Provider resolution.** Each provider's `resolve/1` runs once, in plugin order, and returns data its calls read, or conflicts.

Any conflict fails resolution with `Ltix.Errors.Unknown.InvalidPluginSet`, which lists every conflict with the plugins involved.

Ltix keeps each resolved plugin set, or its error, for the life of the node, keyed by the enabled plugins. Resolution calls every `plugin/1`, `init/1`, and `resolve/1`, and later calls with the same plugins skip all of it. The cost is that each distinct `plugins:` list stays in memory, and these lists must come from fixed values.

## Documents and steps

A document is the state of one call that several specifications or vendors add to. Ltix passes it to steps from many plugins in order, and returns it to the caller.

| Document | Created by | What plugins add |
|---|---|---|
| `%Ltix.Login{}` | `Ltix.handle_login/3` | Parameters and checks |
| `%Ltix.Launch{}` | `Ltix.handle_callback/3` | Checks, claims, and data |
| `%Ltix.ClientAssertion{}` | `Ltix.OAuth.authenticate/2` and client refreshes | Scopes and client assertion claims |
| `%Ltix.DeepLinking.Response{}` | `Ltix.DeepLinking.build_response/3` | Response claims |

Each document's hook is `[Ltix.Step, Ltix.Ordered]`. A step returns `{:ok, document}`, `{:error, exception}`, or `{:halt, exception}`. Ltix needs both error results.

- A failed security check halts, so nothing reads claims from an unverified message.
- A malformed claim records an error and continues, so one error reports every malformed and missing claim.

A step that needs a valid document, such as the launch's deployment lookup, checks `errors` first. Steps keep their own data in `private` under keys prefixed with their library's name, so libraries don't overwrite each other.

Browser postMessages aren't documents, because nothing in the browser calls Ltix. Line items, scores, results, members, and membership containers aren't either. They're types, which plugins add properties to, and no steps receive them.

Each message the tool signs is its own document. A Proctoring plugin provides a Start Assessment document, and a Platform Notification Service plugin a notice document. There's no shared provider for tool messages, because the Deep Linking response is the only one Ltix has to generalize from.

### Login

Login and launch are separate requests, and separate documents. Login returns `state`, the application keeps it in the session, and the launch receives it. Ltix derives the nonce from the state and the registration. During the launch, Ltix derives it again to check that both match the login's.

The login's registration lookup sets `registration` and `source_registration` on the login, and the launch's lookup sets them on the launch. A login step ordered after the phase `Ltix.Login.RegistrationFound` can read them without its own storage lookup.

### Launch

`claims` is the launch's `assigns`, beside `raw`, `endpoints`, and `private`. Its default steps and phases run in this order, and plugins order their steps against the phases.

1. Steps check the authentication response, look up the registration, and verify the ID token. Each halts on failure.
2. `Ltix.Launch.Verified`. The message is authentic and comes from a known registration.
3. `Ltix.Launch.ClaimsReceived`. Ltix parses the claims next.
4. A step parses the claims and runs their checks. Failures are recorded, and the launch continues.
5. `Ltix.Launch.ClaimsParsed`. The claims are parsed and checked.
6. Steps check the message type and its required claims. Missing claims are reported together with malformed ones. A malformed claim counts as present and is reported once, as malformed. A malformed claim declared with [`strict: false`](#declared-claims) is `nil`, so a message type that requires it reports it missing.
7. `Ltix.Launch.Validated`. The message type and its required claims are checked.
8. A step looks up the deployment for a launch without errors.

The deployment lookup is last. A storage adapter that creates a deployment the first time it sees an ID never sees a malformed launch.

Each default launch step other than a phase declares its place against the phases with `before?/1` and `after?/1`. A plugin step ordered after `Ltix.Launch.Verified` and before `Ltix.Launch.ClaimsReceived` can rewrite `raw` or write claims of its own, and parsed claims replace written ones with the same short name. Core lists its steps in the order they run, so a plugin step whose declarations form a cycle with them can't reorder them, because cycles run in plugin order and the default plugins come first.

`Ltix.Test.build_launch/2` runs the steps without the security steps and the deployment lookup, so plugin tests need no OIDC flow.

### Client assertion

Steps add scopes and client assertion claims. The AGS plugin's step adds the endpoint's scopes, and the NRPS plugin's step the NRPS scope. Submission Review uses the AGS scopes and adds no step. The document has no phases, because no step needs to run before or after the default ones.

The document starts with the endpoints the token is for, and no step needs an order to see them. In an earlier design, services added endpoints in their own steps. A vendor step without an order saw the endpoints on refreshes but not on the first request, and the first token lacked its scope.

`Ltix.OAuth.authenticate/2` returns `ServiceNotAvailable` for a service without an endpoint before it builds the document. It checks every endpoint with its claim's `new/1`, and an endpoint an application stored gets the same checks as one from a launch.

### Deep Linking response

`build_response/3` returns content item errors before it builds the document, and steps see only items that passed. There are no default response steps.

## Providers

A provider calls `use Ltix.Provider` and defines three things.

1. **The document or type**, such as `%Ltix.Launch{}`.
2. **Its hook**, given as `hook:`. Each `@callback` the provider declares is part of it.
3. **Its entry point**, the function an application calls.

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

A provider calls `use Ltix.Provider` before it declares its own callbacks, which are read when an extender compiles. Ltix adds a provider's own callbacks to its hook, because a provider listed in its own `hook:` would `use` itself and deadlock compilation.

Each provider sets its own policies. It decides which plugin set applies to the values it creates during a call, and what happens when two extenders add one property. It also decides who creates its values. The grade service creates line items from responses, and the application creates content items and passes them in.

A provider also decides how finely it can be extended. The AGS plugin provides `Ltix.GradeService.LineItem`. The line item in a Deep Linking resource link has fewer fields, so the Deep Linking plugin provides it separately as `Ltix.DeepLinking.LineItem`, and `Review.SubmissionReview` opts into both.

### Extenders

This extender adds a tenant to every login and launch.

```elixir
defmodule AddTenant do
  use Ltix.Login
  use Ltix.Launch

  def init(opts), do: Keyword.fetch!(opts, :tenant)

  def call(%Ltix.Login{} = login, tenant), do: ...
  def call(%Ltix.Launch{} = launch, tenant), do: ...

  def after?(Ltix.Launch.Verified), do: true
  def after?(_module), do: false
end
```

- **One `call/2` for several documents.** Every document's hook shares one `Ltix.Step` behaviour, which avoids Elixir's warning for a module that declares two behaviours with the same callback.
- **Behaviours declared once.** `AddTenant` gets `Ltix.Ordered` from both hooks. Elixir warns when a module declares one behaviour twice, so each behaviour declares itself through `Ltix.Hook.declare_once/2`.
- **Conflicting callbacks.** Two providers with same-named callbacks of their own trigger Elixir's "conflicting behaviours" warning in a module that extends both. Split it in two. A contract several providers share belongs in one behaviour that both hooks include.
- **Absent providers.** Extending a provider that isn't in the plugin set does nothing. A plugin can extend an optional provider. A plugin that needs one depends on its plugin.

## Behaviours

Providers combine these public behaviours into hooks, so third-party providers use the same pieces as Ltix's own.

### Steps

`Ltix.Step` has `init/1` and `call/2`. `Ltix.Step.run/1` runs a document's steps from its `plugins`, and `run/2` runs the entries it's given, which is how `build_launch/2` leaves out the security steps.

### Ordering

`Ltix.Ordered` has `before?/1` and `after?/1`. Only providers whose extenders run in order include it. A content item type's extenders add properties and have no order.

- A step runs before another when either declares it.
- A pair that declares both orders gets neither. The declarations disagree, and neither is more likely right.
- Each extender entry is a separate node, and a module with two entries runs twice. Entries in a cycle run in plugin order, and orders outside the cycle still hold.
- Among ready steps, plugin order decides, so a plugin set orders its steps the same way on every call. A step relies only on the orders it declares, and a step can order itself after or before every other step by returning `true` for every module.

Ordering works on modules, so each phase is its own module. Plugins order against phases, and the other default steps are undocumented, so they can be renamed, split, or reordered between the same two phases.

Each step declares its own order, because steps come from many plugins, the application doesn't list them, and a step's author can tell what it must follow. Order is the one place Ltix tolerates disagreement. Two plugins that both parse one claim leave no correct parse, and they conflict.

### Properties

A property extender declares, parses, and serializes one JSON property on a type. It declares a property name with `use`, and its value is in the type's `extensions` under that name.

- An application passes a property by name, like a standard field, where it builds the type, as in `create_line_item(client, label: "Essay", score_maximum: 10, submission_review: review)`. It reads the value from `item.extensions.submission_review`. Using a plugin's property takes one call, like 0.2's `extensions:`. The rejected alternative, keying values by extender module, needed the extender module in every read and write.
- Builders read the property names from the plugin set. A service call uses its `:plugins` option or the client's set, and `new/1` uses its `:plugins` option or the configured plugins. A name that's neither a field nor a property returns an error when the value is built, before any request.
- The value is the extender's Elixir form, such as a map with atom keys or a struct. `parse/2` and `serialize/2` convert it, and an application reads and writes only the Elixir form.
- Ltix sends a value only when its extender is in the plugin set, and only for the write operations `writes/0` lists. A property extender for Canvas's submission type returns `[:create]`, and updating a line item leaves that property out.

The cost is that an application can't send a property through `extensions` under its JSON name. Undeclared properties are kept in `unrecognized`, keyed by JSON name, and Ltix sends them back unchanged. An application that needs one property without a plugin puts it there.

A property name or JSON name has one meaning on a type wherever an application builds or reads it. `Ltix.Property.conflicts/2` lists the extenders that would give one two meanings. The default `resolve/1` reports them for every provider whose hook includes `Ltix.Property`.

### Types

`Ltix.Type` builds a type's struct from Zoi schemas, and adds `extensions` and `unrecognized`. `from_json/3` and `to_json/3` take a plugin set, so the JSON includes that set's properties. Every type uses it, so JSON names, `strict` field metadata, and properties have one implementation.

0.2's `from_json/1`, `to_map/1`, and JSON encoders are gone, because a type's JSON now depends on the plugin set and, for a line item, the write operation.

## Where properties are parsed and sent

Each of Ltix's types is a provider with hook `[Ltix.Property]`.

| Type | Provided by | Properties are |
|---|---|---|
| Object claims, such as `Ltix.Claims.LaunchPresentation` | The plugin that declares the claim | Parsed in launches and member messages |
| `Ltix.GradeService.LineItem`, `Score`, `Result` | `Ltix.GradeService` | Parsed on read, sent by `create_line_item/3` as `:create`, `update_line_item/3` as `:update`, and `post_score/3` as `:create` |
| `Ltix.MembershipsService.Member`, `MembershipContainer` | `Ltix.MembershipsService` | Parsed by `list_members/2` and `stream_members/2` |
| Content item types | The plugin that declares the type | Sent by `build_response/3` as `:create` |
| `Ltix.DeepLinking.LineItem` | `Ltix.DeepLinking` | Sent with its content item as `:create` |

Member messages are parsed as launch claims, and their checks run for each message's `message_type`. They aren't checked for required claims, because a platform sends only some claims in a message. A message without `roles` is checked with the member's roles, which the platform sends on the member.

`Ltix.DeepLinking.ContentItem.LTIResourceLink.new/1` takes a grade service line item. It keeps each property that an extender of `Ltix.DeepLinking.LineItem` declares under the same name, and returns an error for any other property or for a field Deep Linking can't send. Nothing an application set is silently dropped.

## Declared claims

`Ltix.Claim` is a provider with hook `[Ltix.Property, Ltix.Claim.Declaration]`, so a declared claim is a property whose JSON name is the claim's URI.

```elixir
defmodule Review.ForUser do
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

`build_response/3` rejects anything that isn't a content item type in the plugin set, plain maps included. A declared type lets Ltix check every item against the platform's settings before signing, and a custom type gets the same checks as Deep Linking's.

## Rules

These rules keep plugins from breaking each other.

- **No replacing providers.** A plugin can't replace or remove what another plugin provides.
- **Providers are named by module.** Unlike claims, providers have no short names. A module that two plugins provide is one provider.

An application that needs another login flow writes a new provider with its own entry point. In exchange, every plugin can rely on Ltix's documents existing and doing what their docs say, and a security check can only be replaced by an override that `Ltix.Claims.overrides/1` lists.

## Appendix. Spike for hooks

A one-file spike tested the provider and hook design before implementation. It found the two Elixir warnings that [Extenders](#extenders) describes, and its final version, below, compiles without warnings and prints the output after the code.

The shipped behaviours follow the spike, and add `use` option pass-through, `resolve/1`, and `Ltix.Step.run/1`. The shipped `Ltix.Step` has no `init_all/1`, because resolution runs `init/1`. The spike predates the rest of the design. Its line item provider has a callback of its own where the shipped one has hook `[Ltix.Property]`, its `AddTenant` writes an undeclared claim, and its module names differ.

```elixir
# ---- Ltix behaviours -------------------------------------------------------

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
  # Each entry is its own vertex, so a module with two entries runs twice. Entries in one cycle run in plugin
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

  def after?(VerifyIdToken), do: true
  def after?(_), do: false
end

defmodule VerifyIdToken do
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

steps = Ltix.Step.init_all(Ltix.Ordered.sort([{AddTenant, tenant: "acme"}, {VerifyIdToken, []}]))
IO.inspect(Enum.map(steps, &elem(&1, 0)), label: "launch order")
IO.inspect(Ltix.Step.run(struct(Ltix.Launch), steps), label: "launch")
IO.inspect(Ltix.Step.run(struct(Ltix.Login), Ltix.Step.init_all([{AddTenant, tenant: "acme"}])), label: "login")
IO.inspect(Ltix.Step.run(struct(Ltix.Launch), Ltix.Step.init_all([{RejectUnverified, []}, {AddTenant, tenant: "acme"}])), label: "halted launch")

for mod <- [AddTenant, VerifyIdToken, SubmissionReview.LineItem] do
  attrs = mod.module_info(:attributes)
  IO.inspect({mod, for({:behaviour, [b]} <- attrs, do: b), for({:ltix_extends, [p]} <- attrs, do: p)})
end
```

The run prints this.

```
launch order: [VerifyIdToken, AddTenant]
launch: %Ltix.Launch{claims: %{tenant: "acme"}, private: %{verified: true}, errors: []}
login: %Ltix.Login{params: %{}, private: %{add_tenant: "acme"}, errors: []}
halted launch: %Ltix.Launch{
  claims: %{},
  private: %{},
  errors: [%RuntimeError{message: "unverified"}]
}
{AddTenant, [Ltix.Step, Ltix.Ordered], [Ltix.Login, Ltix.Launch]}
{VerifyIdToken, [Ltix.Step, Ltix.Ordered], [Ltix.Launch]}
{SubmissionReview.LineItem, [Ltix.GradeService.LineItem],
 [Ltix.GradeService.LineItem]}
```

- `AddTenant` extends login and launch with one `call/2`, declares `Ltix.Step` and `Ltix.Ordered` once each, and records both providers in `@ltix_extends`, the attribute `Ltix.Plugin.add/2` reads.
- `after?(VerifyIdToken)` puts `AddTenant` after `VerifyIdToken`.
- `RejectUnverified` halts, so its error is recorded and `AddTenant` never runs.
- `SubmissionReview.LineItem` declares only its provider's own behaviour, with no ordering callbacks.
