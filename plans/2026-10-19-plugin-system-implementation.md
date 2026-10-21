# Plugin System Implementation Plan

## Overview

Ltix 0.2's extension points are replaced by the plugin system described in `plans/2026-10-18-plugin-system.md`. Core, Deep Linking, AGS, and NRPS become bundled plugins that keep 0.2's behavior, and the 0.2 code they replace is removed. This plan converts what 0.2 already does. Every other LTI specification shaped the design so later plans fit, and none of them is built here.

The design decisions below were settled during planning and are recorded in "Design Decisions". Each phase includes the accepted author-facing code from the planning spikes as the reference shape. The code that ships will differ in detail.

## Current State Analysis

- **Launch** is one fixed `with` chain in `lib/ltix/oidc/callback.ex:48-86`. It checks the error response, id_token, state, issuer claims, registration, token, nonce binding, `validate_nonce`, required claims, deployment, and then calls `LaunchClaims.from_json`. It returns `%LaunchContext{}` (`lib/ltix/launch_context.ex:23`) whose `registration` is the host's record.
- **Message types are hardcoded.** `callback.ex:201-216` accepts only `LtiResourceLinkRequest` and `LtiDeepLinkingRequest`. Required claims per type are at `callback.ex:184-197`, and `launch_claims.ex:402-406` loosens `resource_link` and `deep_linking_settings` parsing by type.
- **Claim parsing** is `LaunchClaims.from_json/2` with fixed Zoi structs per claim (`lib/ltix/launch_claims/*.ex`), plus `:claim_parsers` merged from app config and call options (`app_config.ex:31-37`, `launch_claims.ex:263-269`). Unknown claims land raw in `claims.extensions`. Claims Core never requires are parsed through `ClaimHelpers.optional` (`claim_helpers.ex:4-18`), so a malformed one becomes `nil` (`launch_claims.ex:238-249,272-283`).
- **Roles** are parsed into `%Role{}` structs by prefix-keyed parsers (`launch_claims/role.ex`, `role/lis.ex`), with app-config parsers only for NRPS members (`member.ex:129`, `membership_container.ex:80`).
- **Advantage services** implement `Ltix.AdvantageService` (`advantage_service.ex:33-39`). `Ltix.OAuth.authenticate/2` unions scopes across services (`oauth.ex:140-159`, `client.ex:425-440`), and `Client.force_refresh/1` does it again (`client.ex:307-326`). The client assertion is built in `client_credentials.ex:151-167`. `%Ltix.OAuth.Client{}` keeps no plugin information.
- **`extensions:`** on `Score`, `LineItem`, `Result`, `Member`, and the five content items is a string-keyed map checked against standard keys (`extensions.ex:47-66`). `LineItem`, `Result`, and `Member` also keep unrecognized response keys there.
- **Deep Linking** dispatches items through the `Ltix.DeepLinking.ContentItem` protocol, including a `Map` impl for one-off items (`content_item.ex:43-45`). `build_response/3` validates the serialized maps with hardcoded type strings (`deep_linking.ex:225-329`).
- **Test helpers** in `lib/ltix/test.ex` build `%LaunchContext{}` and stub services, and `test/ltix/launch_claims_config_test.exs` and `test/support/memberships_service_helper.ex` change global `Application` env for parsers.

## Desired End State

- An app with no plugin configuration gets 0.2's behavior from the bundled plugins, with these deliberate changes:
  - `%Ltix.Launch{}` replaces `%LaunchContext{}` and `%LaunchClaims{}`.
  - Roles are URI strings.
  - Core 1.3.0's `role_scope_mentor` rule is enforced.
  - The `organization` and `actual_user` claims are parsed.
  - Plain-map content items are rejected.
  - A malformed `resource_link` or `deep_linking_settings` fails the launch in every message type.
- A third-party plugin can do each of these without changing Ltix:
  - add a login or launch step
  - own a claim, add a property inside another plugin's claim, add a claim check, or override a named check within message types
  - declare a message type and contribute to another type's validator
  - add scopes and claims to token requests
  - add a property to line items, scores, results, members, or content items
  - declare a content item type
  - depend on other plugins
- Conflicts fail when the plugin set is resolved, naming both parties.
- No 0.2 extension point remains: `:claim_parsers`, `:role_parsers`, `Ltix.LaunchClaims.Parser`, `Ltix.LaunchClaims.Role.Parser`, `Ltix.AdvantageService`, the `ContentItem` protocol, and `Ltix.Extensions` are gone.
- `plans/2026-10-18-plugin-system.md` matches what was built.
- `guides/upgrading-to-0.3.md` covers every breaking change.

### Key Discoveries:
- Core §5.3.7 requires a non-empty `roles` list to contain at least one standard vocabulary role, so a platform's own role URIs always arrive alongside a standard one. That is why roles need no parsing extension point.
- Core 1.3.0 and 1.3.1 both send `version: "1.3.0"`, so a message never says which revision it follows. The bundled Core plugin follows 1.3.0.
- Messages of every kind repeat the same claim shapes, while required claims vary by message type. Parsing is shared and per claim, and required-claim validation is per message type.
- Zoi can't combine plugins' contributions. `Zoi.extend` drops refinements, replaces fields silently, and fails on string keys. Ltix owns a small validator value and keeps Zoi for claim and field shapes.
- `Zoi.struct/3` keeps field order when the fields are a keyword list and the options are non-empty.
- A behaviour declared twice by two `use` macros warns, which is why building blocks declare themselves once with `Ltix.Hook.declare_once/2`.

## What We're NOT Doing

- Notices and PNS, Proctoring, ACS, Dynamic Registration, platform storage, the Core 1.3.1 plugin, Submission Review, EULA, Asset Processor, and any other specification 0.2 doesn't implement. The decisions that mention notices are designed but not built. Decisions that mention Submission Review are verified with test-only plugins.
- A shared tool message provider. The Deep Linking response is the only tool-signed message, so it is its own document.
- Changing the storage adapter, `Ltix.Registerable`, `Ltix.Deployable`, global configuration, or telemetry beyond what the new documents need.
- Changing the error shape. Entry points return `{:ok, document}` or `{:error, exception}` as in 0.2.

## Design Decisions

These were settled during planning. Numbers are the planning agenda's.

1. **Types.** Line item, Score, Result, Member, MembershipContainer, the content item types, and object-valued claims are types with named standard fields. Each extender owns one JSON property through `Ltix.Property` (`property/0`, `parse/2`, `serialize/2`). Parsed values go in `extensions`, keyed by extender module, through `get_extension/2` and `put_extension/3`. Unclaimed properties go in `unrecognized` and are written back unchanged. Two extenders owning one property fail at resolution.
2. **Endpoints.** Message documents have an `endpoints` map keyed by service module. A service's endpoint claim owner declares `service/0`, and `Ltix.Claims` puts its parsed value into `endpoints[service]`. Two owners declaring the same `service/0` fail at resolution. `authenticate/2` reads `endpoints`, and the registration form takes explicit endpoints. Client assertion extenders only add scopes and claims. `Ltix.AdvantageService` goes away, and endpoint validation moves to the endpoint types.
3. **Plugin sets after a launch.** `%Ltix.OAuth.Client{}` keeps the plugin set it was authenticated with, and refresh and service calls use it. `plugins:` on a call replaces it. Claim parsing is one shared `Ltix.Claims` type. Launches run it as a step after their security checks, and NRPS member messages run it directly. Claim checks run after every claim is parsed. Member messages never get per-type required-claim validation, and claim checks apply to them scoped by their `message_type`.
4. **Content item types.** A type is `use Ltix.DeepLinking.ContentItemType, type: "...", fields: [...]`, with Zoi field schemas as a keyword list and shared fields from imported helpers.
   - **What `use` generates.** The struct, a fully typed `@type t`, `@enforce_keys`, overridable `new/1` and `new!/1`, and the options section of the moduledoc. It respects `@moduledoc false`. A documented API exposes the type string and fields.
   - **Serialization.** Fields serialize to camelCase with a per-field key override, caller-chosen keys are left alone, and unknown keys are rejected.
   - **Checks.** Type-specific settings checks go in `check/2`. The presentation target check applies to any item with `window`, `iframe`, or `embed`. `accept_types` (against each item's own type) and `accept_multiple` are response-wide.
   - **Rejections.** Plain maps are rejected, and two modules declaring one type string fail at resolution.
   - `Ltix.Provider` passes an extender's `use` options to its hook blocks.
5. **Message types.** Each message type is a module that `use`s `Ltix.Launch.MessageType` and builds a validator by piping `new/1`, `required/3`, and `optional/3` over claim short names.
   - **Conditions** are data: `option/1`, `includes/3`, or a condition module with `met?/3` and `describe/1`.
   - **Contributions.** Every message type is a provider. Plugins extend one type with `use Ltix.DeepLinkingRequest`, or every type with `use Ltix.Launch.EveryMessageType`, by implementing `validator/1`.
   - **Combining.** Statements only tighten, and required beats optional. `override/3` is the only way to loosen, and two overrides of one claim in one type fail at resolution. `defaults/2` fills unstated claims.
   - **Resolution failures.** Duplicate claim short names, unknown claim names, and two modules declaring one type string.
   - Undeclared message types are rejected. Validators are built once per plugin set, and options and message content are evaluated per message.
6. **Roles.** Roles are URIs. Role claims hold the URIs as received, with no `unrecognized_roles`. This covers `launch.claims.roles`, NRPS member roles, and `actual_user.roles`. `Ltix.Role` is a plain module with LIS URI constants and predicates that compare URIs, covering sub-roles, simple names, and deprecated forms. Role parsing is not an extension point.
7. **Deep Linking line item.** `Ltix.DeepLinking.LineItem` is its own provider type with Deep Linking's five fields. Extenders opt into each line item type separately. Passing a `%Ltix.GradeService.LineItem{}` still works:
   - The five shared fields are copied.
   - Setting `id`, `resourceLinkId`, `startDateTime`, or `endDateTime` is an error.
   - An extension value carries over only when its extender also extends the Deep Linking type.
8. **Create-only properties.** `Ltix.Property` has an optional `writes/0`, defaulting to `[:create, :update]`. Types serialize with the operation they perform, and Deep Linking line items always serialize as `:create`. Reads parse every claimed property.
9. **Core revision.** The bundled Core plugin follows Core 1.3.0 Final. Core 1.3.1 is a separate, non-bundled plugin for a later plan.
10. **Claim ownership.** Each claim has one owner module, and different owners of one claim fail at resolution. The same module listed by several plugins counts as one owner. The owner's parser accepts every shape in use.
    - **Checks.** Any plugin can add checks to any claim, optionally scoped to message types, and all checks must pass.
    - **Overrides.** A plugin can explicitly override a named check within named message types. Two overrides of one check in one message type fail at resolution, and overrides can be listed from the plugin set.
    - **Properties.** New properties on an existing claim come from property extenders (decision 1).
11. **Profiles.** A named profile is a plugin whose manifest is only `depend_on/2` calls.
12. **Dependencies.** `Ltix.Plugin.depend_on/2` names a module. Resolution adds dependencies transitively. Each plugin module appears once, and dependencies come first. A cycle fails. Options come only from the app's listing.
13. **Absent providers.** Extending an absent provider, or ordering against a module that isn't running, stays silent.
14. **Scope.** Only converting 0.2 is in scope (see "What We're NOT Doing").
15. **Errors.** Entry points return `{:ok, document}` when the document has no errors. Otherwise they return `{:error, exception}`, with the errors combined into one Ltix error as in 0.2.
16. **Resolution hook.** A provider can define an optional `resolve/1` callback that runs when the plugin set is resolved. It returns per-set data, such as validators, or resolution errors.
17. **Malformed claims.** Core 1.3.0's claim owners keep 0.2's behavior for malformed claims. A malformed claim that 0.2 parsed through `ClaimHelpers.optional` is left out of `claims`, and stays in `raw`. A malformed optional property inside a claim becomes `nil`. The stricter 1.3.1 rule belongs to the future 1.3.1 plugin as a claim check.

## Implementation Approach

Phases are vertical slices through public entry points. Phase 1 builds the plugin machinery and proves it end to end on the smallest document, login. Each later phase converts one 0.2 capability to plugins, removes the 0.2 code it replaces, and in the same change does three more things:
- adds its section to `guides/upgrading-to-0.3.md`
- updates `Ltix.Test` and the guides it touches
- amends `plans/2026-10-18-plugin-system.md` where its decisions change the spec

Tests are end to end through `handle_login/3`, `handle_callback/3`, `authenticate/2`, the service calls, and `build_response/3`, with test-only plugins under `test/support/plugins/`. Test-only plugins stand in for later specifications: a Submission Review-like extender of both line item types, a 1.4-like override, and a vendor tenant claim.

Phase modules, such as `Ltix.Login.RegistrationFound`, are the steps other plugins order against. They're documented and keep stable names, and renaming one is a breaking change.

---

## Phase 1: Plugin Sets and the Login Document

### Overview

This phase adds the building blocks, plugin manifests, and plugin set resolution, and makes `handle_login/3` the entry point of the `Ltix.Login` document. Login is the smallest document, so the whole mechanism is proven end to end before launches move.

### Red-Green TDD Test Plan:
1. A test-only `AddTenant` extender of `Ltix.Login`, listed in `config :ltix, plugins:`, writes to `login.private`. Then `handle_login/3` returns the redirect with the stored state. File: `test/ltix/plugins/login_test.exs`.
2. `plugins:` at the call replaces the configured list.
3. Two extenders ordered with `after?/1` run in that order, and a cycle between them runs in plugin order.
4. A step returning `{:halt, e}` stops later steps, and `handle_login/3` returns `{:error, e}`. A step returning `{:error, e}` lets later steps run, and the errors are combined.
5. `init/1` runs once per extender entry at resolution, and its result reaches every `call/2`.
6. A plugin listed twice provides each module once, and each listing adds its own extender entries.
7. `depend_on/2` pulls in an unlisted dependency with `[]` options. A plugin needed by two others appears once, dependencies come first, and a cycle fails at resolution.
8. A profile plugin with only `depend_on/2` calls brings in its members.
9. Extending a provider no plugin provides does nothing, and `before?/1` naming a module that isn't running does nothing.
10. A test-only provider's `resolve/1` returning errors makes `handle_login/3` return the resolution error.

### Changes Required:

#### 1. Building blocks
**Files**: `lib/ltix/hook.ex`, `lib/ltix/step.ex`, `lib/ltix/ordered.ex`, `lib/ltix/provider.ex`
**Changes**: These are taken from the spec's spike, with one change. `Ltix.Provider` passes an extender's `use` options to each hook block (decision 4). `Ltix.Ordered.sort/1` is the spec's Spark-style sort.

```elixir
defmodule Ltix.Provider do
  defmacro __using__(opts) do
    quote bind_quoted: [hook: Keyword.get(opts, :hook, [])] do
      @ltix_hook hook
      def __ltix_hook__, do: @ltix_hook
      defmacro __using__(opts), do: Ltix.Provider.__extender__(__MODULE__, @ltix_hook, opts)
    end
  end

  def __extender__(provider, hook, opts) do
    own = if function_exported?(provider, :behaviour_info, 1), do: quote(do: @behaviour(unquote(provider)))
    uses = for block <- hook, do: quote(do: use(unquote(block), unquote(opts)))

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
```

#### 2. Plugin manifest
**File**: `lib/ltix/plugin.ex`
**Changes**: The `Ltix.Plugin` behaviour has `plugin/1`, the struct has `name`, `version`, `providers`, `extenders`, and `dependencies`, and the builders are `new/1`, `provide/2`, `extend/2`, and `depend_on/2`.

```elixir
def plugin(_opts) do
  Ltix.Plugin.new(name: "Asset Processor", version: "1.0.0")
  |> Ltix.Plugin.depend_on(ReportReview)
  |> Ltix.Plugin.depend_on(AssetProcessorNotice)
end
```

#### 3. Plugin set resolution
**File**: `lib/ltix/plugin_set.ex`
**Changes**:
- **Listing order.** Bundled plugins first, then `config :ltix, plugins:` or the call's `plugins:`, expanded by dependencies.
- **Dependencies.** Each plugin module appears once, dependencies come before the plugins that need them, and options come only from the app's listing.
- **Entries.** `init/1` runs once per extender entry.
- **Provider resolution.** Each provider's optional `resolve/1` runs, and its data is kept on the set under the provider module.
- **Failures.** Conflicts and cycles return `{:error, %Ltix.Errors.Unknown.InvalidPluginSet{conflicts: [...]}}`, and every conflict names both parties.
- **Caching.** Resolved sets are cached in `:persistent_term`, keyed by the normalized listing, so validators and other per-set data are built once.

`run/2` sorts a document provider's extenders and runs them as steps. An absent provider runs nothing.

#### 4. Bundled plugin manifest
**File**: `lib/ltix/bundled.ex`
**Changes**: This plugin depends on the Core, Deep Linking, AGS, and NRPS plugins as they're added in later phases. In this phase it provides only `Ltix.Login`.

#### 5. Login document
**Files**: `lib/ltix/login.ex`, `lib/ltix/oidc/login_initiation.ex`, `lib/ltix.ex`
**Changes**: `Ltix.Login` is a provider with hook `[Ltix.Step, Ltix.Ordered]` and fields `params`, `private`, `errors`, and `plugins`. The checks `LoginInitiation` performs become default step modules under `Ltix.Login`, with the phase `Ltix.Login.RegistrationFound` after the registration lookup. `handle_login/3` resolves the plugin set, builds the document, runs it, and returns what 0.2 returns. It accepts `plugins:`.

#### 6. Errors
**File**: `lib/ltix/errors/unknown/invalid_plugin_set.ex`
**Changes**: A new error for resolution conflicts, listing each conflict.

#### 7. Docs
**Files**: `guides/upgrading-to-0.3.md` (new), `plans/2026-10-18-plugin-system.md`
**Changes**:
- Start the upgrade guide.
- Amend the spec. "Absent providers" uses `depend_on/2` in place of "the application lists them". The Provider passes `use` options. The plugin struct gains `dependencies`. Providers get the optional `resolve/1`.

### Success Criteria:

#### Automated Verification:
- [ ] Login plugin tests pass: `mix test test/ltix/plugins/login_test.exs`
- [ ] Existing login tests pass: `mix test test/ltix/oidc`
- [ ] Full suite passes: `mix test`
- [ ] `mix precommit` passes

#### Manual Verification:
- [ ] The generated docs for `Ltix.Plugin`, `Ltix.Provider`, `Ltix.Step`, and `Ltix.Ordered` read as a plugin author's reference

---

## Phase 2: Resource Link Launch on `%Ltix.Launch{}`

### Overview

`handle_callback/3` becomes the entry point of the `Ltix.Launch` document. Its security checks become bundled steps, claims are parsed by Core 1.3.0 claim owners through `Ltix.Claims`, roles become URIs, and `LtiResourceLinkRequest` is declared as a message type. `LaunchContext`, `LaunchClaims`, and role parsers are removed.

### Red-Green TDD Test Plan:
1. A resource link launch through `Ltix.Test.launch_params/2` returns `{:ok, %Ltix.Launch{}}` with the fields below. File: `test/ltix_test.exs` and `test/ltix/oidc/*`, ported.
   - `registration` and `deployment` as Ltix structs
   - `source_registration` and `source_deployment` as the host's records
   - `raw` as received, and parsed `claims`
   - `plugins`
2. Every 0.2 security failure (state, issuer, signature, nonce, deployment) returns the same error as in 0.2, and no claim is parsed after a halt.
3. A message whose type no plugin declares is rejected. A resource link launch missing `resource_link` or `roles` reports each as missing. Missing `sub` passes only with `allow_anonymous`.
4. `launch.claims.roles` is the received URI list. `Ltix.Role.instructor?/1` is true for `membership#Instructor`, for an `Instructor#TeachingAssistant` sub-role, and for the simple name `Instructor`.
5. `role_scope_mentor` with IDs and no Mentor role is rejected, and an empty list passes. This is a new rejection against 0.2.
6. `organization` and `actual_user` parse.
7. A malformed `lis` or `context` is left out of `claims` and kept in `raw`, as in 0.2. A malformed optional property, such as `launch_presentation.width` = `"abc"`, becomes `nil`. A malformed `resource_link` fails.
8. An unknown top-level claim stays in `raw`, and an unknown key inside `launch_presentation` goes to its `unrecognized`.

### Changes Required:

#### 1. Launch document
**File**: `lib/ltix/launch.ex`
**Changes**: `%Ltix.Launch{}` has these fields:
- `registration` and `deployment` (`%Ltix.Registration{}`, `%Ltix.Deployment{}`)
- `source_registration` and `source_deployment`
- `claims`, `raw`, `endpoints`, `private`, `errors`, and `plugins`

The provider's hook is `[Ltix.Step, Ltix.Ordered]`. Delete `lib/ltix/launch_context.ex`.

#### 2. Bundled launch steps
**File**: `lib/ltix/launch/` (one module per step)
**Changes**: Split `callback.ex:48-86` into step modules in 0.2's order, with the phases plugins order against between them:
- `CheckErrorResponse`, `ExtractIdToken`, `VerifyState`
- `LookUpRegistration`, `VerifyIdToken`, `VerifyNonceBinding`, `ValidateNonce`
- the phases `Verified` and `ClaimsReceived`
- `ParseClaims`, then the phase `ClaimsParsed`
- `RejectUndeclaredMessageType`, `ValidateMessageType`, then the phase `Validated`
- `LookUpDeployment`, after the claims pass, as 0.2 looked up the deployment

A phase module is a documented step that changes nothing. The other steps have `@moduledoc false`, and each declares its place against the phase modules, and its order among the steps between the same two, with `before?/1` and `after?/1`. `validate_required_lti_claims` (`callback.ex:170-299`) is split three ways:
- Shape rules go to claim owners.
- Rules `Ltix.Validator` can't express, such as `version` being `"1.3.0"`, become claim checks.
- Per-type requirements go to message types.

#### 3. Claim owners and `Ltix.Claims`
**Files**: `lib/ltix/claim.ex`, `lib/ltix/claims.ex`, `lib/ltix/claims/*.ex`
**Changes**:
- **The owner contract.** `Ltix.Claim` is a provider whose extenders implement `Ltix.Property`. An owner declares `claim:` and `name:` as `use` options.
- **Object claims.** These declare `fields:` (a Zoi keyword list, as content item types do in decision 4), and `use` generates the struct with `extensions` and `unrecognized`.
- **Scalar claims.** These implement `parse/2`.
- **The `strict` option.** An owner declared with `strict: false` keeps 0.2's behavior. When its parse fails, the claim is left out of `claims`.
- **Checks.** An owner may define `check/2`, which reads the parsed claims.

`Ltix.Claims` handles these:
- **Resolution.** Its `resolve/1` fails on two owners of one claim URI, two owners of one short name, two owners declaring one `service/0`, and two extenders of one property.
- **Parsing.** It parses every present claim and puts service owners' values into `endpoints`.
- **Checks.** It runs owner checks, added checks, and overrides after all claims are parsed.

The Core 1.3.0 owners cover:
- the OIDC claims
- `message_type`, `version`, `deployment_id`, `target_link_uri`, `resource_link`, `roles`
- `context`, `tool_platform`, `launch_presentation`, `lis`, `custom`, `role_scope_mentor`
- `organization`, `actual_user`

`role_scope_mentor`'s `check/2` uses `Ltix.Role.mentor?/1`. Delete `lib/ltix/launch_claims.ex`, `lib/ltix/launch_claims/*.ex`, and `lib/ltix/launch_claims/parser.ex`.

```elixir
defmodule Ltix.Claims.LaunchPresentation do
  @moduledoc "How the platform displays the tool."

  # [Core §5.4.4](https://www.imsglobal.org/spec/lti/v1p3/#launch-presentation-claim)
  use Ltix.Claim,
    claim: "https://purl.imsglobal.org/spec/lti/claim/launch_presentation",
    name: :launch_presentation,
    strict: false,
    fields: [
      document_target: Zoi.enum(~w(frame iframe window), description: "How the tool is displayed.") |> Zoi.optional(),
      height: Zoi.number(description: "Height of the window or frame.") |> Zoi.optional(),
      width: Zoi.number(description: "Width of the window or frame.") |> Zoi.optional(),
      return_url: Zoi.string(description: "Where to send the user when they're done.") |> Zoi.optional(),
      locale: Zoi.string(description: "The user's locale.") |> Zoi.optional()
    ]
end
```

A property inside another plugin's claim:

```elixir
defmodule Core131.Placement do
  use Ltix.Claims.LaunchPresentation

  @impl true
  def property, do: "placement"

  @impl true
  def parse(placements, _opts) when is_list(placements), do: {:ok, placements}
end
```

#### 4. Roles
**Files**: `lib/ltix/role.ex`
**Changes**: Replace `launch_claims/role.ex` and `role/lis.ex` with a plain `Ltix.Role` module:
- LIS role URI constants for the context, sub-role, institution, system, and LTI system vocabularies, plus the deprecated forms
- predicates over URI lists that cover sub-roles, simple names, and deprecated forms, such as `instructor?/1`, `learner?/1`, `mentor?/1`, `teaching_assistant?/1`, `administrator?/1`, and `context_administrator?/1`
- `has?/2`

Remove `:role_parsers` and `AppConfig.role_parsers!/0`, and update `ltix.ex:271`.

```elixir
Ltix.Role.instructor?(launch.claims.roles)
Ltix.Role.has?(launch.claims.roles, Ltix.Role.teaching_assistant())
```

#### 5. Validator and message types
**Files**: `lib/ltix/validator.ex`, `lib/ltix/validator/condition.ex`, `lib/ltix/validator/contribution.ex`, `lib/ltix/launch/message_type.ex`, `lib/ltix/launch/every_message_type.ex`, `lib/ltix/resource_link_request.ex`
**Changes**:
- **The validator.** `Ltix.Validator` has `new/1`, `required/3`, `optional/3`, `override/3`, `defaults/2`, `option/1`, and `includes/3`. It combines statements as decision 5 describes.
- **Message types and contributions.** `Ltix.Launch.MessageType` makes a module a message type and a provider. `Ltix.Validator.Contribution` is the shared `validator/1` building block.
- **Resolution.** `Ltix.Launch.MessageType.resolve/1` builds every validator once per set. It fails on unknown claim names, two modules declaring one type string, and two overrides of one claim in one type.
- **Docs.** `describe/1` renders a validator as a table for generated docs.

```elixir
defmodule Ltix.ResourceLinkRequest do
  @moduledoc "A user follows a resource link into the tool."

  # [Core §5.3](https://www.imsglobal.org/spec/lti/v1p3/#required-message-claims)
  use Ltix.Launch.MessageType

  @impl true
  def validator do
    new("LtiResourceLinkRequest")
    |> required(:resource_link)
    |> required(:roles)
    |> required(:subject, unless: option(:allow_anonymous))
  end
end
```

#### 6. Core plugin
**File**: `lib/ltix/core.ex`
**Changes**: This plugin provides `Ltix.Launch`, `Ltix.Claim`, `Ltix.Launch.MessageType`, `Ltix.Launch.EveryMessageType`, and `Ltix.ResourceLinkRequest`, and it extends the launch steps and Core claim owners. `Ltix.Bundled` depends on it.

#### 7. Entry point and test helpers
**Files**: `lib/ltix.ex`, `lib/ltix/oidc/callback.ex`, `lib/ltix/test.ex`
**Changes**:
- `handle_callback/3` returns `{:ok, %Ltix.Launch{}}` and accepts `plugins:`, and `:claim_parsers` and `:role_parsers` are removed from its options.
- `Ltix.Test.build_launch_context/2` becomes `build_launch/2`, which runs `Ltix.Claims` and the validators with no security steps.
- `valid_lti_claims/2` and `launch_params/2` keep their shape.
- Remove the global-env parser tests (`test/ltix/launch_claims_config_test.exs`).

#### 8. Docs
**Files**: `guides/working-with-roles.md`, `guides/getting-started.md`, `guides/concepts.md`, `guides/upgrading-to-0.3.md`, `plans/2026-10-18-plugin-system.md`
**Changes**:
- Rewrite the roles guide for URIs.
- Update launch examples to `%Ltix.Launch{}`.
- Add the upgrade guide's launch and roles sections.
- Amend the spec:
  - The Launch table gains `endpoints`.
  - The role parser row becomes "removed, roles are URIs".
  - The claim parser row becomes "a claim owner extending `Ltix.Claim`".

### Success Criteria:

#### Automated Verification:
- [ ] Launch tests pass: `mix test test/ltix_test.exs test/ltix/oidc test/ltix/claims`
- [ ] Full suite passes: `mix test`
- [ ] No reference to `LaunchContext`, `LaunchClaims`, `role_parsers`, or `claim_parsers` remains in `lib/`: `grep -rn "LaunchContext\|LaunchClaims\|role_parsers\|claim_parsers" lib` returns nothing
- [ ] `mix precommit` passes

#### Manual Verification:
- [ ] The moduledocs of `Ltix.ResourceLinkRequest` and a claim owner read like the spec's tables
- [ ] `guides/working-with-roles.md` reads clearly to someone who hasn't read the LTI spec

---

## Phase 3: Plugins Extend Launches

### Overview

This phase proves every launch extension point against test-only plugins through `handle_callback/3`, and replaces the parser guides with a plugin author guide.

### Red-Green TDD Test Plan:
All tests live in `test/ltix/plugins/launch_test.exs`, with plugins in `test/support/plugins/`.
1. A vendor plugin owns `https://vendor.example.com/session`, and `launch.claims.session` is parsed.
2. A property extender of `Ltix.Claims.LaunchPresentation` parses `placement` into `extensions`. Without it, `placement` is in `unrecognized`.
3. A claim check scoped to one message type runs only there. An unscoped check runs in every type. Every check must pass.
4. An override of `Ltix.Claims.RoleScopeMentor`'s check within a test message type accepts a mentor list without the Mentor role in that type, and resource link launches still reject it.
5. A contribution `use Ltix.ResourceLinkRequest` requires `:context`. A contribution with `when: includes(...)` requires a claim only when the condition holds. A condition module named directly works.
6. `use Ltix.Launch.EveryMessageType` with `defaults(required: [...])` applies to unstated claims and leaves a type's `optional` statements alone.
7. `override(validator, :roles, :optional)` loosens `roles`, and a later contribution's `required(:roles)` doesn't undo it.
8. A test plugin declares `LtiTestRequest`, and it is accepted.
9. Each of these returns `InvalidPluginSet` naming both parties:
   - two owners of one claim, of one short name, or of one `service/0`
   - two extenders of one claim property
   - two overrides of one check, or of one validator claim, in one type
   - two modules declaring one message type string
   - an unknown claim name in a validator
10. A launch step ordered after `Ltix.Launch.Verified` and before `Ltix.Launch.ClaimsReceived` can rewrite `raw` and write `claims`, and one ordered after `Ltix.Launch.ClaimsParsed` reads parsed claims.

### Changes Required:

#### 1. Added checks and check overrides
**Files**: `lib/ltix/claims/check.ex`, `lib/ltix/claims/override.ex`
**Changes**:
- **Added checks.** `Ltix.Claims.Check` is a provider. An added check declares `claim:` and `message_types:` (a list or `:all`) as `use` options and implements `check/2`.
- **Overrides.** `Ltix.Claims.Override` names the check it replaces with `check:` and the message types with `message_types:`, and implements `check/2`.
- **Listing.** `Ltix.Claims.overrides/1` lists the overrides in a plugin set.

```elixir
defmodule Lti1p4.MentorWithoutRole do
  use Ltix.Claims.Override, check: Ltix.Claims.RoleScopeMentor, message_types: ["LtiFutureRequest"]

  @impl true
  def check(_ids, _claims), do: :ok
end
```

#### 2. Contributions
**File**: `lib/ltix/validator/contribution.ex`
**Changes**: Every message type is a provider. A module that extends several types writes one `validator/1` clause per type.

```elixir
defmodule Vendor.Tenant do
  use Ltix.ResourceLinkRequest
  use Ltix.DeepLinkingRequest

  @impl true
  def validator(%{message_type: "LtiResourceLinkRequest"} = validator), do: required(validator, :context)
  def validator(%{message_type: "LtiDeepLinkingRequest"} = validator), do: optional(validator, :context)
end
```

#### 3. Docs
**Files**: `guides/writing-plugins.md` (new), `guides/custom-claim-parsers.md` and `guides/custom-role-parsers.md` (delete), `guides/upgrading-to-0.3.md`, `plans/2026-10-18-plugin-system.md`, `mix.exs` (guide list)
**Changes**:
- **The plugin author guide** covers manifests, dependencies, profiles, steps and ordering, claim owners, claim properties, checks and overrides, message types and contributions, and resolution errors.
- **The spec** amends "No overrides" to allow explicit scoped check overrides beside the rule against replacing providers. "No provider collisions" gains claim and property ownership failing at resolution.

### Success Criteria:

#### Automated Verification:
- [ ] Plugin launch tests pass: `mix test test/ltix/plugins/launch_test.exs`
- [ ] Full suite passes: `mix test`
- [ ] `mix precommit` passes

#### Manual Verification:
- [ ] `guides/writing-plugins.md` is enough for someone new to Ltix to write a plugin for a specification it doesn't support

---

## Phase 4: OAuth and NRPS

### Overview

Token requests become the `Ltix.ClientAssertion` document, endpoints come from message documents, the OAuth client keeps its plugin set, and NRPS members and containers become types. `Ltix.AdvantageService` is removed.

### Red-Green TDD Test Plan:
1. `authenticate(launch, services: [Ltix.MembershipsService])` reads `launch.endpoints` and requests the NRPS scope. A launch without the NRPS claim returns `ServiceNotAvailable`. File: `test/ltix/oauth_test.exs`, ported.
2. The registration form with explicit `endpoints:` validates them through the endpoint type and requests the same scopes.
3. A test-only client assertion extender adds a tenant claim. The first token, a refresh, and the registration form all include it. A client authenticated from a launch keeps that launch's plugin set, and `plugins:` on a call replaces it.
4. `list_members/2` and `stream_members/2` parse members with a test-only member property into `extensions`, and unclaimed keys into `unrecognized`. File: `test/ltix/memberships_service_test.exs`, ported.
5. A member's `message` is parsed through `Ltix.Claims` with the client's plugin set. It gets claim checks scoped to its `message_type` and no required-claim validation, so a member message with only `custom` passes.
6. The role filter accepts a URI or an `Ltix.Role` constant, and member roles are URIs.
7. The pagination and service collection failure tests pass unchanged.

### Changes Required:

#### 1. Endpoint owners
**Files**: `lib/ltix/memberships_service/endpoint.ex`, `lib/ltix/memberships_service/claim.ex`
**Changes**: The NRPS endpoint claim owner declares `service/0` returning `Ltix.MembershipsService`. Endpoint validation moves into the endpoint type's `new/1`. Delete `launch_claims/memberships_endpoint.ex`.

#### 2. Client assertion
**Files**: `lib/ltix/client_assertion.ex`, `lib/ltix/oauth.ex`, `lib/ltix/oauth/client.ex`, `lib/ltix/oauth/client_credentials.ex`
**Changes**:
- `Ltix.ClientAssertion` is a provider with hook `[Ltix.Step, Ltix.Ordered]` and fields `endpoints`, `scopes`, `claims`, and `errors`.
- `authenticate/2` takes `services:` from a launch, or `endpoints:` for the registration form. It reports missing services before running the document, then signs the claims and requests the deduplicated scopes.
- `%Ltix.OAuth.Client{}` gains `plugins`, and `force_refresh/1` rebuilds the document with it.
- Delete `lib/ltix/advantage_service.ex` and `advantage_service/operation.ex`, after moving what services still need into private helpers.

```elixir
defmodule Ltix.MembershipsService.Token do
  use Ltix.ClientAssertion

  def call(%{endpoints: %{Ltix.MembershipsService => _}} = doc, _opts),
    do: {:ok, update_in(doc.scopes, &(&1 ++ ["https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"]))}

  def call(doc, _opts), do: {:ok, doc}
end
```

#### 3. Member types
**Files**: `lib/ltix/memberships_service/member.ex`, `lib/ltix/memberships_service/membership_container.ex`, `lib/ltix/property.ex`
**Changes**:
- `Ltix.Property` has `property/0`, `parse/2`, `serialize/2`, and `writes/0`, with pass-through defaults declared once.
- `Member` and `MembershipContainer` are provider types with named fields, `extensions`, and `unrecognized`.
- `message` runs `Ltix.Claims` directly with the client's plugin set.
- `roles` are URIs, and `unrecognized_roles` is removed.

#### 4. NRPS plugin
**File**: `lib/ltix/memberships_service.ex`
**Changes**: The service module implements `Ltix.Plugin`. It provides `Ltix.MembershipsService`, `Member`, and `MembershipContainer`, and extends the endpoint owner and token extender. `Ltix.Bundled` depends on it.

#### 5. Test helpers and docs
**Files**: `lib/ltix/test.ex`, `lib/ltix/test/service_stub.ex`, `guides/advantage-services.md`, `guides/memberships-service.md`, `guides/cookbooks/custom-advantage-service.md`, `guides/cookbooks/persisting-service-endpoints.md`, `guides/upgrading-to-0.3.md`
**Changes**: Stubs build members from the new types. The custom service cookbook becomes a service plugin built from an endpoint owner and a token extender.

### Success Criteria:

#### Automated Verification:
- [ ] OAuth and NRPS tests pass: `mix test test/ltix/oauth_test.exs test/ltix/oauth test/ltix/memberships_service_test.exs test/ltix/memberships_service test/ltix/memberships_member_payload_test.exs test/ltix/memberships_message_claims_test.exs`
- [ ] Full suite passes: `mix test`
- [ ] `grep -rn "AdvantageService" lib guides` returns nothing
- [ ] `mix precommit` passes

#### Manual Verification:
- [ ] The rewritten custom service cookbook reads as a complete example of a service plugin

---

## Phase 5: AGS

### Overview

The AGS endpoint owner fills `endpoints`, and `LineItem`, `Score`, and `Result` become types with property extenders and `writes/0`. `Ltix.Extensions` is removed.

### Red-Green TDD Test Plan:
1. `authenticate(launch, services: [Ltix.GradeService])` requests the endpoint claim's `scope` array. File: `test/ltix/grade_service_test.exs`, ported.
2. A test-only create-only property (`writes: [:create]`) is sent on `create_line_item/2` and left out of `update_line_item/2` after a GET.
3. A test-only read-only property (`writes: []`) is parsed on GET and never sent.
4. An unclaimed property read on GET is sent back unchanged on PUT.
5. A test-only score property is serialized on `post_score/3`, and a result property is parsed by `list_results/2`.
6. `get_line_item/2` through a client authenticated from a launch parses a property whose plugin only that launch listed.

### Changes Required:

#### 1. Endpoint owner
**Files**: `lib/ltix/grade_service/endpoint.ex`, `lib/ltix/grade_service/claim.ex`
**Changes**: The AGS endpoint claim owner declares `service/0` returning `Ltix.GradeService`, and validation moves into the endpoint type. A token extender adds the endpoint's `scope` array. Delete `launch_claims/ags_endpoint.ex`.

#### 2. Types
**Files**: `lib/ltix/grade_service/line_item.ex`, `score.ex`, `result.ex`
**Changes**: Each is a provider type with named fields, `extensions`, and `unrecognized`. `LineItem.to_json/3` takes the extenders and the operation, and leaves out properties whose `writes/0` excludes it. `create_line_item/2` passes `:create` and `update_line_item/2` passes `:update`. Delete `lib/ltix/extensions.ex`.

```elixir
defmodule Canvas.SubmissionType do
  use Ltix.GradeService.LineItem

  @impl true
  def property, do: "https://canvas.instructure.com/lti/submission_type"

  @impl true
  def writes, do: [:create]
end
```

#### 3. AGS plugin
**File**: `lib/ltix/grade_service.ex`
**Changes**: The service module implements `Ltix.Plugin`. It provides `Ltix.GradeService`, `LineItem`, `Score`, and `Result`, and extends the endpoint owner and token extender. `Ltix.Bundled` depends on it.

#### 4. Test helpers and docs
**Files**: `lib/ltix/test.ex`, `guides/grade-service.md`, `guides/cookbooks/canvas-grade-extensions.md`, `guides/cookbooks/background-grade-sync.md`, `guides/upgrading-to-0.3.md`
**Changes**: The Canvas cookbook becomes a Canvas plugin with `Canvas.SubmissionType` and `Canvas.LaunchUrl`.

### Success Criteria:

#### Automated Verification:
- [ ] AGS tests pass: `mix test test/ltix/grade_service_test.exs test/ltix/grade_service`
- [ ] Full suite passes: `mix test`
- [ ] `grep -rn "Ltix.Extensions" lib guides` returns nothing
- [ ] `mix precommit` passes

#### Manual Verification:
- [ ] The Canvas cookbook reads as a complete example of a vendor plugin

---

## Phase 6: Deep Linking

### Overview

Deep Linking becomes a bundled plugin with its message type, settings owner, content item types, its own line item type, and the response document. The `ContentItem` protocol and plain-map items are removed.

### Red-Green TDD Test Plan:
1. A Deep Linking launch is accepted without `resource_link` or `roles` and rejected without `deep_linking_settings`. File: `test/ltix/deep_linking_test.exs` and `test/ltix/deep_linking/*`, ported.
2. `build_response/3` with each bundled type produces 0.2's JWT claims. Each of these is reported: an unaccepted presentation target, a media type outside `accept_media_types`, a line item when `accept_lineitem` is false, a type outside `accept_types`, and too many items.
3. A test-only content item type is accepted when listed in `accept_types` and gets the presentation target check without writing one.
4. A plain map is rejected as an undeclared type.
5. A test-only property on `ltiResourceLink` is serialized into the item.
6. One test-only module extending both `Ltix.GradeService.LineItem` and `Ltix.DeepLinking.LineItem` writes its property in both places.
7. A `%Ltix.GradeService.LineItem{}` passed to `LTIResourceLink.new/1` handles extensions this way:
   - Its five shared fields are copied.
   - Setting `end_date_time` is an error.
   - A property whose extender extends both types carries over, and one that extends only AGS is an error.
8. Two modules declaring one content item type string fail at resolution.
9. `new/1` rejects a missing required field and an unknown one. Caller-chosen keys in `custom` aren't camelized.
10. A test-only step extending `Ltix.DeepLinking.Response` adds a claim to the response JWT.

### Changes Required:

#### 1. Message type and settings owner
**Files**: `lib/ltix/deep_linking_request.ex`, `lib/ltix/deep_linking/settings.ex`
**Changes**: `Ltix.DeepLinkingRequest` requires `deep_linking_settings` and states `roles` as optional. The settings owner is strict. Delete `launch_claims/deep_linking_settings.ex`.

```elixir
defmodule Ltix.DeepLinkingRequest do
  @moduledoc "A user asks the tool for content to place."

  # [DL §4.4](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-request-message)
  use Ltix.Launch.MessageType

  @impl true
  def validator do
    new("LtiDeepLinkingRequest")
    |> required(:deep_linking_settings)
    |> optional(:roles)
  end
end
```

#### 2. Content item types
**Files**: `lib/ltix/deep_linking/content_item_type.ex`, `lib/ltix/deep_linking/content_item/fields.ex`, `lib/ltix/deep_linking/content_item/{link,lti_resource_link,file,image,html_fragment}.ex`
**Changes**: `use Ltix.DeepLinking.ContentItemType, type:, fields:` generates the type (decision 4). Shared field helpers replace `content_item_helpers.ex`. `File` checks media types, and `LTIResourceLink` checks `accept_lineitem`. Delete `content_item.ex`, the protocol, and its `Map` impl.

```elixir
defmodule Ltix.DeepLinking.ContentItem.File do
  @moduledoc "A file the platform downloads or links to."

  # [DL §3.3](https://www.imsglobal.org/spec/lti-dl/v2p0/#file)
  use Ltix.DeepLinking.ContentItemType,
    type: "file",
    fields: [
      url: Zoi.string(description: "URL of the file."),
      title: title(),
      text: text(),
      icon: icon(),
      media_type: Zoi.string(description: "Media type of the file, such as `image/png`.") |> Zoi.optional()
    ]

  # `accept_media_types` "only applies to File types" (DL §4.4.1)
  @impl true
  def check(%{media_type: media_type}, %{accept_media_types: accepted}) do
    if Ltix.MediaType.accepted?(media_type, accepted), do: :ok, else: {:error, {:media_type_not_accepted, media_type}}
  end
end
```

#### 3. Deep Linking line item
**File**: `lib/ltix/deep_linking/line_item.ex`
**Changes**: This is a provider type with `label` (optional), `score_maximum`, `resource_id`, `tag`, and `grades_released`. It serializes extenders as `:create`. `new/1` accepts a `%Ltix.GradeService.LineItem{}` (decision 7).

#### 4. Response document
**Files**: `lib/ltix/deep_linking/response.ex`, `lib/ltix/deep_linking.ex`
**Changes**: `Ltix.DeepLinking.Response` is a provider with hook `[Ltix.Step, Ltix.Ordered]`. `build_response/3` builds and checks the items, builds the claims, runs the response's extenders, and signs through the storage adapter as in 0.2. Its `resolve/1` fails on duplicate type strings and duplicate property owners.

#### 5. Deep Linking plugin
**File**: `lib/ltix/deep_linking/plugin.ex`
**Changes**: This plugin provides:
- `Ltix.DeepLinkingRequest` and `Ltix.DeepLinking.Response`
- `Ltix.DeepLinking.ContentItemType` and the five types
- `Ltix.DeepLinking.LineItem`

It extends the settings owner. `Ltix.Bundled` depends on it.

#### 6. Test helpers and docs
**Files**: `lib/ltix/test.ex`, `test/support/custom_content_item.ex`, `guides/deep-linking.md`, `guides/cookbooks/building-content-items.md`, `guides/upgrading-to-0.3.md`, `plans/2026-10-18-plugin-system.md`
**Changes**:
- The content item cookbook shows a custom type in place of a plain map.
- Finish the upgrade guide.
- Mark the spec's "Not Yet Decided" bundled contracts as decided, pointing to this plan's decisions.

### Success Criteria:

#### Automated Verification:
- [ ] Deep Linking tests pass: `mix test test/ltix/deep_linking_test.exs test/ltix/deep_linking`
- [ ] Full suite passes: `mix test`
- [ ] `grep -rn "defimpl Ltix.DeepLinking.ContentItem\|ContentItemHelpers" lib` returns nothing
- [ ] `mix precommit` passes

#### Manual Verification:
- [ ] The generated docs for each bundled content item type list their options in field order, with no internal fields
- [ ] `guides/upgrading-to-0.3.md` lets a 0.2 app upgrade without reading this plan

---

## Mechanisms Proven in the Planning Spikes

The planning spikes ran each design as a standalone `.exs` file with no warnings. These are the mechanisms they proved, and the pitfalls they hit, so the implementation doesn't have to rediscover them.

### Finding a provider's extenders

`use SomeProvider` records the provider in a persisted `@ltix_extends` attribute, which accumulates. Resolution reads it back from each extender entry. A module listed by several plugins counts once, which is what "the same module listed twice is one owner" relies on (decision 10).

```elixir
def extenders(set, provider),
  do: for({mod, _opts} <- set.extenders, {:ltix_extends, [^provider]} <- mod.module_info(:attributes), uniq: true, do: mod)
```

### Building blocks with defaults

A building block declares its behaviour and defaults once per module through `Ltix.Hook.declare_once/2`, so a module extending two providers that share a block gets one copy. `Ltix.Property` works this way.

```elixir
defmodule Ltix.Property do
  @callback property() :: String.t()
  @callback parse(json :: term, opts :: keyword) :: {:ok, term} | {:error, term}
  @callback serialize(value :: term, opts :: keyword) :: term
  @callback writes() :: [:create | :update]

  defmacro __using__(_opts) do
    quote do
      require Ltix.Hook

      Ltix.Hook.declare_once Ltix.Property do
        def parse(json, _opts), do: {:ok, json}
        def serialize(value, _opts), do: value
        def writes, do: [:create, :update]
        defoverridable parse: 2, serialize: 2, writes: 0
      end
    end
  end
end
```

**Pitfall.** An `import` inside the `declare_once` block only applies inside that block, because the block is the body of an `unless`. A block that needs to import a module for the extender, as `Ltix.Validator.Contribution` imports `Ltix.Validator`, puts the `import` after the `declare_once` call.

```elixir
defmodule Ltix.Validator.Contribution do
  @callback validator(Ltix.Validator.t()) :: Ltix.Validator.t()

  defmacro __using__(_opts) do
    quote do
      require Ltix.Hook
      Ltix.Hook.declare_once(Ltix.Validator.Contribution, do: nil)
      import Ltix.Validator
    end
  end
end
```

### Modules that become providers when they `use` something

Message types and content item types are each written by `use`-ing one module, and the result is itself a provider that other plugins extend (`use Ltix.DeepLinkingRequest`, `use Ltix.DeepLinking.ContentItem.LTIResourceLink`). This works without new machinery. `Ltix.Launch.MessageType` is a provider whose hook is a building block that itself calls `use Ltix.Provider`.

```elixir
# The hook block. It runs inside the message type module.
defmodule Ltix.Launch.MessageType.Definition do
  defmacro __using__(_opts) do
    quote do
      use Ltix.Provider, hook: [Ltix.Validator.Contribution]
      import Ltix.Validator
    end
  end
end

defmodule Ltix.Launch.MessageType do
  use Ltix.Provider, hook: [Ltix.Launch.MessageType.Definition]
  @callback validator() :: Ltix.Validator.t()
end

defmodule Ltix.Launch.EveryMessageType do
  use Ltix.Provider, hook: [Ltix.Validator.Contribution]
end
```

A module that extends two message types ends up with one behaviour, `Ltix.Validator.Contribution`, and no conflicting-behaviours warning. Contributions to a message type that isn't in the plugin set are ignored, so an Asset Processor-like plugin loaded without Deep Linking builds only the types that are present.

`Ltix.DeepLinking.ContentItemType` and `Ltix.Claim` use the same pattern, and their hook block reads the `use` options that `Ltix.Provider` now passes through. The struct part is quoted with `unquote: false`, because it unquotes values computed from `@schema` inside the type module.

```elixir
defmodule Ltix.DeepLinking.ContentItemType.Definition do
  defmacro __using__(opts) do
    definition =
      quote do
        use Ltix.Provider, hook: [Ltix.Property]
        import Ltix.DeepLinking.ContentItem.Fields
        @schema Ltix.DeepLinking.ContentItem.Fields.struct_schema(__MODULE__, unquote(opts[:type]), unquote(opts[:fields]))
      end

    struct =
      quote unquote: false do
        @type t :: unquote(Zoi.type_spec(@schema))
        @enforce_keys Zoi.Struct.enforce_keys(@schema)
        defstruct Zoi.Struct.struct_fields(@schema) ++ [extensions: %{}]

        @impl true
        def schema, do: @schema

        def new(fields), do: Ltix.DeepLinking.ContentItem.new(__MODULE__, fields)
      end

    [definition, struct]
  end
end

defmodule Ltix.DeepLinking.ContentItemType do
  use Ltix.Provider, hook: [Ltix.DeepLinking.ContentItemType.Definition]
  @callback schema() :: Zoi.schema()
  @callback check(item :: struct, settings :: map) :: :ok | {:error, term}
  @optional_callbacks check: 2
end
```

The spike's version still lacks four pieces decision 4 adds:
- overridable `new/1` and `new!/1`
- the moduledoc options section, which respects `@moduledoc false`
- the documented API for the type string and fields
- the per-field JSON key override

### Zoi pitfalls

- **Field order.** `Zoi.struct(module, fields)` with a keyword list treats the list as options. Passing non-empty options makes it read the fields, and keeps their order in `Zoi.describe/1`. The spike's schema is shown below. The type string goes in `metadata:`, not in a custom option.

  ```elixir
  Zoi.struct(module, fields, metadata: [content_item_type: type], coerce: true, unrecognized_keys: :error, empty_values: [nil])
  ```

- **Nested keyword values.** `Zoi.map` rejects nested keyword lists. 0.2 lets callers pass `window: [width: 400]`, so `new/1` converts non-empty nested keyword lists to maps before parsing.
- **`extensions` and `unrecognized`.** These are struct fields outside the schema. Otherwise they show up as `new/1` options and in the generated docs. Extension values go in through `put_extension/3`, and `new/1` rejects `extensions:`.
- **`Zoi.extend` is unusable for combining plugins.** It drops refinements, replaces an existing field silently, and raises on string keys.

### Serializing types

Standard fields are camelized, then each extender's property is merged in, then `type` for content items. Unclaimed properties are merged first, so claimed and standard keys win.

```elixir
def to_json(%module{extensions: extensions} = item, extenders) do
  standard = for {field, value} <- Map.from_struct(item), field != :extensions, value != nil, into: %{}, do: {camelize(field), json(value)}
  properties = for extender <- extenders, {:ok, value} <- [Map.fetch(extensions, extender)], into: %{}, do: {extender.property(), extender.serialize(value, [])}
  standard |> Map.merge(properties) |> Map.put("type", type(module))
end
```

**Pitfall.** The spike camelized every nested atom key, which would mangle `ltiResourceLink`'s `custom` map. Caller-chosen keys must be left alone, as 0.2 does. Only declared fields and the nested shapes Ltix defines, such as `window` and `iframe`, are camelized.

For line items, `to_json/3` also takes the operation and keeps only extenders whose `writes/0` includes it:

```elixir
properties =
  for extender <- extenders,
      operation in extender.writes(),
      {:ok, value} <- [Map.fetch(item.extensions, extender)],
      into: %{},
      do: {extender.property(), extender.serialize(value, [])}
```

### Parsing types and claim objects

Parsing splits the JSON into standard fields, properties some extender claims, and everything else.

```elixir
{standard, rest} = Map.split(json, @standard_keys)
claimed = Map.new(extenders, &{&1.property(), &1})
{known, unrecognized} = Map.split(rest, Map.keys(claimed))
extensions = Map.new(known, fn {key, value} -> {:ok, parsed} = claimed[key].parse(value, []); {claimed[key], parsed} end)
```

The implementation reports an extender's `{:error, reason}` instead of matching `{:ok, _}`.

### The validator

A statement is `{claim, disposition, condition, source}`. `source` is the module that made the statement. Each contribution's statements are tagged with it as they're applied, so `describe/1` and override conflicts can name modules. `unless:` stores `{:not, condition}`. A bare module is a condition with `[]` arguments.

The effective disposition of a claim is computed from all statements at once, so plugin order never matters:

```elixir
def disposition(validator, claim, claims, opts) do
  applying = for {^claim, d, c, _source} <- validator.statements, met?(c, claims, opts), do: d

  case for({^claim, d, _c, _source} <- validator.overrides, do: d) do
    [d | _] -> d
    [] -> if(:required in applying, do: :required, else: List.first(applying) || validator.defaults[claim])
  end
end

def missing(validator, claims, opts) do
  named = Enum.uniq(for({c, _, _, _} <- validator.statements ++ validator.overrides, do: c) ++ Map.keys(validator.defaults))
  for claim <- named, disposition(validator, claim, claims, opts) == :required, not Map.has_key?(claims, claim), do: claim
end

defp met?(nil, _claims, _opts), do: true
defp met?({:not, c}, claims, opts), do: not met?(c, claims, opts)
defp met?({module, args}, claims, opts), do: module.met?(args, claims, opts)
defp met?(module, claims, opts) when is_atom(module), do: module.met?([], claims, opts)
```

`defaults/2` only fills claims no statement mentions. `missing/3` reads the parsed `claims`, and presence means the claim's short name is a key there. When an owner declared with `strict: false` leaves a malformed claim out (decision 17), the claim counts as missing if its type requires it. 0.2 does the same for required claims, because the claims it parses through `ClaimHelpers.optional` are the ones Core never requires.

Building validators for a plugin set applies the type's own `validator/0`, then each contribution, both from the type's extenders and from `Ltix.Launch.EveryMessageType`. It then checks unknown claim names against the owners' `name/0`, and two overrides of one claim in one type.

```elixir
for type <- extenders(set, Ltix.Launch.MessageType), into: %{} do
  own = Ltix.Validator.tag(type.validator(), type)

  validator =
    for c <- extenders(set, type) ++ extenders(set, Ltix.Launch.EveryMessageType), reduce: own do
      v -> Ltix.Validator.tag(c.validator(v), c)
    end

  {validator.message_type, validator}
end
```

### Claim checks and overrides

- **When checks run.** Checks run only for claims present in `claims`, after every claim is parsed, so a check that reads another claim needs no ordering.
- **Choosing the check.** For each owned claim present, the check that runs is the override registered for `{message_type, check}` when there is one, otherwise the original.
- **Added checks.** Added checks run when their `message_types` is `:all` or includes the message's type.
- **NRPS member messages.** These carry `message_type` `LtiResourceLinkRequest`, so checks scoped to that type apply to them, while validators never do (decision 3).

### Dependency expansion

Resolution walks dependencies depth first. It tracks the current path to detect cycles and keeps a done list so each plugin module appears once. Top-level listings keep the app's order, and each plugin's dependencies land before it. Options come only from the app's listing, and an unlisted dependency gets `[]`.

```elixir
defp expand([], _opts, _path, done), do: {:ok, Enum.reverse(done)}

defp expand([mod | rest], opts, path, done) do
  cond do
    mod in done -> expand(rest, opts, path, done)
    mod in path -> {:error, {:dependency_cycle, Enum.reverse([mod | path])}}
    true ->
      deps = mod.plugin(Map.get(opts, mod, [])).dependencies

      with {:ok, done} <- expand(deps, opts, [mod | path], done) |> reorder() do
        expand(rest, opts, path, [mod | done])
      end
  end
end
```

`expand/4` returns `done` oldest first, and `reorder/1` flips it back to newest first for the recursion. The implementation can keep one order throughout.

### Endpoints and token requests

- **Missing services.** `authenticate/2` checks requested services against the message's `endpoints` before building the assertion. That way a missing service is reported before anything is signed.
- **Same scopes everywhere.** The assertion document starts with only the requested endpoints, so every extender sees them, and none needs `after?/1`. The first token, the registration form, and a refresh then all produce the same scopes. An earlier variant resolved endpoints inside the services' own extenders. In that variant, a vendor extender listed before AGS silently dropped its scope from the first token but not from refreshes.

### Deep Linking checks

- **Presentation targets.** The check covers `~w(window iframe embed)` on every item.
- **Media types.** `Ltix.MediaType.accepted?/2` passes when either side is `nil`, and matches the exact type, `type/*`, or `*/*` against the comma-separated `accept_media_types`.
- **Error positions.** `build/3` tags each error with the item's index.

---

## Testing Strategy

### End-to-End Tests:
- Every behavior is tested through a public entry point: `handle_login/3`, `handle_callback/3`, `authenticate/2`, the service calls, or `build_response/3`.
- Test-only plugins in `test/support/plugins/` cover each extension point and each resolution failure.
- Existing 0.2 tests are ported, not deleted, unless they test a removed extension point.
- Tests that changed global `Application` env for parsers are removed with the parsers. Plugin tests pass `plugins:` at the call, so they can run async.

### Doctests:
- `Ltix.Role` predicates and constants
- `Ltix.Validator` builders and `describe/1`
- `Ltix.Plugin` builders
- `get_extension/2` and `put_extension/3` on each type
- content item `new/1`

## Spec References
- [Core §5.3](https://www.imsglobal.org/spec/lti/v1p3/#required-message-claims), required message claims
- [Core §5.3.7](https://www.imsglobal.org/spec/lti/v1p3/#roles-claim), roles
- [Core §5.4.3](https://www.imsglobal.org/spec/lti/v1p3/#role-scope-mentor-claim), `role_scope_mentor`
- [Core §6.1](https://www.imsglobal.org/spec/lti/v1p3/#services-exposed-as-additional-claims), service claims
- [Sec §4.1.1](https://www.imsglobal.org/spec/security/v1p0/#using-json-web-tokens-with-oauth-2-0-client-credentials-grant), token requests
- [AGS §3.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#assignment-and-grade-service-claim), AGS claim and scopes
- [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings), deep linking settings

## References
- Spec: `plans/2026-10-18-plugin-system.md`, whose "Spike for Hooks" section has the building blocks this plan starts from
- Specs: `specs/lti-core-v1p3.md`, `specs/lti-dl-v2p0.md`, `specs/lti-ags-v2p0.md`, `specs/lti-nrps-v2p0.md`, `specs/security-v1p0.md`
- Core 1.3.0 Final, which the bundled Core plugin follows and `specs/lti-core-v1p3.md` predates. Copy it into `specs/` in Phase 2.
