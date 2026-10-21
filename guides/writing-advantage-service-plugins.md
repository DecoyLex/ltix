# Writing Advantage Service Plugins

A plugin can add an [Advantage service](advantage-services.md). [Writing Plugins](writing-plugins.md) covers writing and enabling a plugin.

Examples on this page build this plugin for a fictional proctoring service.

```elixir
defmodule Proctoring do
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Ltix.Plugin.new(name: "Proctoring", version: "1.0.0")
    |> Ltix.Plugin.add(Proctoring.Endpoint)
    |> Ltix.Plugin.add(Proctoring.Scope)
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

## Next steps

- `Ltix.Property` and `Ltix.ClientAssertion` for the full contracts
