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
  @sub_role_base "http://purl.imsglobal.org/vocab/lis/v2/membership/"
  @context_sub_roles %{
    "Administrator" =>
      ~w(Administrator Developer ExternalDeveloper ExternalSupport ExternalSystemAdministrator Support SystemAdministrator),
    "ContentDeveloper" => ~w(ContentDeveloper ContentExpert ExternalContentExpert Librarian),
    "Instructor" =>
      ~w(ExternalInstructor Grader GuestInstructor Lecturer PrimaryInstructor SecondaryInstructor TeachingAssistant TeachingAssistantGroup TeachingAssistantOffering TeachingAssistantSection TeachingAssistantSectionAssociation TeachingAssistantTemplate),
    "Learner" => ~w(ExternalLearner GuestLearner Instructor Learner NonCreditLearner),
    "Manager" => ~w(AreaManager CourseCoordinator ExternalObserver Manager Observer),
    "Member" => ~w(Member),
    "Mentor" =>
      ~w(Advisor Auditor ExternalAdvisor ExternalAuditor ExternalLearningFacilitator ExternalMentor ExternalReviewer ExternalTutor LearningFacilitator Mentor Reviewer Tutor),
    "Officer" => ~w(Chair Communications Secretary Treasurer Vice-Chair)
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
             true <- sub in Map.get(@context_sub_roles, principal, []) do
          {:ok,
           %Role{
             type: :context,
             name: principal_name,
             sub_role: to_snake_atom(sub),
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

  defp to_snake_atom(pascal_string) do
    pascal_string
    |> String.replace(~r/([A-Z])/, "_\\1")
    |> String.trim_leading("_")
    |> String.replace("-", "_")
    |> String.downcase()
    |> String.to_existing_atom()
  end
end
