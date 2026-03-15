# Ltix

[![CI](https://github.com/DecoyLex/ltix/actions/workflows/ci.yml/badge.svg)](https://github.com/DecoyLex/ltix/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/ltix.svg)](https://hex.pm/packages/ltix)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/ltix)
[![License](https://img.shields.io/hexpm/l/ltix.svg)](https://github.com/DecoyLex/ltix/blob/main/LICENSE)

Ltix is an Elixir library for building LTI 1.3 tool applications focused on
correctness and developer experience. It handles the OIDC launch flow, JWT
verification, claim parsing, and spec compliance so you can focus on what
your tool actually does.

LTI 1.3 connects learning platforms (Canvas, Moodle, Blackboard) with external
tools through a multi-step browser redirect built on OpenID Connect and signed
JWTs. Ltix collapses all of that into two function calls:

```elixir
# Platform initiates login — build the redirect
{:ok, %{redirect_uri: url, state: state}} =
  Ltix.handle_login(params, launch_url)

# Platform sends the signed JWT — validate and parse
{:ok, context} = Ltix.handle_callback(params, state)
```

The result is a `%Ltix.LaunchContext{}` with everything about the launch:

```elixir
context.claims.roles            #=> [%Role{type: :context, name: :instructor}, ...]
context.claims.context          #=> %Context{id: "course-1", title: "Intro to Elixir"}
context.claims.resource_link    #=> %ResourceLink{id: "link-1", title: "Assignment 1"}
context.claims.target_link_uri  #=> "https://mytool.example.com/activity/42"
context.registration            #=> %Registration{issuer: "https://canvas.instructure.com", ...}
```

Between those two calls, Ltix verifies the JWT signature against the platform's
public keys, validates expiration and audience, checks and consumes the nonce,
parses role URIs into structured data, and confirms the deployment exists.

## Features

- **Two-function API** — `handle_login/3` and `handle_callback/3` are the
  only entry points you need for launches
- **Storage-agnostic** — implement four callbacks in `Ltix.StorageAdapter`
  to plug in any persistence layer (Ecto, Mnesia, Redis, etc.)
- **Framework-agnostic** — works with Phoenix, bare Plug, or any Elixir web
  framework; no Plug dependencies in the core path
- **Structured claims** — roles, context, resource links, and service endpoints
  are parsed into typed structs with convenience predicates
- **Advantage Services** — built-in support for Names and Roles Provisioning
  (roster queries), with OAuth 2.0 client credentials authentication
- **Spec-referenced errors** — errors are classified as `:invalid`, `:security`,
  or `:unknown`, and most carry a `spec_ref` pointing to the violated spec section
- **Testing utilities** — `Ltix.Test` provides a simulated platform for
  writing integration tests without a real LMS

## Installation

Add `:ltix` to your dependencies:

```elixir
def deps do
  [
    {:ltix, "~> 0.1"}
  ]
end
```

Then configure a storage adapter:

```elixir
# config/config.exs
config :ltix, storage_adapter: MyApp.LtiStorage
```

## Quick start

Implement the `Ltix.StorageAdapter` behaviour (four callbacks for registration
lookup, deployment lookup, nonce storage, and nonce validation), add two POST
routes, and wire them to Ltix:

```elixir
defmodule MyAppWeb.LtiController do
  use MyAppWeb, :controller

  def login(conn, params) do
    launch_url = url(conn, ~p"/lti/launch")

    case Ltix.handle_login(params, launch_url) do
      {:ok, %{redirect_uri: redirect_uri, state: state}} ->
        conn
        |> put_session(:lti_state, state)
        |> redirect(external: redirect_uri)

      {:error, reason} ->
        conn |> put_status(400) |> text(Exception.message(reason))
    end
  end

  def launch(conn, params) do
    state = get_session(conn, :lti_state)

    case Ltix.handle_callback(params, state) do
      {:ok, context} ->
        conn
        |> delete_session(:lti_state)
        |> render(:launch, context: context)

      {:error, reason} ->
        conn |> put_status(401) |> text(Exception.message(reason))
    end
  end
end
```

See the [Getting Started](https://hexdocs.pm/ltix/getting-started.html) guide
for a complete walkthrough including storage adapters, routing, and cross-origin
configuration.

## Documentation

- [What is Ltix?](https://hexdocs.pm/ltix/what-is-ltix.html) — high-level overview
- [LTI 1.3 Concepts](https://hexdocs.pm/ltix/concepts.html) — registrations, deployments, the launch flow
- [Getting Started](https://hexdocs.pm/ltix/getting-started.html) — step-by-step Phoenix integration
- [Storage Adapters](https://hexdocs.pm/ltix/storage-adapters.html) — implementing persistence
- [Working with Roles](https://hexdocs.pm/ltix/working-with-roles.html) — role parsing and authorization
- [Error Handling](https://hexdocs.pm/ltix/error-handling.html) — matching on error classes
- [Advantage Services](https://hexdocs.pm/ltix/advantage-services.html) — OAuth and service endpoints
- [Memberships Service](https://hexdocs.pm/ltix/memberships-service.html) — querying course rosters
- [JWK Management](https://hexdocs.pm/ltix/jwk-management.html) — key generation and rotation

## License

MIT — see [LICENSE](https://github.com/DecoyLex/ltix/blob/main/LICENSE) for details.
