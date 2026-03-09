# Comparing Elixir LTI Libraries

Elixir's LTI ecosystem is small. If you need LTI 1.3 support, there are
two real options: Ltix and `lti_1p3`. This guide compares their design
philosophies so you can choose the right fit for your project.

## Landscape

| Library | LTI version | Status | Hex downloads |
|---|---|---|---|
| **Ltix** | 1.3 | Active | New |
| **`lti_1p3`** | 1.3 | Active | ~61,000 |
| `lti` | 1.0 only | Unmaintained | ~132,000 (legacy) |
| `plug_lti` | 1.x | Unmaintained | Not on Hex |
| `lightbulb` | 1.3 | Active (Gleam, not Elixir) | ~200 |

[`lti_1p3`](https://hex.pm/packages/lti_1p3) comes from the
Simon Initiative at Carnegie Mellon University. It was generously
extracted from [OLI Torus](https://github.com/Simon-Initiative/oli-torus),
a large Phoenix/LiveView learning platform, and has been in production
since 2021. The same team maintains `lightbulb`, a Gleam LTI library
targeting the BEAM.

Ltix would not exist without `lti_1p3`. It was born from extensive
experience building tools on top of `lti_1p3` and reflects lessons
learned about what a tool-focused LTI library could look like when
designed from scratch.

## Different starting points

The libraries come from different contexts, which shaped their designs:

**`lti_1p3`** was extracted from a production LMS. It supports both the
platform and tool sides of LTI, includes database-backed storage with
Ecto schemas, and reflects the needs of a large application that manages
its own registrations, JWKs, and platform instances.

**Ltix** was designed as a standalone library for tool developers. It
focuses on the tool side only, keeps storage abstract, and tries to
minimize the surface area a host app needs to implement.

Neither approach is wrong — they serve different audiences.

## API comparison

### Launch flow

Both libraries handle the three-step OIDC launch. The main difference
is how claims are returned.

**Ltix** parses claims into typed structs during validation:

```elixir
{:ok, %{redirect_uri: url, state: state}} =
  Ltix.handle_login(params, launch_url)

{:ok, context} = Ltix.handle_callback(params, state)

context.claims.roles            #=> [%Role{type: :context, name: :instructor}]
context.claims.context.title    #=> "Intro to Elixir"
context.claims.target_link_uri  #=> "https://mytool.example.com/launch"
```

**`lti_1p3`** returns the validated JWT as a map, preserving the
original claim URIs:

```elixir
{:ok, state, redirect_url} =
  Lti_1p3.Tool.OidcLogin.oidc_login_redirect_url(params)

{:ok, claims} =
  Lti_1p3.Tool.LaunchValidation.validate(params, session_state)

claims["https://purl.imsglobal.org/spec/lti/claim/roles"]
#=> ["http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"]

claims["https://purl.imsglobal.org/spec/lti/claim/context"]["title"]
#=> "Intro to Elixir"
```

### Storage

**Ltix** defines a single `Ltix.StorageAdapter` behaviour with four
callbacks — registration lookup, deployment lookup, nonce storage,
and nonce validation. JWK management and other concerns are handled
internally.

**`lti_1p3`** provides three behaviours (`DataProvider`,
`ToolDataProvider`, `PlatformDataProvider`) with a broader callback
surface. This gives the host app more control over JWK lifecycle,
login hints, and platform instances. The companion package
`lti_1p3_ecto_provider` provides a ready-made Ecto implementation.

### Error handling

**Ltix** uses [Splode](https://hex.pm/packages/splode) to define a
structured exception hierarchy. Errors are grouped into three classes
(`:invalid`, `:security`, `:unknown`) and carry `spec_ref` fields:

```elixir
case Ltix.handle_callback(params, state) do
  {:ok, context} -> ...
  {:error, %Ltix.Errors.Security{} = error} ->
    Logger.warning("Security: #{Exception.message(error)}")
end
```

**`lti_1p3`** returns error maps with `:reason` and `:msg` keys:

```elixir
case Lti_1p3.Tool.LaunchValidation.validate(params, state) do
  {:ok, claims} -> ...
  {:error, %{reason: :invalid_registration, msg: msg}} -> ...
end
```

### Advantage services

**Ltix** wraps service authentication and queries behind an
authenticate-then-call pattern:

```elixir
{:ok, client} = Ltix.MembershipsService.authenticate(context)
{:ok, roster} = Ltix.MembershipsService.get_members(client)
```

**`lti_1p3`** provides separate modules for token acquisition and
service calls, giving more visibility into each step:

```elixir
{:ok, token} = Lti_1p3.Tool.Services.AccessToken.fetch_access_token(
  registration, scopes, host
)
{:ok, members} = Lti_1p3.Tool.Services.NRPS.fetch_memberships(url, token)
```

## Feature comparison

| | Ltix | `lti_1p3` |
|---|---|---|
| **OIDC launch** | Yes | Yes |
| **AGS** | Coming before 0.1.0 | Yes |
| **NRPS** | Yes | Yes |
| **Deep Linking** | Claim parsing | Claim parsing |
| **Platform side** | No (tool only) | Yes |
| **Ecto provider** | No (bring your own adapter) | Yes (`lti_1p3_ecto_provider`) |
| **Test helpers** | Yes (`Ltix.Test`) | In-memory provider |

### Dependencies

| Ltix | `lti_1p3` |
|---|---|
| `req` | `httpoison` |
| `jose` | `joken` |
| `splode` | — |
| `nimble_options` | — |
| — | `timex` |
| — | `uuid` |
| — | `jason` |

## Choosing between them

**Ltix** is a good fit when you are building a tool and want typed
claims, structured errors, and a small integration surface (four
storage callbacks). It focuses on ergonomics and correctness for the
tool side of LTI.

**`lti_1p3`** is a good fit when you need platform-side support, want
a ready-made Ecto storage layer, or prefer a library with several years
of production history. Its broader callback surface gives more control
over JWK lifecycle and platform management.

## Next steps

- [What is Ltix?](what-is-ltix.md) — overview of Ltix's design
- [Getting Started](getting-started.md) — integrate Ltix into a Phoenix app
- `Ltix.StorageAdapter` — the four callbacks your app implements
- [Error Handling](error-handling.md) — working with structured errors
- [Advantage Services](advantage-services.md) — OAuth and service calls
