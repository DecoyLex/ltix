# Ltix

[![CI](https://github.com/DecoyLex/ltix/actions/workflows/ci.yml/badge.svg)](https://github.com/DecoyLex/ltix/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/ltix.svg)](https://hex.pm/packages/ltix)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/ltix)
[![License](https://img.shields.io/hexpm/l/ltix.svg)](https://github.com/DecoyLex/ltix/blob/main/LICENSE)

Ltix is an Elixir library for building LTI 1.3 tool applications. It handles
the OIDC launch flow, JWT verification, and claim parsing so you can focus on
what your tool actually does.

```elixir
# Platform initiates login - build the redirect
{:ok, %{redirect_uri: url, state: state}} =
  Ltix.handle_login(params, launch_url)

# Platform sends the signed JWT - validate and parse
{:ok, context} = Ltix.handle_callback(params, state)

context.claims.roles          #=> [%Role{type: :context, name: :instructor}, ...]
context.claims.resource_link  #=> %ResourceLink{id: "link-1", title: "Assignment 1"}
context.registration          #=> your struct from StorageAdapter.get_registration/2
```

## Features

- **Two-function launch API** - `handle_login/3` and `handle_callback/3`
  cover the entire OIDC flow
- **LTI Advantage** - Assignment and Grade Services, Names and Role
  Provisioning, and Deep Linking
- **Storage-agnostic** - implement four callbacks in `Ltix.StorageAdapter`
  to plug in any persistence layer
- **Framework-agnostic** - works with Phoenix, bare Plug, or any Elixir
  web framework
- **Structured claims** - roles, context, resource links, and service
  endpoints parsed into typed structs
- **Spec-referenced errors** - classified as `:invalid`, `:security`, or
  `:unknown`, with a `spec_ref` pointing to the relevant spec section
- **Testing utilities** - `Ltix.Test` provides a simulated platform for
  integration tests without a real LMS

## Installation

Add `:ltix` to your dependencies:

```elixir
def deps do
  [
    {:ltix, "~> 0.1"}
  ]
end
```

## Documentation

- [Getting Started](https://hexdocs.pm/ltix/getting-started.html)
- [What is Ltix?](https://hexdocs.pm/ltix/what-is-ltix.html)
- [LTI 1.3 Concepts](https://hexdocs.pm/ltix/concepts.html)
- [Storage Adapters](https://hexdocs.pm/ltix/storage-adapters.html)
- [Working with Roles](https://hexdocs.pm/ltix/working-with-roles.html)
- [Error Handling](https://hexdocs.pm/ltix/error-handling.html)
- [Advantage Services](https://hexdocs.pm/ltix/advantage-services.html)
- [Memberships Service](https://hexdocs.pm/ltix/memberships-service.html)
- [Grade Service](https://hexdocs.pm/ltix/grade-service.html)
- [Deep Linking](https://hexdocs.pm/ltix/deep-linking.html)
- [JWK Management](https://hexdocs.pm/ltix/jwk-management.html)

## License

MIT.

See [LICENSE](https://github.com/DecoyLex/ltix/blob/main/LICENSE) for details.
