# Working with Roles

LTI platforms send role URIs in the launch JWT. Ltix parses these into
structured `%Role{}` structs and provides predicates and filters for
authorization logic.

## Roles in launch claims

After a successful launch, roles are available on the claims struct:

```elixir
{:ok, context} = Ltix.handle_callback(params, state)

context.claims.roles
#=> [%Role{type: :context, name: :instructor, ...}, %Role{type: :institution, name: :student, ...}]

context.claims.unrecognized_roles
#=> ["http://example.com/custom-role"]
```

Recognized role URIs become `%Role{}` structs. Anything the parser
doesn't recognize goes into `unrecognized_roles` as raw URI strings.

## The Role struct

```elixir
%Ltix.LaunchClaims.Role{
  type: :context | :institution | :system,
  name: :instructor,
  sub_role: :teaching_assistant | nil,
  uri: "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"
}
```

- **type** — the role's scope: `:context` (course-level), `:institution`, or `:system`
- **name** — the role as an atom (`:instructor`, `:learner`, `:administrator`, etc.)
- **sub_role** — optional refinement (e.g. `:teaching_assistant`, `:grader`)
- **uri** — the original URI string from the platform

## Predicates

The most common check is "is this user an instructor or a learner?"
Use the built-in predicates:

```elixir
alias Ltix.LaunchClaims.Role

Role.instructor?(context.claims.roles)      #=> true/false
Role.learner?(context.claims.roles)         #=> true/false
Role.administrator?(context.claims.roles)   #=> true/false
Role.content_developer?(context.claims.roles)
Role.mentor?(context.claims.roles)
Role.teaching_assistant?(context.claims.roles)
```

These check for **context** roles specifically. An institution-level
`:administrator` won't match `Role.administrator?/1` — use `has_role?/4`
for cross-type checks.

### Generic checks with `has_role?/4`

```elixir
# Context instructor (same as instructor?/1)
Role.has_role?(roles, :context, :instructor)

# Institution faculty
Role.has_role?(roles, :institution, :faculty)

# System administrator
Role.has_role?(roles, :system, :administrator)

# Specific sub-role
Role.has_role?(roles, :context, :instructor, :teaching_assistant)
```

## Filtering by type

Split roles into their three categories:

```elixir
Role.context_roles(roles)       #=> [%Role{type: :context, ...}, ...]
Role.institution_roles(roles)   #=> [%Role{type: :institution, ...}, ...]
Role.system_roles(roles)        #=> [%Role{type: :system, ...}, ...]
```

## Building authorization logic

A typical pattern for an LTI tool:

```elixir
defmodule MyAppWeb.LtiAuth do
  alias Ltix.LaunchClaims.Role

  def authorize(context) do
    roles = context.claims.roles

    cond do
      Role.administrator?(roles) -> :admin
      Role.instructor?(roles) -> :instructor
      Role.teaching_assistant?(roles) -> :ta
      Role.learner?(roles) -> :learner
      true -> :observer
    end
  end
end
```

Use the result to gate access in your controller:

```elixir
def launch(conn, params) do
  {:ok, context} = Ltix.handle_callback(params, get_session(conn, :lti_state))
  role = MyAppWeb.LtiAuth.authorize(context)

  conn
  |> put_session(:lti_role, role)
  |> put_session(:lti_user_id, context.claims.subject)
  |> redirect(to: dashboard_path(role))
end

defp dashboard_path(:admin), do: ~p"/admin"
defp dashboard_path(:instructor), do: ~p"/manage"
defp dashboard_path(_), do: ~p"/learn"
```

## Supported role names

### Context roles

`:administrator`, `:content_developer`, `:instructor`, `:learner`,
`:mentor`, `:manager`, `:member`, `:officer`

Common sub-roles for instructor: `:teaching_assistant`,
`:external_instructor`, `:grader`, `:guest_instructor`, `:lecturer`,
`:primary_instructor`, `:secondary_instructor`

### Institution roles

`:administrator`, `:faculty`, `:guest`, `:none`, `:other`, `:staff`,
`:student`, `:alumni`, `:instructor`, `:learner`, `:member`, `:mentor`,
`:observer`, `:prospective_student`

### System roles

`:administrator`, `:none`, `:account_admin`, `:creator`, `:sys_admin`,
`:sys_support`, `:user`, `:test_user`

## Parsing roles directly

If you need to parse role URIs outside of a launch (e.g. from a Names
and Roles Provisioning Service response):

```elixir
{:ok, role} = Role.parse("http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor")
#=> %Role{type: :context, name: :instructor, sub_role: nil, ...}

# Short forms work too
{:ok, role} = Role.parse("Learner")
#=> %Role{type: :context, name: :learner, ...}

# Batch parse with unrecognized separation
{parsed, unrecognized} = Role.parse_all(uri_list)
```
