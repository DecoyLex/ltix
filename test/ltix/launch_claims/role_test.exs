defmodule Ltix.LaunchClaims.RoleTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchClaims.Role

  doctest Ltix.LaunchClaims.Role

  # --- Context Roles [Core §A.2.3] ---

  @context_base "http://purl.imsglobal.org/vocab/lis/v2/membership#"

  describe "parse/1 context roles [Core §A.2.3]" do
    for role_name <-
          ~w(Administrator ContentDeveloper Instructor Learner Mentor Manager Member Officer) do
      test "parses #{role_name}" do
        uri = @context_base <> unquote(role_name)
        assert {:ok, %Role{type: :context, uri: ^uri}} = Role.parse(uri)
      end
    end

    test "parses Instructor with correct name atom" do
      assert {:ok, %Role{name: :instructor, sub_role: nil}} =
               Role.parse(@context_base <> "Instructor")
    end

    test "parses Learner with correct name atom" do
      assert {:ok, %Role{name: :learner, sub_role: nil}} =
               Role.parse(@context_base <> "Learner")
    end

    test "parses ContentDeveloper with correct name atom" do
      assert {:ok, %Role{name: :content_developer, sub_role: nil}} =
               Role.parse(@context_base <> "ContentDeveloper")
    end

    test "parses Administrator with correct name atom" do
      assert {:ok, %Role{name: :administrator, sub_role: nil}} =
               Role.parse(@context_base <> "Administrator")
    end
  end

  # --- Context Sub-Roles [Core §A.2.3.1] ---

  @sub_role_base "http://purl.imsglobal.org/vocab/lis/v2/membership/"

  describe "parse/1 context sub-roles [Core §A.2.3.1]" do
    # Exhaustive test of every sub-role in the vocabulary.
    # Each entry: {PrincipalRole, SubRole, expected_name_atom, expected_sub_role_atom}
    @sub_role_cases [
      # Administrator sub-roles
      {"Administrator", "Administrator", :administrator, :administrator},
      {"Administrator", "Developer", :administrator, :developer},
      {"Administrator", "ExternalDeveloper", :administrator, :external_developer},
      {"Administrator", "ExternalSupport", :administrator, :external_support},
      {"Administrator", "ExternalSystemAdministrator", :administrator,
       :external_system_administrator},
      {"Administrator", "Support", :administrator, :support},
      {"Administrator", "SystemAdministrator", :administrator, :system_administrator},
      # ContentDeveloper sub-roles
      {"ContentDeveloper", "ContentDeveloper", :content_developer, :content_developer},
      {"ContentDeveloper", "ContentExpert", :content_developer, :content_expert},
      {"ContentDeveloper", "ExternalContentExpert", :content_developer, :external_content_expert},
      {"ContentDeveloper", "Librarian", :content_developer, :librarian},
      # Instructor sub-roles
      {"Instructor", "ExternalInstructor", :instructor, :external_instructor},
      {"Instructor", "Grader", :instructor, :grader},
      {"Instructor", "GuestInstructor", :instructor, :guest_instructor},
      {"Instructor", "Lecturer", :instructor, :lecturer},
      {"Instructor", "PrimaryInstructor", :instructor, :primary_instructor},
      {"Instructor", "SecondaryInstructor", :instructor, :secondary_instructor},
      {"Instructor", "TeachingAssistant", :instructor, :teaching_assistant},
      {"Instructor", "TeachingAssistantGroup", :instructor, :teaching_assistant_group},
      {"Instructor", "TeachingAssistantOffering", :instructor, :teaching_assistant_offering},
      {"Instructor", "TeachingAssistantSection", :instructor, :teaching_assistant_section},
      {"Instructor", "TeachingAssistantSectionAssociation", :instructor,
       :teaching_assistant_section_association},
      {"Instructor", "TeachingAssistantTemplate", :instructor, :teaching_assistant_template},
      # Learner sub-roles
      {"Learner", "ExternalLearner", :learner, :external_learner},
      {"Learner", "GuestLearner", :learner, :guest_learner},
      {"Learner", "Instructor", :learner, :instructor},
      {"Learner", "Learner", :learner, :learner},
      {"Learner", "NonCreditLearner", :learner, :non_credit_learner},
      # Manager sub-roles
      {"Manager", "AreaManager", :manager, :area_manager},
      {"Manager", "CourseCoordinator", :manager, :course_coordinator},
      {"Manager", "ExternalObserver", :manager, :external_observer},
      {"Manager", "Manager", :manager, :manager},
      {"Manager", "Observer", :manager, :observer},
      # Member sub-roles
      {"Member", "Member", :member, :member},
      # Mentor sub-roles
      {"Mentor", "Advisor", :mentor, :advisor},
      {"Mentor", "Auditor", :mentor, :auditor},
      {"Mentor", "ExternalAdvisor", :mentor, :external_advisor},
      {"Mentor", "ExternalAuditor", :mentor, :external_auditor},
      {"Mentor", "ExternalLearningFacilitator", :mentor, :external_learning_facilitator},
      {"Mentor", "ExternalMentor", :mentor, :external_mentor},
      {"Mentor", "ExternalReviewer", :mentor, :external_reviewer},
      {"Mentor", "ExternalTutor", :mentor, :external_tutor},
      {"Mentor", "LearningFacilitator", :mentor, :learning_facilitator},
      {"Mentor", "Mentor", :mentor, :mentor},
      {"Mentor", "Reviewer", :mentor, :reviewer},
      {"Mentor", "Tutor", :mentor, :tutor},
      # Officer sub-roles
      {"Officer", "Chair", :officer, :chair},
      {"Officer", "Communications", :officer, :communications},
      {"Officer", "Secretary", :officer, :secretary},
      {"Officer", "Treasurer", :officer, :treasurer},
      {"Officer", "Vice-Chair", :officer, :vice_chair}
    ]

    for {principal, sub, expected_name, expected_sub_role} <- @sub_role_cases do
      test "parses #{principal}##{sub}" do
        uri = @sub_role_base <> unquote(principal) <> "#" <> unquote(sub)

        assert {:ok,
                %Role{
                  type: :context,
                  name: unquote(expected_name),
                  sub_role: unquote(expected_sub_role),
                  uri: ^uri
                }} = Role.parse(uri)
      end
    end
  end

  # --- Institution Roles [Core §A.2.2] ---

  @institution_base "http://purl.imsglobal.org/vocab/lis/v2/institution/person#"

  describe "parse/1 institution roles [Core §A.2.2]" do
    for role_name <-
          ~w(Administrator Faculty Guest None Other Staff Student Alumni Instructor Learner Member Mentor Observer ProspectiveStudent) do
      test "parses #{role_name}" do
        uri = @institution_base <> unquote(role_name)
        assert {:ok, %Role{type: :institution, uri: ^uri}} = Role.parse(uri)
      end
    end

    test "parses Faculty with correct name atom" do
      assert {:ok, %Role{name: :faculty}} = Role.parse(@institution_base <> "Faculty")
    end

    test "parses Student with correct name atom" do
      assert {:ok, %Role{name: :student}} = Role.parse(@institution_base <> "Student")
    end
  end

  # --- System Roles (LIS) [Core §A.2.1] ---

  @system_lis_base "http://purl.imsglobal.org/vocab/lis/v2/system/person#"

  describe "parse/1 system LIS roles [Core §A.2.1]" do
    for role_name <- ~w(Administrator None AccountAdmin Creator SysAdmin SysSupport User) do
      test "parses #{role_name}" do
        uri = @system_lis_base <> unquote(role_name)
        assert {:ok, %Role{type: :system, uri: ^uri}} = Role.parse(uri)
      end
    end

    test "parses SysAdmin with correct name atom" do
      assert {:ok, %Role{name: :sys_admin}} = Role.parse(@system_lis_base <> "SysAdmin")
    end
  end

  # --- System Roles (LTI) [Core §A.2.4] ---

  describe "parse/1 system LTI roles [Core §A.2.4]" do
    test "parses TestUser" do
      uri = "http://purl.imsglobal.org/vocab/lti/system/person#TestUser"

      assert {:ok, %Role{type: :system, name: :test_user, uri: ^uri}} = Role.parse(uri)
    end
  end

  # --- Deprecated URI Forms [Core §A] ---

  describe "parse/1 deprecated URI forms [Core §A]" do
    # Deprecated system roles used person# without system/ prefix
    test "parses deprecated system role URI" do
      uri = "http://purl.imsglobal.org/vocab/lis/v2/person#Administrator"
      assert {:ok, %Role{type: :system, name: :administrator}} = Role.parse(uri)
    end

    # Deprecated institution roles used person# without institution/ prefix
    test "parses deprecated institution role URI (Faculty)" do
      uri = "http://purl.imsglobal.org/vocab/lis/v2/person#Faculty"
      assert {:ok, %Role{type: :institution, name: :faculty}} = Role.parse(uri)
    end
  end

  # --- Short Role Names [Cert §6.1.2] ---

  describe "parse/1 short role names [Cert §6.1.2]" do
    test "parses short Instructor" do
      assert {:ok, %Role{type: :context, name: :instructor}} = Role.parse("Instructor")
    end

    test "parses short Learner" do
      assert {:ok, %Role{type: :context, name: :learner}} = Role.parse("Learner")
    end

    test "parses short Administrator" do
      assert {:ok, %Role{type: :context, name: :administrator}} = Role.parse("Administrator")
    end

    test "parses short ContentDeveloper" do
      assert {:ok, %Role{type: :context, name: :content_developer}} =
               Role.parse("ContentDeveloper")
    end

    test "parses short Mentor" do
      assert {:ok, %Role{type: :context, name: :mentor}} = Role.parse("Mentor")
    end
  end

  # --- Unknown Roles ---

  describe "parse/1 unknown roles" do
    test "returns :error for unrecognized URI" do
      assert :error = Role.parse("http://example.com/custom/role#CustomRole")
    end

    test "returns :error for unrecognized short name" do
      assert :error = Role.parse("CustomUnknownRole")
    end

    test "accepts unrecognized role when custom parser provided" do
      custom_parser = fn
        "http://example.com/custom/role#CustomRole" = uri ->
          {:ok, %Role{type: :custom, name: :custom_role, uri: uri}}

        _ ->
          :error
      end

      assert {:ok, %Role{type: :custom, name: :custom_role}} =
               Role.parse("http://example.com/custom/role#CustomRole",
                 parsers: %{
                   "http://example.com" => custom_parser
                 }
               )
    end

    test "parse_all/2 passes parsers option to parse/2 for each role" do
      custom_parser = fn
        "http://example.com/custom/role#CustomRole" = uri ->
          {:ok, %Role{type: :custom, name: :custom_role, uri: uri}}

        _ ->
          :error
      end

      uris = [
        "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor",
        "http://example.com/custom/role#CustomRole"
      ]

      assert {[
                %Role{type: :context, name: :instructor},
                %Role{type: :custom, name: :custom_role}
              ],
              []} =
               Role.parse_all(uris,
                 parsers: %{
                   "http://example.com" => custom_parser
                 }
               )
    end

    test "parse/2 only calls custom parser when prefix matches" do
      custom_parser = fn uri ->
        flunk("Custom parser should not be called for URI: #{uri}")
      end

      # URI with non-matching prefix should not call custom parser
      assert {:ok, %Role{type: :context, name: :instructor}} =
               Role.parse("http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor",
                 parsers: %{
                   "http://example.com" => custom_parser
                 }
               )
    end
  end

  # --- parse_all/1 ---

  describe "parse_all/1" do
    # [Cert §6.1.2 "Valid Instructor Launch with Roles"]
    test "separates recognized from unrecognized roles" do
      uris = [
        "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor",
        "http://example.com/custom#CustomRole",
        "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"
      ]

      assert {parsed, unrecognized} = Role.parse_all(uris)
      assert length(parsed) == 2
      assert length(unrecognized) == 1
      assert [%Role{name: :instructor}, %Role{name: :learner}] = parsed
      assert ["http://example.com/custom#CustomRole"] = unrecognized
    end

    # [Core §5.3.7.1] Empty list accepted (anonymous launch)
    test "handles empty list" do
      assert {[], []} = Role.parse_all([])
    end

    test "preserves order" do
      uris = [
        "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner",
        "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"
      ]

      assert {[%Role{name: :learner}, %Role{name: :instructor}], []} = Role.parse_all(uris)
    end

    # [Core §A.2.3.1] Sub-role without principal role present
    test "sub-role without principal role present" do
      uris = ["http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant"]

      assert {[%Role{name: :instructor, sub_role: :teaching_assistant}], []} =
               Role.parse_all(uris)
    end
  end

  # --- Predicate Helpers ---

  describe "predicate helpers" do
    setup do
      {roles, []} =
        Role.parse_all([
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor",
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner",
          "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Faculty"
        ])

      %{roles: roles}
    end

    test "instructor?/1", %{roles: roles} do
      assert Role.instructor?(roles)
    end

    test "learner?/1", %{roles: roles} do
      assert Role.learner?(roles)
    end

    test "administrator?/1 returns false when not present", %{roles: roles} do
      refute Role.administrator?(roles)
    end

    test "content_developer?/1 returns false when not present", %{roles: roles} do
      refute Role.content_developer?(roles)
    end

    test "mentor?/1 returns false when not present", %{roles: roles} do
      refute Role.mentor?(roles)
    end

    test "teaching_assistant?/1 with sub-role" do
      {roles, []} =
        Role.parse_all([
          "http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant"
        ])

      assert Role.teaching_assistant?(roles)
    end

    test "has_role?/3 generic predicate", %{roles: roles} do
      assert Role.has_role?(roles, :context, :instructor)
      refute Role.has_role?(roles, :context, :administrator)
    end

    test "has_role?/4 with sub_role" do
      {roles, []} =
        Role.parse_all([
          "http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#Grader"
        ])

      assert Role.has_role?(roles, :context, :instructor, :grader)
      refute Role.has_role?(roles, :context, :instructor, :teaching_assistant)
    end
  end

  # --- Filter Helpers ---

  describe "filter helpers" do
    setup do
      {roles, []} =
        Role.parse_all([
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor",
          "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Faculty",
          "http://purl.imsglobal.org/vocab/lis/v2/system/person#Administrator"
        ])

      %{roles: roles}
    end

    test "context_roles/1", %{roles: roles} do
      assert [%Role{type: :context, name: :instructor}] = Role.context_roles(roles)
    end

    test "institution_roles/1", %{roles: roles} do
      assert [%Role{type: :institution, name: :faculty}] = Role.institution_roles(roles)
    end

    test "system_roles/1", %{roles: roles} do
      assert [%Role{type: :system, name: :administrator}] = Role.system_roles(roles)
    end
  end

  # --- URI Preservation ---

  describe "original URI preserved" do
    test "full URI preserved in struct" do
      uri = "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"
      assert {:ok, %Role{uri: ^uri}} = Role.parse(uri)
    end

    test "short name preserved as URI" do
      assert {:ok, %Role{uri: "Instructor"}} = Role.parse("Instructor")
    end
  end
end
