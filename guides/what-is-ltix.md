# What is Ltix?

Ltix is an Elixir library for handling LTI 1.3 launches on the tool side.
It handles the OIDC redirect flow, JWT signature verification, claim
parsing, and spec compliance so you can focus on what your tool actually
does.

## Why a library?

LTI 1.3 connects learning platforms (Canvas, Moodle, Blackboard) with
external tools (quiz engines, coding sandboxes, video players). When a
student clicks a link in their course, the platform launches the tool
through a multi-step browser redirect with information about who the
user is, what course they're in, and what role they have.

The protocol is built on OpenID Connect and signed JWTs. Implementing it
correctly means handling the following.

- A three-step redirect flow with CSRF protection via state parameters
- Key set fetching and caching to verify platform signatures
- JWT validation (signature, expiration, issuer, audience, nonce)
- Claim parsing (roles, context, resource links, service endpoints)
- Spec compliance across dozens of requirements from three IMS
  specifications

This is security-critical work with little room for error. Getting the
nonce check wrong allows replay attacks. Getting the audience
check wrong means accepting tokens meant for other tools.

## Two functions

Ltix does all of that in two function calls.

```elixir
# Step 1: Platform initiates login, build the redirect
{:ok, %{redirect_uri: url, state: state}} =
  Ltix.handle_login(params, launch_url)

# Step 2: Platform sends the signed JWT, validate and parse
{:ok, context} = Ltix.handle_callback(params, state)
```

The result is a `%Ltix.LaunchContext{}` containing everything about
the launch.

```elixir
context.claims.subject          #=> "user-12345"
context.claims.name             #=> "Jane Smith"
context.claims.email            #=> "jane@university.edu"
context.claims.roles            #=> [%Role{type: :context, name: :instructor}, ...]
context.claims.context          #=> %Context{id: "course-1", title: "Intro to Elixir"}
context.claims.resource_link    #=> %ResourceLink{id: "link-1", title: "Assignment 1"}
context.claims.target_link_uri  #=> "https://mytool.example.com/activity/42"

context.registration            #=> your struct from StorageAdapter.get_registration/3
context.deployment              #=> your struct from StorageAdapter.get_deployment/3
```

Between those two calls, Ltix has verified the JWT signature against
the platform's public keys, validated the token's expiration and
audience, checked the nonce and recorded it as used, parsed role URIs into
structured data, and confirmed the deployment exists.

> #### Two calls per launch {: .info}
>
> `handle_login/3` and `handle_callback/3` are the only functions a
> launch needs. Everything else (storage lookups, key fetching, token
> validation) happens inside them. `handle_login!/3` and
> `handle_callback!/3` do the same and raise on error. After a launch,
> `Ltix.GradeService`, `Ltix.MembershipsService`, and `Ltix.DeepLinking`
> take the returned context.

## What Ltix handles vs. what you handle

Ltix handles the protocol. Your application handles everything else.

| Ltix's job | Your app's job |
|---|---|
| Build the authorization redirect | Store the OIDC state in the session |
| Fetch and cache the platform's public keys | Look up registrations and deployments |
| Validate the JWT signature and claims | Record used nonces |
| Parse roles, context, resource links | Decide what to do with the launch |
| Return structured, typed launch data | Handle errors and show appropriate UI |

This boundary is enforced through the `Ltix.StorageAdapter` behaviour,
a set of three required callbacks your application implements to
provide persistence, plus two optional ones for signing. Ltix never accesses your database directly.

## Design choices

**Storage-agnostic.** Ltix doesn't assume your database, ORM, or
persistence strategy. You implement `Ltix.StorageAdapter` with three
required callbacks for registration lookup, deployment lookup, and
recording used nonces. Use Ecto, Mnesia, Redis, or anything else.

**Framework-agnostic.** Ltix works with Phoenix, bare Plug, or any
Elixir web framework. It takes maps in and returns structs out, with no
Plug dependencies in the core path.

**Spec-referenced errors.** When something goes wrong, Ltix returns
structured errors organized into three classes, `:invalid` (bad input),
`:security` (failed security checks), and `:unknown` (unexpected
failures). Most errors have a `spec_ref` field referencing the exact
spec section that was violated, so you can look up why a validation
failed.

```elixir
{:error, %Ltix.Errors.Security.AudienceMismatch{
  claim: "aud",
  expected: "my-client-id",
  actual: ["wrong-client-id"],
  spec_ref: "Sec §5.1.3 step 3"
}}
```

## Next steps

- [LTI Advantage Concepts](concepts.md) - understand the protocol
  (registrations, deployments, the launch flow, roles, and nonces)
- [Getting Started](getting-started.md) - integrate Ltix into a Phoenix
  app step by step
- `Ltix.StorageAdapter` - the three required callbacks your app implements
- `Ltix.LaunchContext` - what a successful launch returns
- `Ltix.LaunchClaims.Role` - role parsing and predicates
