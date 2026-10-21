# Plugin System Specification

## Overview

Ltix becomes a plugin system. A plugin is a module that declares what it provides and what it extends. Ltix's own functionality ships as bundled plugins that go through the same mechanism as third-party plugins.

The plugin system replaces every 0.2 extension point that a library would use to add to Ltix. These are claim parsers (`Ltix.LaunchClaims.Parser`, `:claim_parsers`), `Ltix.AdvantageService`, the `Ltix.DeepLinking.ContentItem` protocol, and the `extensions:` option on scores, line items, and content items (`Ltix.Extensions`). Role parsers (`Ltix.LaunchClaims.Role.Parser`, `:role_parsers`) are removed with no replacement. Roles are the URIs the platform sent, checked with `Ltix.Role`. Core requires a non-empty `roles` list to include a role from a standard role vocabulary, so a platform that sends its own roles also sends a standard role.

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

A plugin is a behaviour module with one callback. The callback takes the plugin's options and returns a `%Ltix.Plugin{}`, or a keyword list that Ltix turns into one.

```elixir
defmodule Lti1p4 do
  @behaviour Ltix.Plugin

  @impl true
  def plugin(_opts) do
    Ltix.Plugin.new(name: "LTI 1.4", version: "1.0")
    |> Ltix.Plugin.extend(Lti1p4.Launch)
    |> Ltix.Plugin.provide(Lti1p4.MCP)
  end
end
```

- `Ltix.Plugin.new/1` takes `name:` and `version:`. They describe the plugin for people, in error messages and telemetry, and nothing in Ltix keys on them.
- `Ltix.Plugin.provide/2` takes the plugin struct and a provider module.
- `Ltix.Plugin.extend/2` takes the plugin struct and an extender as `Module` or `{Module, opts}`. The targets come from the providers the module `use`s, so the plugin never names them. The plugin can build the extender's options from its own, as in `extend(plugin, {AshLti.Claims, resource: opts[:resource]})`.
- A plugin is listed as `Module` or `{Module, opts}`. The options are passed to the callback, so a plugin's manifest can depend on them. A plugin that needs several configurations takes a list in its options and adds one extender entry for each.
- Each listing adds its own extender entries, and each entry runs with its own options. The providers in a plugin set are a set of modules, so a plugin listed twice provides each module once.

The manifest is readable without running any document. Ltix reads it to collect a plugin set's providers and extenders. Providers read it for data that applies outside a call, such as the message types and scopes in a Dynamic Registration request, the notice types for PNS handler registration, and the content item types checked against `accept_types`.

## Registration

- Ltix's bundled plugins always load. No option removes them. They come first in plugin order, before configured and call-site plugins.
- `config :ltix, plugins: [...]` sets the plugins for every call.
- `plugins:` at a call replaces the configured list.
- When a call is given a `%Ltix.Launch{}`, `plugins:` defaults to the launch's `plugins` field. Passing `plugins:` replaces it.
- A call without a launch, such as a background job using stored endpoints, uses its `plugins:` option, or the configured list when the option is absent.

## Documents

A document is the state of one call into Ltix that several specifications or vendors add to. Plugins' steps run over it in order, any step can halt it, and the caller gets it back.

| Document | Created by | Notes |
|---|---|---|
| Login | Login initiation | Platform storage adds parameters and keeps state in the platform's frame |
| Launch | The authentication response | `%Ltix.Launch{}` |
| Notice | Each notice in a PNS envelope | One document per notice. The envelope is not a document. A notice is not a launch |
| Tool message | Building a tool-signed message | The Deep Linking response and Proctoring Start Assessment |
| Content item | Building one content item | One document per item, inside a tool message |
| Service resource | One service request or response body | Line items, scores, results, ACS requests, and Dynamic Registration payloads. Each specification defines its resource types the way it defines message types |
| Client assertion | Requesting an access token | Specifications and vendors add claims and scopes |

Browser postMessages are not documents, because nothing in the browser calls into Ltix.

Login and launch are separate HTTP requests. Data from login is available to the launch the same way as in 0.2. Login returns `state`, the application stores it in its session and passes it to the callback, and the launch checks it and the nonce derived from it and the registration.

The bundled plugins provide these documents. A plugin can provide a new one, such as `Lti1p4.MCP`, which other plugins can then extend.

### `%Ltix.Launch{}`

`%Ltix.Launch{}` replaces both `LaunchContext` and `LaunchClaims`. It follows `%Plug.Conn{}`.

| Field | Contents |
|---|---|
| `registration` | The registration the launch was verified against |
| `deployment` | The deployment the launch belongs to |
| `source_registration` | The host's own record that `registration` was built from |
| `source_deployment` | The host's own record that `deployment` was built from |
| `claims` | Parsed claims. This field has the role Plug gives `assigns` |
| `raw` | The claims as received |
| `private` | Library data, with keys prefixed by the library's name |
| `errors` | Errors collected by steps |
| `plugins` | The plugin set the launch ran with |

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
  use Ltix.Provider
  @callback properties() :: [...]
end
```

Each provider is entirely responsible for defining the semantics of its document. That includes which plugin set a child document uses, whether the provider creates the child during a call, such as each line item in a page of results, or the application builds it and passes it in, such as content items given to a Deep Linking response.

- `hook:` lists the building blocks the provider requires.
- A provider that defines its own `@callback`s has them added to its hook automatically.
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
- **Absent providers.** Extending a provider that no plugin in the call's plugin set provides does nothing. A plugin does not know which other plugins are loaded. When a provider is absent, none of its documents are built, so its extenders have nothing to do. The same holds for `after?/1` and `before?/1` naming a module that is not running. A plugin documents the providers it needs, and the application lists them.
- **Conflicting callbacks.** If two providers define their own callbacks with the same name, a module that extends both gets Elixir's "conflicting behaviours" warning. That module is split into one module per provider. A contract that several providers share belongs in a building block.

## Building Blocks

Building blocks are public, so third-party providers build their hooks from the same pieces as bundled providers.

### `Ltix.Step`

```elixir
@callback init(opts :: term()) :: term()
@callback call(document :: struct(), opts :: term()) ::
            {:ok, struct()} | {:error, Exception.t()} | {:halt, Exception.t()}
```

Options work as they do in Plug. `init/1` runs once for each extender entry when the plugin set is resolved, and its result is the `opts` passed to every `call/2`. The default `init/1` returns its options unchanged.

A step takes a document and returns one of three results. It is the contract for providers that run extenders as steps over a document, such as login and launch.

- `{:ok, document}` passes the updated document to the next step.
- `{:error, error}` adds the error to the document's `errors` and runs the next step.
- `{:halt, error}` adds the error to the document's `errors` and runs no further steps.

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

A module can only be ordered relative to another module, so each bundled step is its own module. `before?/1` and `after?/1` name modules as atoms, so renaming or splitting a bundled step module is a breaking change for plugins that order against it.

## Rules

- **No replacing providers.** A plugin cannot replace or remove what another plugin provides. A different flow, such as another login mechanism, is a new provider that the application calls.
- **No provider collisions.** Providers and targets are modules, and module names are unique. Two plugins cannot provide the same provider. When two steps write the same key in a document, such as a claim, the later write remains, because document data is maps. A provider with its own callbacks defines how its extenders' contributions combine. Extenders of a provider without `Ltix.Ordered` run in plugin order.
- **No short names.** Every provider and target is named by its module.

## Replacing 0.2's Extension Points

| 0.2 extension point | Replacement |
|---|---|
| `Ltix.LaunchClaims.Parser`, `:claim_parsers` | An extender of `Ltix.Launch`, or of each document the claim appears in |
| `Ltix.LaunchClaims.Role.Parser`, `:role_parsers` | Removed. Roles are the URIs the platform sent, checked with `Ltix.Role` |
| `Ltix.AdvantageService` | A service provider module in a plugin |
| `Ltix.DeepLinking.ContentItem` protocol | A content item type provided by a plugin, and extenders of existing types |
| `extensions:` on scores, line items, and content items | Extenders of the provider modules for those types |

## Not Yet Decided

- **The contract of each bundled provider.** This covers login, launch, notice, tool message, content item types, service resources, and the client assertion.

## Spike for Hooks

A prototype in a single `.exs` file tested the provider and hook design. It compiles without warnings and prints the output shown after the code.

Two facts about Elixir shaped the design.

- A module that declares two behaviours defining the same callback gets "conflicting behaviours found. Callback function call/2 is defined by both A and B". This is why steps share one `Ltix.Step` behaviour.
- When two `use` macros both declare the same behaviour, the module gets "the behaviour Ordered has been declared twice" for each callback. This is why building blocks declare themselves once.

`Ltix.Hook.declare_once/2` in the spike is the helper that declares a behaviour once.

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
