# Custom Role Parsers

Ltix parses standard LIS role URIs out of the box, but some platforms
send proprietary role vocabularies with their own URI namespaces. Without
a custom parser, those URIs end up as raw strings in `unrecognized_roles`:

```elixir
context.claims.unrecognized_roles
#=> ["https://myplatform.example.com/roles/CourseAdmin"]
```

Register a custom role parser to teach Ltix how to handle them.

## Implementing the behaviour

A role parser is a module that implements `Ltix.LaunchClaims.Role.Parser`.
The only required callback is `parse/1`, which receives a role URI string
and returns `{:ok, %Role{}}` or `:error`:

```elixir
defmodule MyApp.Lti.PlatformRoleParser do
  use Ltix.LaunchClaims.Role.Parser

  alias Ltix.LaunchClaims.Role

  @base "https://myplatform.example.com/roles/"

  @roles %{
    "CourseAdmin" => :course_admin,
    "Facilitator" => :facilitator,
    "Grader" => :grader
  }

  @impl true
  def parse(uri) do
    suffix = String.replace_leading(uri, @base, "")

    case Map.fetch(@roles, suffix) do
      {:ok, name} ->
        {:ok, %Role{type: :context, name: name, sub_role: nil, uri: uri}}

      :error ->
        :error
    end
  end
end
```

The parser only receives URIs that match its registered prefix (see
[Registration](#registering-parsers) below), so you don't need to check
the prefix yourself.

## Optional: `to_uri/1`

If you need to convert `%Role{}` structs back to URI strings (e.g. for
building NRPS responses or test fixtures), implement the optional
`to_uri/1` callback:

```elixir
@roles_inverse Map.new(@roles, fn {k, v} -> {v, k} end)

@impl true
def to_uri(%Role{type: :context, name: name, sub_role: nil}) do
  case Map.fetch(@roles_inverse, name) do
    {:ok, suffix} -> {:ok, @base <> suffix}
    :error -> :error
  end
end

def to_uri(_), do: :error
```

## Registering parsers

Role parsers are registered as a map of URI prefix to parser module. The
prefix determines which URIs are routed to your parser. Ltix tries each
registered parser whose prefix matches the URI, then falls back to the
built-in LIS parser.

**Via application config** (recommended for parsers that apply globally):

```elixir
# config/config.exs
config :ltix, Ltix.LaunchClaims,
  role_parsers: %{
    "https://myplatform.example.com/roles/" => MyApp.Lti.PlatformRoleParser
  }
```

**Via `LaunchClaims.from_json/2`** (for per-call control):

```elixir
Ltix.LaunchClaims.from_json(claims,
  role_parsers: %{
    "https://myplatform.example.com/roles/" => MyApp.Lti.PlatformRoleParser
  }
)
```

**Via `Role.parse/2`** (for parsing individual URIs):

```elixir
Role.parse(uri,
  parsers: %{
    "https://myplatform.example.com/roles/" => MyApp.Lti.PlatformRoleParser
  }
)
```

Per-call parsers merge with application config, with per-call taking
priority for overlapping prefixes. The LIS parser is always included
as a fallback.

## Using function parsers

For simple cases, you can pass an anonymous function or captured function
instead of a module:

```elixir
config :ltix, Ltix.LaunchClaims,
  role_parsers: %{
    "https://myplatform.example.com/roles/" => fn uri ->
      case uri do
        "https://myplatform.example.com/roles/CourseAdmin" ->
          {:ok, %Role{type: :context, name: :course_admin, sub_role: nil, uri: uri}}

        _ ->
          :error
      end
    end
  }
```

> #### Function parsers can't convert back to URIs {: .warning}
>
> `Role.to_uri/1` only works with module-based parsers that implement
> the `to_uri/1` callback. Function parsers are skipped during URI
> conversion.

## Working with custom roles

Once registered, custom roles are parsed into `%Role{}` structs just
like standard LIS roles. They appear in `context.claims.roles` and work
with all the filtering and checking functions:

```elixir
Role.context_roles(context.claims.roles)
Role.has_role?(context.claims.roles, :context, :course_admin)
```

The built-in predicates (`instructor?/1`, `learner?/1`, etc.) won't
match custom role names. Use `has_role?/4` for custom roles.

## Next steps

- [Working with Roles](working-with-roles.md) for standard role predicates
  and platform differences
- [Custom Claim Parsers](custom-claim-parsers.md) for parsing
  vendor-specific extension claims
- `Ltix.LaunchClaims.Role.Parser` for the full behaviour reference
- `Ltix.LaunchClaims.Role.LIS` as a reference implementation
