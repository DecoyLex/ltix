defmodule Ltix.LaunchClaims.Role.LIS do
  @moduledoc """
  LIS (Learning Information Services) role vocabulary parser.

  Parses role URIs from the standard LIS vocabulary into `%Role{}` structs.
  Covers context roles, context sub-roles, institution roles, system roles
  (LIS and LTI), and deprecated URI forms.
  """
  use Ltix.LaunchClaims.Role.Parser

  alias Ltix.LaunchClaims.Role
  alias Ltix.LaunchClaims.Role.Parser

  # --- Role Vocabulary Tables ---

  # Context roles [Core §A.2.3](https://www.imsglobal.org/spec/lti/v1p3/#lis-vocabulary-for-context-roles)
  @context_base "http://purl.imsglobal.org/vocab/lis/v2/membership#"
  @context_roles %{
    "Administrator" => :administrator,
    "ContentDeveloper" => :content_developer,
    "Instructor" => :instructor,
    "Learner" => :learner,
    "Mentor" => :mentor,
    "Manager" => :manager,
    "Member" => :member,
    "Officer" => :officer
  }

  # Context sub-roles [Core §A.2.3.1](https://www.imsglobal.org/spec/lti/v1p3/#context-sub-roles)
  # Maps {PrincipalRole, SubRole} => atom for bidirectional lookup.
  @sub_role_base "http://purl.imsglobal.org/vocab/lis/v2/membership/"
  @context_sub_roles %{
    {"Administrator", "Administrator"} => :administrator,
    {"Administrator", "Developer"} => :developer,
    {"Administrator", "ExternalDeveloper"} => :external_developer,
    {"Administrator", "ExternalSupport"} => :external_support,
    {"Administrator", "ExternalSystemAdministrator"} => :external_system_administrator,
    {"Administrator", "Support"} => :support,
    {"Administrator", "SystemAdministrator"} => :system_administrator,
    {"ContentDeveloper", "ContentDeveloper"} => :content_developer,
    {"ContentDeveloper", "ContentExpert"} => :content_expert,
    {"ContentDeveloper", "ExternalContentExpert"} => :external_content_expert,
    {"ContentDeveloper", "Librarian"} => :librarian,
    {"Instructor", "ExternalInstructor"} => :external_instructor,
    {"Instructor", "Grader"} => :grader,
    {"Instructor", "GuestInstructor"} => :guest_instructor,
    {"Instructor", "Lecturer"} => :lecturer,
    {"Instructor", "PrimaryInstructor"} => :primary_instructor,
    {"Instructor", "SecondaryInstructor"} => :secondary_instructor,
    {"Instructor", "TeachingAssistant"} => :teaching_assistant,
    {"Instructor", "TeachingAssistantGroup"} => :teaching_assistant_group,
    {"Instructor", "TeachingAssistantOffering"} => :teaching_assistant_offering,
    {"Instructor", "TeachingAssistantSection"} => :teaching_assistant_section,
    {"Instructor", "TeachingAssistantSectionAssociation"} =>
      :teaching_assistant_section_association,
    {"Instructor", "TeachingAssistantTemplate"} => :teaching_assistant_template,
    {"Learner", "ExternalLearner"} => :external_learner,
    {"Learner", "GuestLearner"} => :guest_learner,
    {"Learner", "Instructor"} => :instructor,
    {"Learner", "Learner"} => :learner,
    {"Learner", "NonCreditLearner"} => :non_credit_learner,
    {"Manager", "AreaManager"} => :area_manager,
    {"Manager", "CourseCoordinator"} => :course_coordinator,
    {"Manager", "ExternalObserver"} => :external_observer,
    {"Manager", "Manager"} => :manager,
    {"Manager", "Observer"} => :observer,
    {"Member", "Member"} => :member,
    {"Mentor", "Advisor"} => :advisor,
    {"Mentor", "Auditor"} => :auditor,
    {"Mentor", "ExternalAdvisor"} => :external_advisor,
    {"Mentor", "ExternalAuditor"} => :external_auditor,
    {"Mentor", "ExternalLearningFacilitator"} => :external_learning_facilitator,
    {"Mentor", "ExternalMentor"} => :external_mentor,
    {"Mentor", "ExternalReviewer"} => :external_reviewer,
    {"Mentor", "ExternalTutor"} => :external_tutor,
    {"Mentor", "LearningFacilitator"} => :learning_facilitator,
    {"Mentor", "Mentor"} => :mentor,
    {"Mentor", "Reviewer"} => :reviewer,
    {"Mentor", "Tutor"} => :tutor,
    {"Officer", "Chair"} => :chair,
    {"Officer", "Communications"} => :communications,
    {"Officer", "Secretary"} => :secretary,
    {"Officer", "Treasurer"} => :treasurer,
    {"Officer", "Vice-Chair"} => :vice_chair
  }

  # Institution roles [Core §A.2.2](https://www.imsglobal.org/spec/lti/v1p3/#lis-vocabulary-for-institution-roles)
  @institution_base "http://purl.imsglobal.org/vocab/lis/v2/institution/person#"
  @institution_roles %{
    "Administrator" => :administrator,
    "Faculty" => :faculty,
    "Guest" => :guest,
    "None" => :none,
    "Other" => :other,
    "Staff" => :staff,
    "Student" => :student,
    "Alumni" => :alumni,
    "Instructor" => :instructor,
    "Learner" => :learner,
    "Member" => :member,
    "Mentor" => :mentor,
    "Observer" => :observer,
    "ProspectiveStudent" => :prospective_student
  }

  # System LIS roles [Core §A.2.1](https://www.imsglobal.org/spec/lti/v1p3/#lis-vocabulary-for-system-roles)
  @system_lis_base "http://purl.imsglobal.org/vocab/lis/v2/system/person#"
  @system_lis_roles %{
    "Administrator" => :administrator,
    "None" => :none,
    "AccountAdmin" => :account_admin,
    "Creator" => :creator,
    "SysAdmin" => :sys_admin,
    "SysSupport" => :sys_support,
    "User" => :user
  }

  # System LTI roles [Core §A.2.4](https://www.imsglobal.org/spec/lti/v1p3/#lti-vocabulary-for-system-roles)
  @system_lti_base "http://purl.imsglobal.org/vocab/lti/system/person#"
  @system_lti_roles %{
    "TestUser" => :test_user
  }

  # Deprecated base URI [Core §A](https://www.imsglobal.org/spec/lti/v1p3/#standardvocabs)
  # Was used for both system and institution roles
  @deprecated_base "http://purl.imsglobal.org/vocab/lis/v2/person#"

  # --- Reverse Maps (for to_uri/1) ---

  @context_roles_inverse Map.new(@context_roles, fn {k, v} -> {v, k} end)
  @institution_roles_inverse Map.new(@institution_roles, fn {k, v} -> {v, k} end)
  @system_lis_roles_inverse Map.new(@system_lis_roles, fn {k, v} -> {v, k} end)
  @system_lti_roles_inverse Map.new(@system_lti_roles, fn {k, v} -> {v, k} end)

  @context_sub_roles_inverse Map.new(@context_sub_roles, fn {{principal, sub}, atom} ->
                               {atom, {principal, sub}}
                             end)

  # --- Public API ---

  @doc """
  Attempt to parse a role URI against the LIS vocabularies.

  Returns `{:ok, %Role{}}` for recognized URIs, `:error` otherwise.
  """
  @spec parse(String.t()) :: {:ok, Role.t()} | :error
  @impl Parser
  def parse(uri) do
    cond do
      String.starts_with?(uri, @context_base) ->
        parse_context_role(uri)

      String.starts_with?(uri, @sub_role_base) ->
        parse_context_sub_role(uri)

      String.starts_with?(uri, @institution_base) ->
        parse_institution_role(uri)

      String.starts_with?(uri, @system_lis_base) ->
        parse_system_lis_role(uri)

      String.starts_with?(uri, @system_lti_base) ->
        parse_system_lti_role(uri)

      String.starts_with?(uri, @deprecated_base) ->
        parse_deprecated_role(uri)

      true ->
        :error
    end
  end

  @doc """
  Convert a `%Role{}` struct to its LIS vocabulary URI.

  ## Examples

      iex> alias Ltix.LaunchClaims.Role
      iex> Ltix.LaunchClaims.Role.LIS.to_uri(%Role{type: :context, name: :instructor})
      {:ok, "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"}

      iex> alias Ltix.LaunchClaims.Role
      iex> Ltix.LaunchClaims.Role.LIS.to_uri(%Role{type: :context, name: :instructor, sub_role: :teaching_assistant})
      {:ok, "http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant"}

      iex> alias Ltix.LaunchClaims.Role
      iex> Ltix.LaunchClaims.Role.LIS.to_uri(%Role{type: :institution, name: :faculty})
      {:ok, "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Faculty"}

      iex> alias Ltix.LaunchClaims.Role
      iex> Ltix.LaunchClaims.Role.LIS.to_uri(%Role{type: :system, name: :sys_admin})
      {:ok, "http://purl.imsglobal.org/vocab/lis/v2/system/person#SysAdmin"}

      iex> alias Ltix.LaunchClaims.Role
      iex> Ltix.LaunchClaims.Role.LIS.to_uri(%Role{type: :system, name: :test_user})
      {:ok, "http://purl.imsglobal.org/vocab/lti/system/person#TestUser"}
  """
  @spec to_uri(Role.t_without_uri()) :: {:ok, String.t()} | :error
  @impl Parser
  def to_uri(%Role{type: :context, sub_role: nil, name: name}) do
    case Map.fetch(@context_roles_inverse, name) do
      {:ok, pascal} -> {:ok, @context_base <> pascal}
      :error -> :error
    end
  end

  def to_uri(%Role{type: :context, name: name, sub_role: sub_role}) do
    with {:ok, {principal, sub_pascal}} <- Map.fetch(@context_sub_roles_inverse, sub_role),
         {:ok, ^principal} <- Map.fetch(@context_roles_inverse, name) do
      {:ok, @sub_role_base <> principal <> "#" <> sub_pascal}
    else
      _ -> :error
    end
  end

  def to_uri(%Role{type: :institution, name: name}) do
    case Map.fetch(@institution_roles_inverse, name) do
      {:ok, pascal} -> {:ok, @institution_base <> pascal}
      :error -> :error
    end
  end

  def to_uri(%Role{type: :system, name: name}) do
    case Map.fetch(@system_lis_roles_inverse, name) do
      {:ok, pascal} ->
        {:ok, @system_lis_base <> pascal}

      :error ->
        case Map.fetch(@system_lti_roles_inverse, name) do
          {:ok, pascal} -> {:ok, @system_lti_base <> pascal}
          :error -> :error
        end
    end
  end

  def to_uri(_), do: :error

  # --- Private Parsers ---

  defp parse_context_role(uri) do
    role_name = String.replace_leading(uri, @context_base, "")

    case Map.fetch(@context_roles, role_name) do
      {:ok, name} -> {:ok, %Role{type: :context, name: name, sub_role: nil, uri: uri}}
      :error -> :error
    end
  end

  defp parse_context_sub_role(uri) do
    suffix = String.replace_leading(uri, @sub_role_base, "")

    case String.split(suffix, "#", parts: 2) do
      [principal, sub] ->
        with {:ok, principal_name} <- Map.fetch(@context_roles, principal),
             {:ok, sub_role} <- Map.fetch(@context_sub_roles, {principal, sub}) do
          {:ok,
           %Role{
             type: :context,
             name: principal_name,
             sub_role: sub_role,
             uri: uri
           }}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_institution_role(uri) do
    role_name = String.replace_leading(uri, @institution_base, "")

    case Map.fetch(@institution_roles, role_name) do
      {:ok, name} -> {:ok, %Role{type: :institution, name: name, sub_role: nil, uri: uri}}
      :error -> :error
    end
  end

  defp parse_system_lis_role(uri) do
    role_name = String.replace_leading(uri, @system_lis_base, "")

    case Map.fetch(@system_lis_roles, role_name) do
      {:ok, name} -> {:ok, %Role{type: :system, name: name, sub_role: nil, uri: uri}}
      :error -> :error
    end
  end

  defp parse_system_lti_role(uri) do
    role_name = String.replace_leading(uri, @system_lti_base, "")

    case Map.fetch(@system_lti_roles, role_name) do
      {:ok, name} -> {:ok, %Role{type: :system, name: name, sub_role: nil, uri: uri}}
      :error -> :error
    end
  end

  # Deprecated URI form [Core §A](https://www.imsglobal.org/spec/lti/v1p3/#standardvocabs):
  # person# without system/ or institution/ prefix.
  # System roles take priority, then institution roles.
  defp parse_deprecated_role(uri) do
    role_name = String.replace_leading(uri, @deprecated_base, "")

    cond do
      Map.has_key?(@system_lis_roles, role_name) ->
        {:ok, %Role{type: :system, name: @system_lis_roles[role_name], sub_role: nil, uri: uri}}

      Map.has_key?(@institution_roles, role_name) ->
        {:ok,
         %Role{type: :institution, name: @institution_roles[role_name], sub_role: nil, uri: uri}}

      true ->
        :error
    end
  end
end
