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
`:mentor`. All major platforms send at least `:instructor` and
`:learner`. Canvas also sends `:content_developer` and `:mentor`;
other platforms may or may not depending on configuration.

### Institution roles

Institution roles describe who the person is **at the organization**,
independent of any course. These stay the same regardless of which
course is launched.

What counts as "institution" depends on the platform. It might be a
university, a school district, or an account in the platform's
hierarchy. For example, a Canvas account admin gets
`institution#Administrator` because Canvas maps its account-level admins
to institution roles, not system roles.

Common institution roles: `:administrator`, `:faculty`, `:student`,
`:staff`. Note that only Canvas reliably sends institution roles by
default. Blackboard and Brightspace can be configured to send them,
while Moodle and Sakai generally do not.

### System roles

System roles describe the person's role **on the LMS platform itself**,
the people who manage the software, not just an organization within it.

Common system roles: `:test_user`, `:user`, `:sys_admin`. In practice,
only Canvas sends system roles: `system#User` as a baseline for all
users, `system#SysAdmin` for Instructure Site Admin users, and
`system#TestUser` for Student View launches.

## Institution vs. system boundary

Each platform draws the line between institution and system roles
differently, and most platforms don't send both types. Canvas is the
only major platform that reliably sends institution and system roles.
A root admin on a cloud-hosted Canvas instance gets
`institution#Administrator`, not `system#Administrator`.

If your tool needs to check for admin access, check both levels:

```elixir
Role.has_role?(roles, :institution, :administrator) or
  Role.has_role?(roles, :system, :administrator)
```

Keep in mind that on Moodle, admins may just show up as plain
`context#Instructor`, so role-based admin detection across platforms
may require platform-specific logic or custom parameters.

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

> #### Sub-roles are not well-supported across platforms {: .warning}
> No platform consistently sends sub-roles, and most sub-roles are not
> sent by *any* platform. The only widely-supported sub-role is
> `Instructor#TeachingAssistant`, which only Canvas and Sakai send by
> default.  On Moodle, TAs are indistinguishable from instructors.
> On Blackboard and Brightspace, it depends on the institution's
> configuration. See [Platform differences](#platform-differences)
> for details.

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

Platforms vary significantly in which roles they send and how granular
they are. The table below shows what each platform sends by default
(not what's possible with admin configuration).

| Behavior | Canvas | Moodle | Blackboard | Brightspace | Sakai |
|---|---|---|---|---|---|
| TA as sub-role | ✅ Yes | ❌ No | ❌ No | ❌ No | ✅ Yes |
| ContentDeveloper | ✅ Yes | ❌ No | ❌ No | ❌ No | ✅ Yes |
| Mentor | ✅ Yes | ❌ No | ❌ No | ❌ No | ❌ No |
| Institution roles | ✅ Yes | ❌ No | ❔ Configurable | ❔ Configurable | ❌ No |
| System roles | ✅ Yes | ❌ No | ❌ No | ❌ No | ❌ No |
| Configurable mapping | ❌ No | ❌ No | ✅ Yes | ✅ Yes | ✅ Yes |

### Canvas

[Full mapping](https://developerdocs.instructure.com/services/canvas/external-tools/file.canvas_roles)

Canvas has **hardcoded** role mappings that admins cannot change:

- TeacherEnrollment becomes `membership#Instructor`
- TaEnrollment sends **both** `membership#Instructor` and the
  `Instructor#TeachingAssistant` sub-role
- StudentEnrollment becomes `membership#Learner`
- DesignerEnrollment becomes `membership#ContentDeveloper`
- ObserverEnrollment becomes `membership#Mentor`
- StudentViewEnrollment sends `membership#Learner` plus
  `system#TestUser`
- Group members get `membership#Member`, group leaders get
  `membership#Member` plus `membership#Manager`

Canvas also sends **institution roles** based on account-level
permissions: account admins get `institution#Administrator`, users with
a "teacher" base role get `institution#Instructor`. A root admin may
receive multiple institution roles. For system roles, ordinary users
get `system#User`, Instructure Site Admin users get `system#SysAdmin`.

Canvas is the most granular platform, so tools built against it may
over-rely on roles that other platforms don't send.

### Moodle

Moodle is the **least granular** platform. It sends only two context
roles:

- `membership#Instructor` for anyone with the
  `moodle/course:manageactivities` capability (teachers, TAs, course
  creators, and admins alike)
- `membership#Learner` for everyone else

No sub-roles, no ContentDeveloper, no institution or system roles (site
admins may receive an institution Administrator in some configurations).
This means TAs, course designers, and instructors are all
indistinguishable in the LTI launch. This is a [known
limitation](https://tracker.moodle.org/browse/MDL-75368).

Any tool that needs to work with Moodle cannot depend on sub-roles or
on distinguishing TAs from instructors via roles alone.

### Blackboard

[Role mapping options](https://help.anthology.com/blackboard/administrator/en/integrations/learning-tools-interoperability/manage-ltis.html#role-mapping-options)

Blackboard has **admin-configurable** role mapping. Before
configuration, all privileged users are sent as plain `Instructor`.
Administrators can map each Blackboard course role to a standard LTI
role from a dropdown that includes Administrator, ContentDeveloper,
Instructor, Learner, Manager, Member, Mentor, and TeachingAssistant.

Because the mapping depends on each institution's configuration, a tool
may receive any valid principal role from Blackboard. Sub-roles are
generally not sent. Guest Learners become plain `membership#Learner`.

### Brightspace (D2L)

Brightspace has **admin-configurable** IMS role mapping (under Admin
Tools > IMS Configuration). Administrators map each Brightspace role
(Instructor, Teaching Assistant, Student, Guest, Administrator, Course
Builder, Librarian) to a standard IMS role.

The default mapping sends principal roles (`membership#Instructor`,
`membership#Learner`). TeachingAssistant is available as a configurable
option. Like Blackboard, what you receive depends on how each
institution configured their mapping.

### Sakai

Sakai has explicit default mappings that are configurable via
`lti.outbound.role.map` in `sakai.properties`:

- admin and maintain roles become `membership#Instructor`
- access role becomes `membership#Learner`
- Teaching Assistant sends **both** `membership#Instructor` and the
  `Instructor#TeachingAssistant` sub-role
- ContentDeveloper sends `membership#ContentDeveloper`

Per-tool overrides are also possible.

### Practical takeaways

**Don't rely on sub-roles for critical authorization.** A TA arrives as
`Instructor#TeachingAssistant` from Canvas and Sakai, but as plain
`Instructor` from Moodle, Blackboard, and Brightspace. If you need to
distinguish TAs from instructors, use platform-specific custom
parameters or your own role management.

**Design for the lowest common denominator.** If your tool needs to work
across platforms, assume you'll only reliably get `Instructor` vs
`Learner`. Everything else is a bonus.

**Blackboard and Brightspace are wildcards.** Their role mappings are
admin-configurable, so you might receive any valid IMS role depending on
how the institution set things up.

## Filtering by type

Split roles into their three categories:

```elixir
Role.context_roles(roles)       #=> [%Role{type: :context, ...}, ...]
Role.institution_roles(roles)   #=> [%Role{type: :institution, ...}, ...]
Role.system_roles(roles)        #=> [%Role{type: :system, ...}, ...]
```

## Building roles from atoms

`Role.from_atom/1` builds a `%Role{}` from a well-known atom. This is
handy in test helpers and anywhere you need a role struct without
spelling out a full URI:

```elixir
Role.from_atom(:instructor)
#=> %Role{type: :context, name: :instructor, uri: "http://...#Instructor"}

Role.from_atom(:teaching_assistant)
#=> %Role{type: :context, name: :instructor, sub_role: :teaching_assistant, uri: "http://.../Instructor#TeachingAssistant"}

Role.from_atom(:faculty)
#=> %Role{type: :institution, name: :faculty, uri: "http://...#Faculty"}

Role.from_atom(:test_user)
#=> %Role{type: :system, name: :test_user, uri: "http://...#TestUser"}
```

Supported atoms:

| Atom | Type | Notes |
|------|------|-------|
| `:instructor` | context | Course instructor |
| `:learner` | context | Course learner (enrolled in a specific course) |
| `:content_developer` | context | Course designer |
| `:mentor` | context | Observer / mentor |
| `:teaching_assistant` | context sub-role | Resolves to Instructor#TeachingAssistant |
| `:administrator` | institution | Institution-level admin |
| `:faculty` | institution | Institution faculty member |
| `:student` | institution | Enrolled at the institution (not course-specific, unlike `:learner`) |
| `:staff` | institution | Institution staff |
| `:test_user` | system | Synthetic test user (e.g. Canvas Student View) |

> **`:learner` vs `:student`:** `:learner` is a context role, meaning the
> person is enrolled in a specific course. `:student` is an institution
> role, meaning the person is enrolled at the institution. A user can be
> a `:student` at an institution without being a `:learner` in any
> particular course.

Unknown atoms raise `ArgumentError`. For roles not covered here, use
`Role.parse/1` with the full URI string, or construct the `%Role{}`
struct directly.

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
