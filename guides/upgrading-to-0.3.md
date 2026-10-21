# Upgrading to 0.3

Every tool needs one change, [role URIs](#roles-are-uris). The other sections apply only when your tool uses what they name.

```elixir
# mix.exs
{:ltix, "~> 0.3"}
```

On 0.1, follow [Upgrading to 0.2](upgrading-to-0.2.md) first.

## Roles

### Roles are URIs

`Ltix.LaunchClaims.Role` is now `Ltix.Role`, and `roles` on launches and members are the URIs the platform sent, in its order. They include the roles 0.2 left out and listed in `unrecognized_roles`. Role parsers are gone, and passing `:role_parsers` raises `Ltix.Errors.Invalid.InvalidOption`.

| 0.2 | 0.3 |
|---|---|
| `Ltix.LaunchClaims.Role` | `Ltix.Role` |
| `%Role{}` | the role's URI |
| `Role.from_atom(:instructor)` | `Role.context_instructor()` |
| `Role.from_atom(:learner)` | `Role.context_learner()` |
| `Role.from_atom(:content_developer)` | `Role.context_content_developer()` |
| `Role.from_atom(:mentor)` | `Role.context_mentor()` |
| `Role.from_atom(:context_administrator)` | `Role.context_administrator()` |
| `Role.from_atom(:teaching_assistant)` | `Role.instructor_teaching_assistant()` |
| `Role.from_atom(:administrator)` | `Role.institution_administrator()` |
| `Role.from_atom(:faculty)` | `Role.institution_faculty()` |
| `Role.from_atom(:student)` | `Role.institution_student()` |
| `Role.from_atom(:staff)` | `Role.institution_staff()` |
| `Role.from_atom(:test_user)` | `Role.system_test_user()` |
| `Role.has_role?/3`, `Role.has_role?/4` | `Role.has?/2` |
| `Role.parse/2`, `Role.parse_all/2`, `Role.to_uri/2`, `Role.to_uri!/2` | removed |
| `Role.context_roles/1`, `Role.institution_roles/1`, `Role.system_roles/1` | kept, taking and returning URIs |
| `Ltix.LaunchClaims.Role.LIS`, `Ltix.LaunchClaims.Role.Parser`, `:role_parsers` | removed |
| `unrecognized_roles` | removed |

The checks, such as `instructor?/1` and `learner?/1`, keep their names and take the list of URIs.

```elixir
# 0.2
alias Ltix.LaunchClaims.Role
Role.instructor?(context.claims.roles)
Role.has_role?(roles, :system, :test_user)
Role.has_role?(roles, :context, :instructor, :grader)

# 0.3
alias Ltix.Role
Role.instructor?(context.claims.roles)
Role.has?(roles, Role.system_test_user())
Role.has?(roles, Role.instructor_grader())
```

`has?/2` matches one role in any of its forms, and doesn't match its sub-roles. Check a platform's own role by its URI, as in `Role.has?(roles, "https://lms.example.com/roles#CourseDesigner")`.

### Checks match deprecated forms and every sub-role

`administrator?/1` returns `true` for `person#Administrator`, which means both the institution and the system Administrator role. `instructor?/1`, `learner?/1`, `mentor?/1`, `content_developer?/1`, and `context_administrator?/1` return `true` for every sub-role of their role, including ones the LIS vocabulary doesn't list. If a user with `person#Administrator` must not count as an institution administrator, check for the URI itself.

```elixir
Role.institution_administrator() in roles
```

### Filters keep `person#Administrator`, `person#None`, and unlisted roles

0.2's `system_roles/1` kept the deprecated `person#Administrator` and `person#None` roles, and `institution_roles/1` didn't. Now both keep them.

Each filter also keeps every role under its URI prefix, even one the LTI specification doesn't list, such as `institution/person#Dean`. 0.2 put these in `unrecognized_roles`. `Ltix.Role` lists the URI prefixes each filter keeps.

To keep only the roles you name, including their deprecated forms, filter with `has?/2`.

```elixir
accepted = [Role.institution_faculty(), Role.institution_staff()]
Enum.filter(roles, fn role -> Enum.any?(accepted, &Role.has?([role], &1)) end)
```

### Role options take URIs

The `:role` filter of `list_members/2` and `stream_members/2`, and the `:roles` option of the test helpers, take URIs. Atoms and `%Role{}` structs raise `Ltix.Errors.Invalid.InvalidOption`.

```elixir
# 0.2
Ltix.MembershipsService.list_members(client, role: :learner)
Ltix.Test.build_launch_context(platform, roles: [:instructor, :teaching_assistant])

# 0.3
Ltix.MembershipsService.list_members(client, role: Ltix.Role.context_learner())
Ltix.Test.build_launch_context(platform,
  roles: [Ltix.Role.context_instructor(), Ltix.Role.instructor_teaching_assistant()]
)
```

## Errors

### Errors don't include a spec reference

An error's message doesn't end with the section of the specification its check comes from, such as `[Sec §5.1.3 step 7]`, and errors don't have a `spec_ref` field. Update code that reads `spec_ref` or matches on error messages.

## New in 0.3

- [Plugins](writing-plugins.md) extend Ltix. A tool that enables none works as before. When enabled plugins conflict, a call returns `Ltix.Errors.Unknown.InvalidPluginSet`.
