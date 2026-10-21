# Ltix

[![CI](https://github.com/DecoyLex/ltix/actions/workflows/ci.yml/badge.svg)](https://github.com/DecoyLex/ltix/actions/workflows/ci.yml) [![Hex.pm](https://img.shields.io/hexpm/v/ltix.svg)](https://hex.pm/packages/ltix) [![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://ltix.hexdocs.pm) [![License](https://img.shields.io/hexpm/l/ltix.svg)](https://github.com/DecoyLex/ltix/blob/main/LICENSE)

Ltix is an Elixir library for building LTI 1.3 tool applications. It handles the OIDC launch flow, JWT verification, and claim parsing.

```elixir
# Platform initiates login - build the redirect
{:ok, %{redirect_uri: url, state: state}} =
  Ltix.handle_login(params, launch_url)

# Platform sends the signed JWT - validate and parse
{:ok, launch} = Ltix.handle_callback(params, state)

launch.claims.roles          #=> ["http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor", ...]
launch.claims.resource_link  #=> %ResourceLink{id: "link-1", title: "Assignment 1"}
launch.source_registration   #=> your struct from StorageAdapter.get_registration/3
```

## Features

- **Two-function launch API** - `handle_login/3` and `handle_callback/3` cover the entire OIDC flow
- **LTI Advantage** - Assignment and Grade Services, Names and Role Provisioning, and Deep Linking
- **Storage-agnostic** - implement three required callbacks in `Ltix.StorageAdapter` to use any database or store
- **Framework-agnostic** - works with Phoenix, bare Plug, or any Elixir web framework
- **Structured claims** - context, resource links, and service endpoints parsed into typed structs, and role checks in `Ltix.Role`
- **Structured errors** - classified as `:invalid`, `:security`, or `:unknown`
- **Plugins** - add claims, message types, content items, and launch checks that Ltix doesn't define
- **Testing utilities** - `Ltix.Test` provides a simulated platform for integration tests without a real platform

## Installation

Add `:ltix` to your dependencies.

```elixir
def deps do
  [
    {:ltix, "~> 0.2"}
  ]
end
```

## Documentation

- [Getting Started](https://ltix.hexdocs.pm/getting-started.html)
- [What is Ltix?](https://ltix.hexdocs.pm/what-is-ltix.html)
- [LTI Advantage Concepts](https://ltix.hexdocs.pm/concepts.html)
- [Storage Adapters](https://ltix.hexdocs.pm/storage-adapters.html)
- [Working with Roles](https://ltix.hexdocs.pm/working-with-roles.html)
- [Error Handling](https://ltix.hexdocs.pm/error-handling.html)
- [Advantage Services](https://ltix.hexdocs.pm/advantage-services.html)
- [Memberships Service](https://ltix.hexdocs.pm/memberships-service.html)
- [Grade Service](https://ltix.hexdocs.pm/grade-service.html)
- [Deep Linking](https://ltix.hexdocs.pm/deep-linking.html)
- [Writing Plugins](https://ltix.hexdocs.pm/writing-plugins.html)
- [JWK Management](https://ltix.hexdocs.pm/jwk-management.html)

## License

MIT.

See [LICENSE](https://github.com/DecoyLex/ltix/blob/main/LICENSE) for details.
