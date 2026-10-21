# Working with Roles

Platforms send each user's roles as URIs in the launch. Ltix keeps them as sent in `context.claims.roles`, and `Ltix.Role` has checks and constants for them. Most tools only need the checks in the next section.

## Checking roles

The most common check is "is this user an instructor or a learner?"

```elixir
alias Ltix.Role

Role.instructor?(context.claims.roles)
Role.learner?(context.claims.roles)
Role.mentor?(context.claims.roles)
Role.content_developer?(context.claims.roles)
Role.teaching_assistant?(context.claims.roles)
Role.context_administrator?(context.claims.roles)
Role.administrator?(context.claims.roles)
```

Every check covers its role's deprecated forms, and the checks for context roles also cover sub-roles. So `instructor?/1` returns `true` for a principal Instructor, for an `Instructor#TeachingAssistant`, and for the simple name `"Instructor"`.

`administrator?/1` checks for the **institution** administrator. The other checks, including `context_administrator?/1`, check **context** roles. Use [`has?/2`](#checking-for-one-role) for any other role.

## Roles in launch claims

After a successful launch, `context.claims.roles` has the role URIs in the order the platform sent them.

```elixir
{:ok, context} = Ltix.handle_callback(params, state)

context.claims.roles
#=> ["http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor",
#=>  "http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant",
#=>  "https://lms.example.com/roles#CourseDesigner"]
```

A platform can send roles of its own, such as the last URI above. LTI requires a platform that sends roles to include at least one standard role, so the checks apply to every launch with roles.

Roster members from the [memberships service](memberships-service.md) have role URIs in `member.roles`, and the same checks work on them.

## Checking for one role

`has?/2` checks for one role, given a constant from `Ltix.Role` or any URI.

```elixir
# Canvas Student View and other test users
Role.has?(roles, Role.system_test_user())

# A principal Instructor, not its sub-roles
Role.has?(roles, Role.context_instructor())

# A sub-role
Role.has?(roles, Role.instructor_grader())

# A platform's own role
Role.has?(roles, "https://lms.example.com/roles#CourseDesigner")
```

A sub-role matches only itself, so `Role.has?([Role.instructor_grader()], Role.context_instructor())` is `false`.

| Constant prefix | Roles | Example |
|---|---|---|
| `context_` | Context roles | `Role.context_learner()` |
| A principal role, such as `instructor_` | Its sub-roles | `Role.instructor_teaching_assistant()` |
| `institution_` | Institution roles | `Role.institution_faculty()` |
| `system_` | System roles | `Role.system_test_user()` |
| `person_` | Deprecated institution and system roles | `Role.person_administrator()` |

`Role.context_learner()` means enrolled in this context. `Role.institution_student()` means enrolled at the institution, in any context or none.

## Filtering roles by kind

`Ltix.Role.context_roles/1`, `Ltix.Role.institution_roles/1`, and `Ltix.Role.system_roles/1` return the [context](#context-roles), [institution](#institution-roles), or [system roles](#system-roles) from a list. None of them keep roles under a platform's own URIs.

```elixir
roles = [
  Role.context_instructor(),
  Role.institution_faculty(),
  "https://lms.example.com/roles#CourseDesigner"
]

Role.context_roles(roles)
#=> ["http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"]

Role.institution_roles(roles)
#=> ["http://purl.imsglobal.org/vocab/lis/v2/institution/person#Faculty"]
```

Each filter keeps every role under the filter's URI prefix, even one the specification doesn't list, such as `institution/person#Dean`. `Ltix.Role` lists the prefixes. Each filter also keeps [deprecated forms](#deprecated-forms). Both `institution_roles/1` and `system_roles/1` keep the deprecated `person#Administrator` and `person#None` URIs.

This finds an institution administrator with no role in the launch's context.

```elixir
Role.administrator?(launch.claims.roles) and Role.context_roles(launch.claims.roles) == []
```

## Building authorization logic

The following is a typical pattern for an LTI tool.

```elixir
defmodule MyAppWeb.LtiAuth do
  alias Ltix.Role

  def authorize(context) do
    roles = context.claims.roles

    cond do
      Role.administrator?(roles) -> :administrator
      Role.teaching_assistant?(roles) -> :teaching_assistant
      Role.instructor?(roles) -> :instructor
      Role.learner?(roles) -> :learner
      true -> :observer
    end
  end
end
```

Use the result to control access in your controller.

```elixir
def launch(conn, params) do
  {:ok, context} = Ltix.handle_callback(params, get_session(conn, :lti_state))
  role = MyAppWeb.LtiAuth.authorize(context)

  conn
  |> put_session(:lti_role, role)
  |> put_session(:lti_user_id, context.claims.subject)
  |> redirect(to: dashboard_path(role))
end

defp dashboard_path(:administrator), do: ~p"/administration"
defp dashboard_path(:instructor), do: ~p"/manage"
defp dashboard_path(:teaching_assistant), do: ~p"/manage"
defp dashboard_path(_), do: ~p"/learn"
```

## Role vocabularies

Every standard role belongs to the context, institution, or system vocabulary. A single launch can include roles from any combination of vocabularies. Which ones matter depends on what your tool does.

- A **context-level tool** (quiz engine, assignment viewer, coding sandbox) mostly uses **context roles**, which describe the user's role in the context of the launch.
- A **platform-level tool** (analytics dashboard, account provisioning, administrator console) uses **institution** or **system roles**, which describe the user's role at the organization or on the platform itself.

The checks cover context roles because that's what most tools need, except `administrator?/1`, which checks the institution administrator. For other institution or system roles, use [`has?/2`](#checking-for-one-role).

### Context roles

Context roles describe what the user does **in the context of the launch**.

A person can have different context roles in different contexts. An instructor in CS101 might be a learner in MATH201. The platform sends whichever context roles apply to the context of the launch.

Context roles can have **sub-roles** that refine the principal role. For example, `Instructor#TeachingAssistant` is an instructor role with teaching assistant privileges. See [Sub-roles](#sub-roles) for how the checks handle these.

Common context roles are `Ltix.Role.context_instructor/0`, `Ltix.Role.context_learner/0`, `Ltix.Role.context_content_developer/0`, and `Ltix.Role.context_mentor/0`. All major platforms send at least Instructor and Learner. Canvas and Sakai also send ContentDeveloper, and Canvas sends Mentor. Other platforms may or may not, depending on configuration.

### Institution roles

Institution roles describe who the person is **at the organization**, independent of any context. These stay the same whichever context the launch is in.

What counts as "institution" depends on the platform. It might be a university, a school district, or an account in the platform's hierarchy. For example, a Canvas account administrator gets `institution#Administrator` because Canvas maps its account-level administrators to institution roles, not system roles.

Common institution roles are `Ltix.Role.institution_administrator/0`, `Ltix.Role.institution_faculty/0`, `Ltix.Role.institution_student/0`, and `Ltix.Role.institution_staff/0`. Only Canvas reliably sends institution roles by default. Blackboard and Brightspace can be configured to send them, while Moodle and Sakai generally do not.

### System roles

System roles describe the person's role **on the platform itself**. They apply to the people who manage the software.

Common system roles are `Ltix.Role.system_test_user/0`, `Ltix.Role.system_user/0`, and `Ltix.Role.system_sys_admin/0`. In practice, only Canvas sends system roles, which are `system#User` as a baseline for all users, `system#SysAdmin` for Instructure Site Admin users, and `system#TestUser` for Student View launches.

## Institution vs. system boundary

Each platform divides institution and system roles differently, and most platforms don't send both. Canvas is the only major platform that reliably sends institution and system roles. A root administrator on a cloud-hosted Canvas instance gets `institution#Administrator`, not `system#Administrator`.

If your tool needs to check for administrator access, check both levels.

```elixir
Role.administrator?(roles) or Role.has?(roles, Role.system_administrator())
```

On Moodle, administrators may be sent as plain `membership#Instructor`, so role-based administrator detection across platforms may require platform-specific logic or custom properties.

## Sub-roles

Context roles can include a sub-role that refines the principal role. For example, `Instructor#TeachingAssistant` and `Instructor#Grader` are both instructor roles with different privileges.

Platforms *should* send the principal role alongside a sub-role (for example both `Instructor` and `Instructor#TeachingAssistant`), but this is not guaranteed. The checks handle this, so `instructor?/1` matches any instructor, whether or not the principal role was sent separately.

If your tool needs to distinguish between instructors and teaching assistants, check the sub-role first.

```elixir
cond do
  Role.teaching_assistant?(roles) -> :teaching_assistant
  Role.instructor?(roles) -> :instructor
  Role.learner?(roles) -> :learner
  true -> :observer
end
```

> #### Sub-roles are not well-supported across platforms {: .warning}
>
> No platform consistently sends sub-roles, and most sub-roles are not sent by *any* platform. The only widely-supported sub-role is `Instructor#TeachingAssistant`, which only Canvas and Sakai send by default. On Moodle, teaching assistants are indistinguishable from instructors. On Blackboard and Brightspace, it depends on the institution's configuration. See [Platform differences](#platform-differences) for details.

## Deprecated forms

Older platforms may send roles in forms that LTI 1.3 deprecates.

- A context role by its simple name, such as `"Instructor"` or `"Learner"`
- An institution or system role with a `person#` URI, such as `http://purl.imsglobal.org/vocab/lis/v2/person#Administrator`, which leaves out `institution/` or `system/`

`context.claims.roles` keeps these as sent. The checks and `has?/2` treat each one as the role it stands for. A `person#` URI can stand for an institution role and a system role at once, so `Role.has?([Role.person_administrator()], Role.system_administrator())` and `Role.administrator?([Role.person_administrator()])` both return `true`.

## Platform differences

Platforms vary significantly in which roles they send and how granular they are. The table below shows what each platform sends by default.

| Behavior | Canvas | Moodle | Blackboard | Brightspace | Sakai |
|---|---|---|---|---|---|
| Teaching assistant as sub-role | ✅ Yes | ❌ No | ❌ No | ❌ No | ✅ Yes |
| ContentDeveloper | ✅ Yes | ❌ No | ❌ No | ❌ No | ✅ Yes |
| Mentor | ✅ Yes | ❌ No | ❌ No | ❌ No | ❌ No |
| Institution roles | ✅ Yes | ❌ No | ❔ Configurable | ❔ Configurable | ❌ No |
| System roles | ✅ Yes | ❌ No | ❌ No | ❌ No | ❌ No |
| Configurable mapping | ❌ No | ❌ No | ✅ Yes | ✅ Yes | ✅ Yes |

### Canvas

[Full mapping](https://developerdocs.instructure.com/services/canvas/external-tools/file.canvas_roles)

Canvas has **hardcoded** role mappings that administrators cannot change.

- TeacherEnrollment becomes `membership#Instructor`
- TaEnrollment sends **both** `membership#Instructor` and the `Instructor#TeachingAssistant` sub-role
- StudentEnrollment becomes `membership#Learner`
- DesignerEnrollment becomes `membership#ContentDeveloper`
- ObserverEnrollment becomes `membership#Mentor`
- StudentViewEnrollment sends `membership#Learner` plus `system#TestUser`
- Group members get `membership#Member`, group leaders get `membership#Member` plus `membership#Manager`

Canvas also sends **institution roles** based on account-level permissions. Account administrators get `institution#Administrator`, and users with a "teacher" base role get `institution#Instructor`. A root administrator may receive multiple institution roles. For system roles, ordinary users get `system#User`, Instructure Site Admin users get `system#SysAdmin`.

Canvas is the most granular platform, so tools built against it may over-rely on roles that other platforms don't send.

### Moodle

Moodle is the **least granular** platform. It sends only two context roles.

- `membership#Instructor` for anyone with the `moodle/course:manageactivities` capability (teachers, teaching assistants, course creators, and administrators alike)
- `membership#Learner` for everyone else

No sub-roles, no ContentDeveloper, no institution or system roles (site administrators may receive an institution Administrator in some configurations). This means teaching assistants, course designers, and instructors are all indistinguishable in the LTI launch. This is a [known limitation](https://tracker.moodle.org/browse/MDL-72066).

Any tool that needs to work with Moodle cannot depend on sub-roles or on distinguishing teaching assistants from instructors via roles alone.

### Blackboard

[Role mapping options](https://help.anthology.com/blackboard/administrator/en/integrations/learning-tools-interoperability/manage-ltis.html#role-mapping-options)

Blackboard has role mapping **configurable by administrators**. Before configuration, all privileged users are sent as plain `Instructor`. Administrators can map each Blackboard course role to a standard LTI role from a dropdown that includes Administrator, ContentDeveloper, Instructor, Learner, Manager, Member, Mentor, and TeachingAssistant.

Because the mapping depends on each institution's configuration, a tool may receive any valid principal role from Blackboard. Sub-roles are generally not sent. Guest Learners become plain `membership#Learner`.

### Brightspace (D2L)

Brightspace has IMS role mapping **configurable by administrators** (under Admin Tools > IMS Configuration). Administrators map each Brightspace role (Instructor, Teaching Assistant, Student, Guest, Administrator, Course Builder, Librarian) to a standard IMS role.

The default mapping sends principal roles (`membership#Instructor`, `membership#Learner`). TeachingAssistant is available as a configurable option. Like Blackboard, what you receive depends on how each institution configured their mapping.

### Sakai

Sakai has explicit default mappings that are configurable via `lti.outbound.role.map` in `sakai.properties`.

- admin and maintain roles become `membership#Instructor`
- access role becomes `membership#Learner`
- Teaching Assistant sends **both** `membership#Instructor` and the `Instructor#TeachingAssistant` sub-role
- ContentDeveloper sends `membership#ContentDeveloper`

Per-tool overrides are also possible.

### Practical takeaways

**Don't rely on sub-roles for critical authorization.** A teaching assistant is sent as `Instructor#TeachingAssistant` from Canvas and Sakai, but as plain `Instructor` from Moodle, Blackboard, and Brightspace. If you need to distinguish teaching assistants from instructors, use platform-specific custom properties or your own role management.

**Design for the roles every platform sends.** If your tool needs to work across platforms, assume you'll only reliably get `Instructor` vs `Learner`. Treat every other role as optional.

**Blackboard and Brightspace roles are unpredictable.** Administrators configure their role mappings, so you might receive any valid IMS role depending on how the institution set things up.

## Roles in tests

`Ltix.Test.build_launch_context/2` and `Ltix.Test.launch_params/2` take role URIs in `:roles`. They default to an instructor.

```elixir
context =
  Ltix.Test.build_launch_context(platform,
    roles: [Role.context_instructor(), Role.instructor_teaching_assistant()]
  )

Role.teaching_assistant?(context.claims.roles)
#=> true
```

## Next steps

- `Ltix.Role` lists every check and constant
- [Memberships Service](memberships-service.md) filters a roster by role
- [Hardening Your Tool](hardening.md) covers authorization after the launch
- [Testing LTI Launches](cookbooks/testing-lti-launches.md) builds launches with any roles
