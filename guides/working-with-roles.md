# Working with Roles

LTI platforms send role URIs in the launch JWT. Ltix parses these into
structured `%Role{}` structs with predicates and filters for
authorization logic. Most tools just need the predicates in the next
section.

## Checking roles

The most common check is "is this user an instructor or a learner?"

```elixir
alias Ltix.LaunchClaims.Role

Role.instructor?(context.claims.roles)
Role.learner?(context.claims.roles)
Role.administrator?(context.claims.roles)
Role.content_developer?(context.claims.roles)
Role.mentor?(context.claims.roles)
Role.teaching_assistant?(context.claims.roles)
```

Predicates match on the role **name**, including sub-roles. So
`instructor?/1` returns `true` for both a principal Instructor and
an Instructor#TeachingAssistant. To check for only the principal role,
see [Sub-roles](#sub-roles) below.

These check **context** roles only. An institution-level
`:administrator` won't match `Role.administrator?/1`. Use
`has_role?/4` for [cross-type checks](#generic-checks-with-has_role-4).

## Roles in launch claims

After a successful launch, roles are available on the claims struct:

```elixir
{:ok, context} = Ltix.handle_callback(params, state)

context.claims.roles
#=> [%Role{type: :context, name: :instructor, ...}]

context.claims.unrecognized_roles
#=> ["http://example.com/custom-role"]
```

Recognized role URIs become `%Role{}` structs. Anything the parser
doesn't recognize goes into `unrecognized_roles` as raw URI strings.

## Building authorization logic

A typical pattern for an LTI tool:

```elixir
defmodule MyAppWeb.LtiAuth do
  alias Ltix.LaunchClaims.Role

  def authorize(context) do
    roles = context.claims.roles

    cond do
      Role.administrator?(roles) -> :admin
      Role.teaching_assistant?(roles) -> :ta
      Role.instructor?(roles) -> :instructor
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

## Role types

Every role has a **type** that determines its scope. A single launch can
include roles from any combination of these types. Which types matter
depends on what your tool does:

- A **course-level tool** (quiz engine, assignment viewer, coding
  sandbox) primarily cares about **context roles**, which describe the
  user's role in the specific course being launched.
- A **platform-level tool** (analytics dashboard, account provisioning,
  admin console) cares about **institution** or **system roles**, which
  describe the user's role at the organization or on the platform itself.

The convenience predicates (`instructor?/1`, `learner?/1`, etc.) check
context roles because that's what most tools need. For institution or
system role checks, use [`has_role?/4`](#generic-checks-with-has_role-4).

### Context roles

Context roles describe what the user does **in the specific course or
activity** being launched.

A person can have different context roles in different courses: an
instructor in CS101 might be a learner in MATH201. The platform sends
whichever context roles apply to the course that triggered the launch.

Context roles can have **sub-roles** that refine the principal role.
For example, `Instructor#TeachingAssistant` is an instructor-type role
with teaching assistant privileges. See [Sub-roles](#sub-roles) for
details on how predicates handle these.

Common context roles: `:instructor`, `:learner`, `:content_developer`,
`:mentor`, `:administrator`

### Institution roles

Institution roles describe who the person is **at the organization**,
independent of any course. These stay the same regardless of which
course is launched.

What counts as "institution" depends on the platform. It might be a
university, a school district, or an account in the platform's
hierarchy. For example, a Canvas account admin gets
`institution#Administrator` because Canvas maps its account-level admins
to institution roles, not system roles.

Common institution roles: `:faculty`, `:student`, `:staff`,
`:administrator`, `:guest`, `:alumni`

### System roles

System roles describe the person's role **on the LMS platform itself**,
the people who manage the software, not just an organization within it.
How platforms use system roles varies: Blackboard sends them for its
system-level users, while Canvas reserves them for Instructure employees
(Site Admin) and sends `system#User` as a baseline for everyone else.

Common system roles: `:user`, `:sys_admin`, `:administrator`,
`:sys_support`, `:account_admin`

## Institution vs. system boundary

Each platform draws the line between institution and system roles
differently. A root admin on a cloud-hosted Canvas instance gets
`institution#Administrator`, not `system#Administrator`. On Blackboard,
a platform-level administrator gets actual system roles.

If your tool needs to check for admin access, check both levels:

```elixir
Role.has_role?(roles, :institution, :administrator) or
  Role.has_role?(roles, :system, :administrator)
```

## Sub-roles

Context roles can include a sub-role that refines the principal role.
For example, `Instructor#TeachingAssistant` and `Instructor#Grader`
are both instructor-type roles with different privileges.

Platforms *should* send the principal role alongside a sub-role (e.g.
both `Instructor` and `Instructor#TeachingAssistant`), but this is
not guaranteed. The predicates handle this correctly: `instructor?/1`
matches any instructor, whether or not the principal role was sent
separately.

If your tool needs to distinguish between instructors and TAs, check
the sub-role first:

```elixir
cond do
  Role.teaching_assistant?(roles) -> :ta
  Role.instructor?(roles) -> :instructor
  Role.learner?(roles) -> :learner
  true -> :observer
end
```

Note that not all platforms send sub-roles (see [Platform
differences](#platform-differences)), so this distinction may only
work on some platforms.

## Generic checks with `has_role?/4`

For checks beyond context-role predicates, use `has_role?/4`:

```elixir
# Institution faculty
Role.has_role?(roles, :institution, :faculty)

# System administrator
Role.has_role?(roles, :system, :administrator)

# Exact match: principal instructor only (no sub-roles)
Role.has_role?(roles, :context, :instructor, nil)

# Exact match: specific sub-role
Role.has_role?(roles, :context, :instructor, :teaching_assistant)
```

## Platform differences

Platforms vary in which roles they send and how granular they are.

| Behavior | Canvas | Blackboard |
|---|---|---|
| TA representation | `Instructor#TeachingAssistant` sub-role | Plain `Instructor`, no sub-role |
| Institution roles | Multiple roles sent | Primary role only |
| System roles | `system#User` baseline for all users | Actual system roles for platform admins |
| Guest learners | N/A | Plain `Learner`, no sub-role |

**Canvas** ([full mapping](https://developerdocs.instructure.com/services/canvas/external-tools/file.canvas_roles.md)):

- Always sends **context roles**: TeacherEnrollment becomes
  `context#Instructor`, StudentEnrollment becomes `context#Learner`.
  TaEnrollment sends both `context#Instructor` and the
  `Instructor#TeachingAssistant` sub-role.
- Sends **institution roles** based on account-level roles: account
  admins get `institution#Administrator`, users with a "teacher" base
  role get `institution#Instructor`. A root admin may receive several
  institution roles at once.
- Sends `system#User` for ordinary users, `system#SysAdmin` for
  Instructure Site Admin users, and `system#TestUser` for Student
  View (LTI Advantage only).

**Blackboard** ([role mapping options](https://help.anthology.com/blackboard/administrator/en/integrations/learning-tools-interoperability/manage-ltis.html#role-mapping-options)):

- Maps TAs and Graders to plain `context#Instructor` **without
  sub-roles**. On Canvas, these would arrive as
  `Instructor#TeachingAssistant` or `Instructor#Grader`.
- Sends only the user's primary institution role; secondary roles
  are not included.
- Guest Learners become plain `context#Learner` with no sub-role.

The practical takeaway: don't rely on sub-roles for critical
authorization decisions. A TA might arrive as
`Instructor#TeachingAssistant` from one platform and plain `Instructor`
from another. If you need to distinguish TAs from instructors, consider
using platform-specific custom parameters or your own role management
rather than LTI sub-roles alone.

## Filtering by type

Split roles into their three categories:

```elixir
Role.context_roles(roles)       #=> [%Role{type: :context, ...}, ...]
Role.institution_roles(roles)   #=> [%Role{type: :institution, ...}, ...]
Role.system_roles(roles)        #=> [%Role{type: :system, ...}, ...]
```

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
