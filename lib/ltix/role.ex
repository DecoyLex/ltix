defmodule Ltix.Role do
  @moduledoc """
  Role URIs, checks, and filters for the roles in a launch or a roster.

  The checks and filters take a list of roles, such as `launch.claims.roles` or
  `member.roles`. Core defines the standard roles in its
  [role vocabularies](https://standards.1edtech.org/lti/specifications/core/lti-spec#role-vocabularies).

      Ltix.Role.instructor?(launch.claims.roles)
      Ltix.Role.learner?(member.roles)

  Use `has?/2` with a constant to check for one role.

      Ltix.Role.has?(launch.claims.roles, Ltix.Role.system_test_user())

  [Working with Roles](working-with-roles.md) covers authorization and how
  platforms differ.

  ## Filters

  `context_roles/1`, `institution_roles/1`, and `system_roles/1` return the
  roles of one kind, in the order given. A role's kind comes from the start of its
  URI.

  | Filter | Keeps URIs that start with |
  |---|---|
  | `context_roles/1` | `http://purl.imsglobal.org/vocab/lis/v2/membership#` or `http://purl.imsglobal.org/vocab/lis/v2/membership/` |
  | `institution_roles/1` | `http://purl.imsglobal.org/vocab/lis/v2/institution/person#` |
  | `system_roles/1` | `http://purl.imsglobal.org/vocab/lis/v2/system/person#` or `http://purl.imsglobal.org/vocab/lti/system/person#` |

  Each filter also keeps the [deprecated forms](#module-deprecated-forms) of
  its roles. No filter keeps a platform's own role, such as
  `"https://lms.example.com/roles#CourseDesigner"`.

  ## Constants

  Each constant returns one standard role's URI. Its name starts with one
  of these prefixes.

    * `context_` for roles in a context, such as `context_learner/0`
    * the principal role's name for context sub-roles, as in
      `instructor_teaching_assistant/0`
    * `institution_` for roles at the institution, such as
      `institution_faculty/0`
    * `system_` for roles on the platform, such as `system_test_user/0`
    * `person_` for the deprecated URIs of institution and system roles,
      such as `person_administrator/0`

  ## Deprecated forms

  Some platforms send a context role by its simple name, such as
  `"Instructor"`, or an institution or system role by a deprecated URI. The
  checks, the filters, and `has?/2` match each deprecated form as the role it
  stands for.

      iex> Ltix.Role.instructor?(["Instructor"])
      true

      iex> Ltix.Role.has?([Ltix.Role.person_faculty()], Ltix.Role.institution_faculty())
      true

  `person#Administrator` and `person#None` stand for both the institution
  role and the system role of that name. `institution_roles/1` and
  `system_roles/1` both keep them.

      iex> Ltix.Role.institution_roles([Ltix.Role.person_administrator()])
      ["http://purl.imsglobal.org/vocab/lis/v2/person#Administrator"]

      iex> Ltix.Role.system_roles([Ltix.Role.person_administrator()])
      ["http://purl.imsglobal.org/vocab/lis/v2/person#Administrator"]
  """
  @moduledoc groups: [
               %{title: "Checks", description: "Check a list of role URIs."},
               %{title: "Filters", description: "Filter a list of role URIs by kind."},
               %{title: "Context roles", description: "Roles a user has in a context."},
               %{
                 title: "Context sub-roles",
                 description: "Roles that narrow a context role, named after the principal role."
               },
               %{
                 title: "Institution roles",
                 description: "Roles a user has at the institution, whatever the context."
               },
               %{title: "System roles", description: "Roles a user has on the platform itself."},
               %{
                 title: "Deprecated roles",
                 description:
                   "Deprecated URIs of institution and system roles, which some platforms still send."
               }
             ]

  @lis "http://purl.imsglobal.org/vocab/lis/v2/"
  @context @lis <> "membership#"
  @sub_role @lis <> "membership/"
  @institution @lis <> "institution/person#"
  @system @lis <> "system/person#"
  @person @lis <> "person#"
  @lti_system "http://purl.imsglobal.org/vocab/lti/system/person#"

  # [Core, LIS vocabulary for context roles](https://standards.1edtech.org/lti/specifications/core/lti-spec#lis-vocabulary-for-context-roles)
  @context_roles ~w(Administrator ContentDeveloper Instructor Learner Mentor Manager Member Officer)

  # [Core, Context sub-roles](https://standards.1edtech.org/lti/specifications/core/lti-spec#context-sub-roles)
  @sub_roles [
    {"Administrator",
     ~w(Administrator Developer ExternalDeveloper ExternalSupport ExternalSystemAdministrator Support SystemAdministrator)},
    {"ContentDeveloper", ~w(ContentDeveloper ContentExpert ExternalContentExpert Librarian)},
    {"Instructor",
     ~w(ExternalInstructor Grader GuestInstructor Lecturer PrimaryInstructor SecondaryInstructor TeachingAssistant TeachingAssistantGroup TeachingAssistantOffering TeachingAssistantSection TeachingAssistantSectionAssociation TeachingAssistantTemplate)},
    {"Learner", ~w(ExternalLearner GuestLearner Instructor Learner NonCreditLearner)},
    {"Manager", ~w(AreaManager CourseCoordinator ExternalObserver Manager Observer)},
    {"Member", ~w(Member)},
    {"Mentor",
     ~w(Advisor Auditor ExternalAdvisor ExternalAuditor ExternalLearningFacilitator ExternalMentor ExternalReviewer ExternalTutor LearningFacilitator Mentor Reviewer Tutor)},
    {"Officer", ~w(Chair Communications Secretary Treasurer Vice-Chair)}
  ]

  # [Core, LIS vocabulary for institution roles](https://standards.1edtech.org/lti/specifications/core/lti-spec#lis-vocabulary-for-institution-roles)
  @institution_roles ~w(Administrator Faculty Guest None Other Staff Student Alumni Instructor Learner Member Mentor Observer ProspectiveStudent)

  # [Core, LIS vocabulary for system roles](https://standards.1edtech.org/lti/specifications/core/lti-spec#lis-vocabulary-for-system-roles)
  @system_roles ~w(Administrator None AccountAdmin Creator SysAdmin SysSupport User)

  # [Core, LTI vocabulary for system roles](https://standards.1edtech.org/lti/specifications/core/lti-spec#lti-vocabulary-for-system-roles)
  @lti_system_roles ~w(TestUser)

  # Institution and system roles each have a deprecated `person#` URI. This maps each
  # deprecated name to the `{vocabulary, uri}` of each role it stands for.
  # [Core, LIS vocabulary for system roles](https://standards.1edtech.org/lti/specifications/core/lti-spec#lis-vocabulary-for-system-roles)
  # [Core, LIS vocabulary for institution roles](https://standards.1edtech.org/lti/specifications/core/lti-spec#lis-vocabulary-for-institution-roles)
  @person_forms Map.new(Enum.uniq(@institution_roles ++ @system_roles), fn name ->
                  {name,
                   for(
                     {vocabulary, base, names} <- [
                       {"institution", @institution, @institution_roles},
                       {"system", @system, @system_roles}
                     ],
                     name in names,
                     do: {vocabulary, base <> name}
                   )}
                end)

  # Maps each deprecated form to the standard URIs it stands for. A context role's
  # simple name stands for its URI.
  # [Core, LIS vocabulary for context roles](https://standards.1edtech.org/lti/specifications/core/lti-spec#lis-vocabulary-for-context-roles)
  @standard_forms Map.merge(
                    Map.new(@context_roles, &{&1, [@context <> &1]}),
                    Map.new(@person_forms, fn {name, forms} ->
                      {@person <> name, Enum.map(forms, &elem(&1, 1))}
                    end)
                  )

  # Each entry is `{prefix, name, uri, summary, group}`.
  @entries List.flatten([
             for name <- @context_roles do
               {"context", name, @context <> name, "#{name} context role", "Context roles"}
             end,
             for {principal, names} <- @sub_roles, name <- names do
               {principal, name, "#{@sub_role}#{principal}##{name}",
                "#{name} sub-role of #{principal}", "Context sub-roles"}
             end,
             for name <- @institution_roles do
               {"institution", name, @institution <> name, "#{name} institution role",
                "Institution roles"}
             end,
             for {vocabulary, names} <- [
                   {@system, @system_roles},
                   {@lti_system, @lti_system_roles}
                 ],
                 name <- names do
               {"system", name, vocabulary <> name, "#{name} system role", "System roles"}
             end,
             for {name, forms} <- @person_forms do
               labels = Enum.map(forms, &elem(&1, 0))
               roles = if length(labels) == 1, do: "role", else: "roles"

               {"person", name, @person <> name,
                "deprecated form of the #{name} #{Enum.join(labels, " and ")} #{roles}",
                "Deprecated roles"}
             end
           ])

  # Each constant is `{function, uri, summary, group}`.
  @constants (for {prefix, name, uri, summary, group} <- @entries do
                {:"#{Macro.underscore(prefix)}_#{Macro.underscore(String.replace(name, "-", ""))}",
                 uri, summary, group}
              end)

  @doc group: "Checks"
  @doc """
  Returns `true` when any of `roles` is `role`, in any of its forms.

  A sub-role in `roles` matches only that sub-role, not its principal role.

  ## Examples

      iex> Ltix.Role.has?([Ltix.Role.system_test_user()], Ltix.Role.system_test_user())
      true

      iex> Ltix.Role.has?(["Learner"], Ltix.Role.context_learner())
      true

      iex> Ltix.Role.has?([Ltix.Role.instructor_grader()], Ltix.Role.context_instructor())
      false
  """
  @spec has?([String.t()], String.t()) :: boolean()
  def has?(roles, role) do
    forms = standard_forms(role)
    Enum.any?(roles, fn sent -> Enum.any?(standard_forms(sent), &(&1 in forms)) end)
  end

  @doc group: "Filters"
  @doc """
  Returns the [context roles](#module-filters) in `roles`.

  ## Examples

      iex> Ltix.Role.context_roles([
      ...>   Ltix.Role.context_instructor(),
      ...>   Ltix.Role.institution_faculty(),
      ...>   "Learner"
      ...> ])
      ["http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor", "Learner"]
  """
  @spec context_roles([String.t()]) :: [String.t()]
  def context_roles(roles), do: of_kind(roles, :context)

  @doc group: "Filters"
  @doc """
  Returns the [institution roles](#module-filters) in `roles`.

  ## Examples

      iex> Ltix.Role.institution_roles([
      ...>   Ltix.Role.institution_faculty(),
      ...>   Ltix.Role.context_instructor(),
      ...>   Ltix.Role.person_student()
      ...> ])
      [
        "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Faculty",
        "http://purl.imsglobal.org/vocab/lis/v2/person#Student"
      ]
  """
  @spec institution_roles([String.t()]) :: [String.t()]
  def institution_roles(roles), do: of_kind(roles, :institution)

  @doc group: "Filters"
  @doc """
  Returns the [system roles](#module-filters) in `roles`.

  ## Examples

      iex> Ltix.Role.system_roles([
      ...>   Ltix.Role.context_learner(),
      ...>   Ltix.Role.system_test_user(),
      ...>   Ltix.Role.person_sys_admin()
      ...> ])
      [
        "http://purl.imsglobal.org/vocab/lti/system/person#TestUser",
        "http://purl.imsglobal.org/vocab/lis/v2/person#SysAdmin"
      ]
  """
  @spec system_roles([String.t()]) :: [String.t()]
  def system_roles(roles), do: of_kind(roles, :system)

  @doc group: "Checks"
  @doc """
  Returns `true` when any of `roles` is the Instructor context role or one of its sub-roles, in any form.

  ## Examples

      iex> Ltix.Role.instructor?([Ltix.Role.context_instructor()])
      true

      iex> Ltix.Role.instructor?([Ltix.Role.instructor_teaching_assistant()])
      true

      iex> Ltix.Role.instructor?(["Instructor"])
      true

      iex> Ltix.Role.instructor?([Ltix.Role.institution_instructor()])
      false
  """
  @spec instructor?([String.t()]) :: boolean()
  def instructor?(roles), do: context_role?(roles, "Instructor")

  @doc group: "Checks"
  @doc """
  Returns `true` when any of `roles` is the Learner context role or one of its sub-roles, in any form.

  ## Examples

      iex> Ltix.Role.learner?([Ltix.Role.context_learner()])
      true

      iex> Ltix.Role.learner?([Ltix.Role.learner_guest_learner()])
      true

      iex> Ltix.Role.learner?(["Learner"])
      true

      iex> Ltix.Role.learner?([Ltix.Role.institution_student()])
      false
  """
  @spec learner?([String.t()]) :: boolean()
  def learner?(roles), do: context_role?(roles, "Learner")

  @doc group: "Checks"
  @doc """
  Returns `true` when any of `roles` is the Mentor context role or one of its sub-roles, in any form.

  ## Examples

      iex> Ltix.Role.mentor?([Ltix.Role.context_mentor()])
      true

      iex> Ltix.Role.mentor?([Ltix.Role.mentor_advisor()])
      true

      iex> Ltix.Role.mentor?(["Mentor"])
      true

      iex> Ltix.Role.mentor?([Ltix.Role.institution_mentor()])
      false
  """
  @spec mentor?([String.t()]) :: boolean()
  def mentor?(roles), do: context_role?(roles, "Mentor")

  @doc group: "Checks"
  @doc """
  Returns `true` when any of `roles` is the ContentDeveloper context role or one of its sub-roles, in any form.

  ## Examples

      iex> Ltix.Role.content_developer?([Ltix.Role.context_content_developer()])
      true

      iex> Ltix.Role.content_developer?([Ltix.Role.content_developer_librarian()])
      true

      iex> Ltix.Role.content_developer?(["ContentDeveloper"])
      true

      iex> Ltix.Role.content_developer?([Ltix.Role.context_instructor()])
      false
  """
  @spec content_developer?([String.t()]) :: boolean()
  def content_developer?(roles), do: context_role?(roles, "ContentDeveloper")

  @doc group: "Checks"
  @doc """
  Returns `true` when any of `roles` is the Administrator context role or one of its sub-roles, in any form.

  `administrator?/1` checks the institution role.

  ## Examples

      iex> Ltix.Role.context_administrator?([Ltix.Role.context_administrator()])
      true

      iex> Ltix.Role.context_administrator?([Ltix.Role.administrator_support()])
      true

      iex> Ltix.Role.context_administrator?(["Administrator"])
      true

      iex> Ltix.Role.context_administrator?([Ltix.Role.institution_administrator()])
      false
  """
  @spec context_administrator?([String.t()]) :: boolean()
  def context_administrator?(roles), do: context_role?(roles, "Administrator")

  @doc group: "Checks"
  @doc """
  Returns `true` when any of `roles` is the Administrator institution role, in any form.

  `context_administrator?/1` checks the context role.

  ## Examples

      iex> Ltix.Role.administrator?([Ltix.Role.institution_administrator()])
      true

      iex> Ltix.Role.administrator?([Ltix.Role.person_administrator()])
      true

      iex> Ltix.Role.administrator?([Ltix.Role.context_administrator()])
      false

      iex> Ltix.Role.administrator?([Ltix.Role.system_administrator()])
      false
  """
  @spec administrator?([String.t()]) :: boolean()
  def administrator?(roles), do: has?(roles, institution_administrator())

  @doc group: "Checks"
  @doc """
  Returns `true` when any of `roles` is the TeachingAssistant sub-role of Instructor.

  ## Examples

      iex> Ltix.Role.teaching_assistant?([Ltix.Role.instructor_teaching_assistant()])
      true

      iex> Ltix.Role.teaching_assistant?([Ltix.Role.context_instructor()])
      false
  """
  @spec teaching_assistant?([String.t()]) :: boolean()
  def teaching_assistant?(roles), do: has?(roles, instructor_teaching_assistant())

  for {function, uri, summary, group} <- @constants do
    @doc group: group
    @doc """
    Returns the URI of the #{summary}.

    ## Examples

        iex> Ltix.Role.#{function}()
        "#{uri}"
    """
    @spec unquote(function)() :: String.t()
    def unquote(function)(), do: unquote(uri)
  end

  # A sub-role belongs to its principal role, whether or not the platform
  # also sends the principal role.
  # [Core, Context sub-roles](https://standards.1edtech.org/lti/specifications/core/lti-spec#context-sub-roles)
  defp context_role?(roles, principal) do
    sub_role = @sub_role <> principal <> "#"
    has?(roles, @context <> principal) || Enum.any?(roles, &String.starts_with?(&1, sub_role))
  end

  defp standard_forms(role), do: Map.get(@standard_forms, role, [role])

  defp of_kind(roles, kind) do
    Enum.filter(roles, fn role -> Enum.any?(standard_forms(role), &(kind(&1) == kind)) end)
  end

  # A standard role has the kind of its vocabulary.
  # [Core, Role vocabularies](https://standards.1edtech.org/lti/specifications/core/lti-spec#role-vocabularies)
  defp kind(@context <> _name), do: :context
  defp kind(@sub_role <> _name), do: :context
  defp kind(@institution <> _name), do: :institution
  defp kind(@system <> _name), do: :system
  defp kind(@lti_system <> _name), do: :system
  defp kind(_role), do: nil
end
