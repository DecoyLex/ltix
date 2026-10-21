# Writing Plugins

A plugin can add a step to login. Ltix's own login steps come from `Ltix.Core`, a default plugin.

| Goal | See |
|---|---|
| Write and enable a first plugin | [Write a plugin](#write-a-plugin), [Enable plugins](#enable-plugins) |
| Run code during login | [Add a step](#add-a-step) |
| Build on another plugin, or enable several together | [Depend on another plugin](#depend-on-another-plugin), [Enable several plugins together](#enable-several-plugins-together) |
| Let other plugins extend yours | [Provide something for other plugins to extend](#provide-something-for-other-plugins-to-extend) |
| Fix `InvalidPluginSet` | [Fix a plugin set that fails to resolve](#fix-a-plugin-set-that-fails-to-resolve) |
| Test a plugin | [Test a plugin](#test-a-plugin) |

## Write a plugin

A plugin implements `Ltix.Plugin`. Its `plugin/1` callback returns the plugin's declaration, built from `Ltix.Plugin.new/1`. This one adds a login step that rejects blocked platforms.

```elixir
defmodule Blocklist do
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(opts) do
    Ltix.Plugin.new(name: "Blocklist", version: "1.0.0")
    |> Ltix.Plugin.add({Blocklist.Login, issuers: Keyword.get(opts, :issuers, [])})
  end
end

defmodule Blocklist.Login do
  use Ltix.Login

  @impl Ltix.Step
  def call(login, opts) do
    if login.params["iss"] in opts[:issuers] do
      {:halt, Blocklist.Blocked.exception(issuer: login.params["iss"])}
    else
      {:ok, login}
    end
  end

  @impl Ltix.Ordered
  def before?(_module), do: true
end

defmodule Blocklist.Blocked do
  defexception [:issuer]

  @impl Exception
  def message(%{issuer: issuer}), do: "#{issuer} is blocked"
end
```

`use Ltix.Login` makes `Blocklist.Login` a login step, and its `before?/1` runs it before every other step, so Ltix never looks up a blocked platform's registration. Once you [enable](#enable-plugins) the plugin, a login from a blocked issuer returns `{:error, %Blocklist.Blocked{}}`.

The declaration lists your plugin's modules and the plugins it needs.

- `Ltix.Plugin.add/2` adds a module, such as a login step. Pass options as `{module, opts}`. Leave out the [providers](`Ltix.Provider`) your modules `use`, such as `Ltix.Login`.
- `Ltix.Plugin.depend_on/2` adds a plugin this one needs.

`name` and `version` are optional. Conflict errors include them to identify your plugin.

## Enable plugins

Enable plugins in your configuration, as `MyPlugin` or `{MyPlugin, opts}`. `plugin/1` receives the options, or `[]`.

```elixir
# config/config.exs
config :ltix, plugins: [{Blocklist, issuers: ["https://lms.example.com"]}]
```

`plugins:` on a call replaces the configured plugins for that call.

```elixir
Ltix.handle_login(params, launch_url, plugins: [Blocklist])
```

- A plugin that appears twice in `plugins:` runs each of its steps twice, once with each entry's options.
- Each distinct `plugins:` list stays in memory until the node stops. In production, build these lists from values that don't change between requests.

A call runs with the [default plugins](`Ltix.DefaultPlugins`) first, then the enabled plugins, each after its [dependencies](#depend-on-another-plugin). This is plugin order.

## Add a step

A step receives a login, launch, client assertion, or Deep Linking response, and returns it. A module becomes a step with `use` and one of these modules, such as `use Ltix.Login`.

| Module | Runs during |
|---|---|
| `Ltix.Login` | `Ltix.handle_login/3` |

`c:Ltix.Step.call/2` returns one of three results.

| Result | Effect |
|---|---|
| `{:ok, struct}` | The next step receives the struct |
| `{:error, exception}` | Ltix records the error and runs the next step |
| `{:halt, exception}` | Ltix records the error and runs no more steps |

When the struct has errors after its steps run, the function your application called, such as `Ltix.handle_login/3`, returns `{:error, exception}`. Several errors come back as one [grouped error](error-handling.md#single-and-grouped-errors).

Do expensive setup in `c:Ltix.Step.init/1`.

Keep your own data in the struct's `private` map, under keys that start with your library's name. Ltix's own keys start with `ltix_`.

```elixir
@impl Ltix.Step
def call(login, _opts) do
  {:ok, put_in(login.private[:blocklist_checked_at], DateTime.utc_now())}
end
```

### Add a function as a step

`Ltix.Login.add_step/2` adds a function as a login step, an anonymous step. The function receives the login and returns the same results as `c:Ltix.Step.call/2`.

```elixir
def plugin(_opts) do
  Ltix.Plugin.new(name: "Login Timer")
  |> Ltix.Login.add_step(fn login ->
    {:ok, put_in(login.private[:login_timer_started_at], DateTime.utc_now())}
  end)
end
```

No step's `c:Ltix.Ordered.before?/1` or `c:Ltix.Ordered.after?/1` receives an anonymous step. Write a module for a step that other steps order against.

### Order steps

Order a step against a phase, such as `Ltix.Login.RegistrationFound`, with `c:Ltix.Ordered.before?/1` or `c:Ltix.Ordered.after?/1`. `Ltix.Login` lists its phases and what's true at each. Implement only the callback you need. Both default to `false`.

This login step rejects logins for a suspended tenant. It runs after `Ltix.Login.RegistrationFound`, so `login.source_registration` is your application's registration record.

```elixir
defmodule MyApp.RejectSuspendedTenant do
  use Ltix.Login

  @impl Ltix.Step
  def call(login, _opts) do
    tenant_id = login.source_registration.tenant_id

    if MyApp.Tenants.suspended?(tenant_id),
      do: {:halt, MyApp.TenantSuspended.exception(tenant_id: tenant_id)},
      else: {:ok, login}
  end

  @impl Ltix.Ordered
  def after?(Ltix.Login.RegistrationFound), do: true
  def after?(_module), do: false
end
```

Declare an order for everything your step relies on. A step can rely only on its orders, and its place among other steps can change when plugins change. To run between two phases, order the step after the first and before the second. To run after every other step, return `true` from `c:Ltix.Ordered.after?/1` for every module. Ordering against a module that isn't running, or a misspelled one, has no effect. `Ltix.Ordered` has the full rules.

Order the steps your plugin adds, anonymous steps included, with `Ltix.Login.run_after/3` and `Ltix.Login.run_before/3`. Each calls a function with your plugin, and orders every login step the function adds after or before a module. This plugin rejects suspended tenants with an anonymous step after `Ltix.Login.RegistrationFound`.

```elixir
def plugin(_opts) do
  Ltix.Plugin.new(name: "Tenants")
  |> Ltix.Login.run_after(Ltix.Login.RegistrationFound, fn plugin ->
    Ltix.Login.add_step(plugin, &MyApp.Tenants.reject_suspended/1)
  end)
end
```

To run steps between two phases, call `run_before/3` inside `run_after/3`. When these calls order a step both before and after another, or put it in a cycle, the plugin set fails to resolve with `Ltix.Errors.Unknown.InvalidPluginSet`.

## Depend on another plugin

Declare a plugin yours needs with `Ltix.Plugin.depend_on/2`. The application enables only yours.

```elixir
defmodule CourseTools do
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Ltix.Plugin.new(name: "Course Tools", version: "1.0.0")
    |> Ltix.Plugin.depend_on(Blocklist)
    |> Ltix.Plugin.add(CourseTools.Login)
  end
end
```

- A dependency comes before the plugins that need it.
- A dependency is added once, however many plugins depend on it.
- A dependency gets the options the application enables it with, or `[]` when the application doesn't enable it.

## Enable several plugins together

A profile is a plugin that only depends on others. Enabling the profile enables them all.

```elixir
defmodule CourseSuite do
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Ltix.Plugin.new(name: "Course Suite", version: "1.0.0")
    |> Ltix.Plugin.depend_on(Blocklist)
    |> Ltix.Plugin.depend_on(CourseTools)
  end
end
```

## Provide something for other plugins to extend

A provider is a module that other plugins extend, such as `Ltix.Login`. The `hook:` option of `use Ltix.Provider` lists the behaviours that modules extending it implement.

This provider defines a report that other plugins add steps to. `build/2` is the function your application calls. A plugin adds the provider with `Ltix.Plugin.add/2`.

```elixir
defmodule Reports.Report do
  use Ltix.Provider, hook: [Ltix.Step, Ltix.Ordered]

  defstruct data: %{}, private: %{}, errors: [], plugins: nil

  def build(data, opts \\ []) do
    with {:ok, plugins} <- Ltix.PluginSet.resolve(opts[:plugins]),
         %Reports.Report{errors: []} = report <-
           Ltix.Step.run(%Reports.Report{data: data, plugins: plugins}) do
      {:ok, report}
    else
      %Reports.Report{errors: errors} -> {:error, errors}
      {:error, error} -> {:error, error}
    end
  end
end
```

- `Ltix.PluginSet.resolve/1` resolves the configured plugins when given `nil`.
- `Ltix.Step.run/1` runs the report's steps in their declared order. The struct needs `plugins` and `errors` fields. Add a `private` map when steps keep their own data.
- Extending a provider that isn't in the plugin set does nothing.

### Report conflicts

A provider can implement `c:Ltix.Provider.resolve/1` to check the plugin set when Ltix resolves it. It returns `{:ok, data}` or `{:error, conflicts}`. An entry point such as `Reports.Report.build/2` reads the data from the resolved plugin set with `Ltix.PluginSet.data(plugins, Reports.Column)`.

This provider defines report columns. Each column declares its name with the `:name` option, and the provider returns a conflict for two columns with the same name.

```elixir
defmodule Reports.Column do
  use Ltix.Provider

  alias Ltix.PluginSet.Conflict

  @callback value(data :: map()) :: term()

  @impl Ltix.Provider
  def resolve(plugins) do
    columns = Ltix.PluginSet.entries(plugins, __MODULE__)
    conflicts = Conflict.duplicates(columns, & &1.opts[:name], &"both declare the column #{&1}")

    if conflicts == [],
      do: {:ok, Map.new(columns, &{&1.opts[:name], &1.module})},
      else: {:error, conflicts}
  end
end

defmodule Reports.Total do
  use Reports.Column, name: "total"

  @impl Reports.Column
  def value(data), do: Enum.sum(data.amounts)
end
```

`Ltix.PluginSet.entries/2` returns each module a plugin added, with its options. The options of the module's `use`, such as `name: "total"`, come first, and a plugin can't add the module with them again. Modules that extend a provider also implement each `@callback` it defines, such as `value/1` in `Reports.Column`.

## Fix a plugin set that fails to resolve

When the enabled plugins conflict, a call returns `{:error, %Ltix.Errors.Unknown.InvalidPluginSet{}}`. The error message includes each conflicting module and the plugin that adds it.

```elixir
{:error, error} = Ltix.handle_login(params, launch_url)
Exception.message(error)
#=> "Reports.Total (Totals 1.0.0) and Reports.Sum (Sums 2.1.0) both declare the column total"
```

| Conflict | Fix |
|---|---|
| Plugins that depend on each other in a cycle | Remove one of the dependencies |
| A conflict another module's `c:Ltix.Provider.resolve/1` reports | See that module's documentation |

Enabling a module that isn't a plugin raises `Ltix.Errors.Invalid.InvalidOption`.

## Test a plugin

Pass `plugins:` at the call, and your tests can run with `async: true`. These tests use the configuration from [Testing LTI Launches](cookbooks/testing-lti-launches.md#setup) and a test platform from `Ltix.Test.setup_platform!/1`.

```elixir
setup do
  %{platform: Ltix.Test.setup_platform!()}
end

test "blocks a listed issuer", %{platform: platform} do
  params = Ltix.Test.login_params(platform)

  assert {:error, %Blocklist.Blocked{}} =
           Ltix.handle_login(params, "https://tool.example.com/launch",
             plugins: [{Blocklist, issuers: [params["iss"]]}]
           )
end
```

## Next steps

- `Ltix.Plugin` and `Ltix.PluginSet` for manifests and plugin sets
- `Ltix.Login` for the login's fields and phases
