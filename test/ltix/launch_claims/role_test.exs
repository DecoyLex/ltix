defmodule Ltix.LaunchClaims.RoleTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchClaims.Role

  defmodule VendorParser do
    @moduledoc false
    use Ltix.LaunchClaims.Role.Parser

    @base "https://vendor.example.com/roles#"

    @impl Ltix.LaunchClaims.Role.Parser
    def parse(@base <> "Reviewer" = uri),
      do: {:ok, %Role{type: :context, name: :reviewer, uri: uri}}

    def parse(_uri), do: :error

    @impl Ltix.LaunchClaims.Role.Parser
    def to_uri(%Role{type: :context, name: :reviewer, sub_role: nil}),
      do: {:ok, @base <> "Reviewer"}

    def to_uri(%Role{type: :context, name: :instructor, sub_role: nil}),
      do: {:ok, @base <> "Teacher"}

    def to_uri(_role), do: :error
  end

  doctest Ltix.LaunchClaims.Role
  doctest Ltix.LaunchClaims.Role.LIS

  # --- Context Roles [Core §A.2.3] ---

  @context_base "http://purl.imsglobal.org/vocab/lis/v2/membership#"

  describe "parse/2 and parse_all/2 options" do
    test "raise on unknown and invalid options" do
      uri = "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"

      assert_raise Ltix.Errors.Invalid.InvalidOption, "Option :parser is unknown", fn ->
        Role.parse(uri, parser: %{})
      end

      assert_raise Ltix.Errors.Invalid.InvalidOption, ~r/Option :role_parsers is invalid/, fn ->
        Role.parse_all([uri], role_parsers: [Ltix.LaunchClaims.Role.LIS])
      end

      for parser <- ["parser", Enum, fn _uri, _other -> :error end] do
        assert_raise Ltix.Errors.Invalid.InvalidOption,
                     ~r/Option :role_parsers is invalid, parsers must be modules/,
                     fn -> Role.parse(uri, role_parsers: %{"https://example.com/" => parser}) end
      end
    end
  end

  describe "parse/1 context roles [Core §A.2.3]" do
    for {role_name, expected_name} <- [
          {"Administrator", :administrator},
          {"ContentDeveloper", :content_developer},
          {"Instructor", :instructor},
          {"Learner", :learner},
          {"Mentor", :mentor},
          {"Manager", :manager},
          {"Member", :member},
          {"Officer", :officer}
        ] do
      test "parses #{role_name} and converts it back" do
        uri = @context_base <> unquote(role_name)

        assert {:ok,
                %Role{type: :context, name: unquote(expected_name), sub_role: nil, uri: ^uri} =
                  role} = Role.parse(uri)

        assert Role.to_uri(%{role | uri: nil}) == {:ok, uri}
      end
    end
  end

  # --- Context Sub-Roles [Core §A.2.3.1] ---

  @sub_role_base "http://purl.imsglobal.org/vocab/lis/v2/membership/"

  describe "parse/1 context sub-roles [Core §A.2.3.1]" do
    # Exhaustive test of every sub-role in the vocabulary.
    # Each entry is {PrincipalRole, SubRole, expected_name_atom, expected_sub_role_atom}
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
      test "parses #{principal}##{sub} and converts it back" do
        uri = @sub_role_base <> unquote(principal) <> "#" <> unquote(sub)

        assert {:ok,
                %Role{
                  type: :context,
                  name: unquote(expected_name),
                  sub_role: unquote(expected_sub_role),
                  uri: ^uri
                } = role} = Role.parse(uri)

        assert Role.to_uri(%{role | uri: nil}) == {:ok, uri}
      end
    end
  end

  # --- Institution Roles [Core §A.2.2] ---

  @institution_base "http://purl.imsglobal.org/vocab/lis/v2/institution/person#"

  describe "parse/1 institution roles [Core §A.2.2]" do
    for {role_name, expected_name} <- [
          {"Administrator", :administrator},
          {"Faculty", :faculty},
          {"Guest", :guest},
          {"None", :none},
          {"Other", :other},
          {"Staff", :staff},
          {"Student", :student},
          {"Alumni", :alumni},
          {"Instructor", :instructor},
          {"Learner", :learner},
          {"Member", :member},
          {"Mentor", :mentor},
          {"Observer", :observer},
          {"ProspectiveStudent", :prospective_student}
        ] do
      test "parses #{role_name} and converts it back" do
        uri = @institution_base <> unquote(role_name)

        assert {:ok,
                %Role{type: :institution, name: unquote(expected_name), sub_role: nil, uri: ^uri} =
                  role} = Role.parse(uri)

        assert Role.to_uri(%{role | uri: nil}) == {:ok, uri}
      end
    end
  end

  # --- System Roles (LIS) [Core §A.2.1] ---

  @system_lis_base "http://purl.imsglobal.org/vocab/lis/v2/system/person#"

  describe "parse/1 system LIS roles [Core §A.2.1]" do
    for {role_name, expected_name} <- [
          {"Administrator", :administrator},
          {"None", :none},
          {"AccountAdmin", :account_admin},
          {"Creator", :creator},
          {"SysAdmin", :sys_admin},
          {"SysSupport", :sys_support},
          {"User", :user}
        ] do
      test "parses #{role_name} and converts it back" do
        uri = @system_lis_base <> unquote(role_name)

        assert {:ok,
                %Role{type: :system, name: unquote(expected_name), sub_role: nil, uri: ^uri} =
                  role} = Role.parse(uri)

        assert Role.to_uri(%{role | uri: nil}) == {:ok, uri}
      end
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

  # --- LIS Edge Cases ---

  describe "parse/1 LIS edge cases" do
    test "returns :error for unrecognized context role name" do
      uri = @context_base <> "Janitor"
      assert :error = Role.parse(uri)
    end

    test "returns :error for sub-role URI without # separator" do
      uri = @sub_role_base <> "InstructorTeachingAssistant"
      assert :error = Role.parse(uri)
    end

    test "returns :error for unrecognized sub-role principal/sub combo" do
      uri = @sub_role_base <> "Instructor#BogusRole"
      assert :error = Role.parse(uri)
    end

    test "returns :error for unrecognized institution role name" do
      uri = @institution_base <> "Janitor"
      assert :error = Role.parse(uri)
    end

    test "returns :error for unrecognized system LIS role name" do
      uri = "http://purl.imsglobal.org/vocab/lis/v2/system/person#Janitor"
      assert :error = Role.parse(uri)
    end

    test "returns :error for unrecognized system LTI role name" do
      uri = "http://purl.imsglobal.org/vocab/lti/system/person#Janitor"
      assert :error = Role.parse(uri)
    end

    test "returns :error for deprecated URI with unrecognized role name" do
      uri = "http://purl.imsglobal.org/vocab/lis/v2/person#Janitor"
      assert :error = Role.parse(uri)
    end

    test "to_uri returns :error for unrecognized context role name" do
      assert :error = Role.to_uri(%Role{type: :context, name: :janitor, sub_role: nil})
    end

    test "to_uri returns :error for unrecognized sub-role" do
      assert :error = Role.to_uri(%Role{type: :context, name: :instructor, sub_role: :janitor})
    end

    test "to_uri returns :error for unrecognized institution role name" do
      assert :error = Role.to_uri(%Role{type: :institution, name: :janitor})
    end

    test "to_uri returns :error for unrecognized system role name" do
      assert :error = Role.to_uri(%Role{type: :system, name: :janitor})
    end

    test "to_uri returns :error for unknown role type" do
      assert :error = Role.to_uri(%Role{type: :custom, name: :something})
    end

    test "to_uri returns the URI a role has" do
      role = %Role{
        type: :custom,
        name: :reviewer,
        uri: "https://vendor.example.com/roles#Reviewer"
      }

      assert Role.to_uri(role) == {:ok, "https://vendor.example.com/roles#Reviewer"}
    end

    test "to_uri! raises for a role no parser can convert" do
      assert_raise ArgumentError, ~r/no role parser can convert/, fn ->
        Role.to_uri!(%Role{type: :custom, name: :something})
      end
    end

    test "to_uri converts a role back with the role parsers parse uses" do
      parsers = %{"https://vendor.example.com/roles#" => VendorParser}
      uri = "https://vendor.example.com/roles#Reviewer"

      assert {:ok, role} = Role.parse(uri, role_parsers: parsers)
      assert Role.to_uri(%{role | uri: nil}, role_parsers: parsers) == {:ok, uri}
      assert Role.to_uri!(%{role | uri: nil}, role_parsers: parsers) == uri
      assert Role.to_uri(%{role | uri: nil}) == :error
    end

    test "to_uri tries custom role parsers before the built-in LIS parser" do
      instructor = %Role{type: :context, name: :instructor, sub_role: nil}
      parsers = %{"https://vendor.example.com/roles#" => VendorParser}

      assert Role.to_uri(instructor, role_parsers: parsers) ==
               {:ok, "https://vendor.example.com/roles#Teacher"}
    end

    test "to_uri raises on invalid role parsers" do
      assert_raise Ltix.Errors.Invalid.InvalidOption, ~r/Option :role_parsers is invalid/, fn ->
        Role.to_uri(%Role{type: :context, name: :reviewer}, role_parsers: [VendorParser])
      end
    end
  end

  # --- Short Role Names [Cert §6.1.2] ---

  describe "parse/1 short role names [Cert §6.1.2]" do
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

    test "returns :error for a URI in an unrecognized LIS vocabulary" do
      assert :error = Role.parse("http://purl.imsglobal.org/vocab/lis/v2/course#CourseOffering")
    end

    test "tries overlapping parser prefixes longest first" do
      uri = "https://example.com/roles/Reviewer"
      general = fn uri -> {:ok, %Role{type: :context, name: :general, uri: uri}} end
      specific = fn uri -> {:ok, %Role{type: :context, name: :specific, uri: uri}} end

      for parsers <- [
            %{"https://example.com/" => general, "https://example.com/roles/" => specific},
            %{"https://example.com/roles/" => specific, "https://example.com/" => general}
          ] do
        assert {:ok, %Role{name: :specific}} = Role.parse(uri, role_parsers: parsers)
      end
    end

    test "parse/2 only calls custom parser when prefix matches" do
      custom_parser = fn uri ->
        flunk("Custom parser should not be called for URI: #{uri}")
      end

      # URI with non-matching prefix should not call custom parser
      assert {:ok, %Role{type: :context, name: :instructor}} =
               Role.parse("http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor",
                 role_parsers: %{
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

    test "administrator?/1 means the institution administrator" do
      refute Role.administrator?([Role.from_atom(:context_administrator)])
      assert Role.administrator?([Role.from_atom(:administrator)])
    end

    test "context_administrator?/1 means the context administrator" do
      refute Role.context_administrator?([Role.from_atom(:administrator)])
      assert Role.context_administrator?([Role.from_atom(:context_administrator)])

      {roles, []} = Role.parse_all([@context_base <> "Administrator", "Administrator"])
      assert Role.context_administrator?(roles)
      refute Role.administrator?(roles)
    end

    test "content_developer?/1", %{roles: roles} do
      refute Role.content_developer?(roles)
      assert Role.content_developer?([Role.from_atom(:content_developer) | roles])
    end

    test "mentor?/1", %{roles: roles} do
      refute Role.mentor?(roles)
      assert Role.mentor?([Role.from_atom(:mentor) | roles])
    end

    test "teaching_assistant?/1 with sub-role" do
      {roles, []} =
        Role.parse_all([
          "http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant"
        ])

      assert Role.teaching_assistant?(roles)
    end

    # [Core §A.2.3.1](https://www.imsglobal.org/spec/lti/v1p3/#context-sub-roles)
    # "Whenever a platform specifies a sub-role, by best practice it should
    # also include the associated principal role." The tool MUST NOT assume
    # the principal role is always present alongside the sub-role.
    test "instructor?/1 matches when only sub-role is present", %{} do
      {roles, []} =
        Role.parse_all([
          "http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant"
        ])

      assert Role.instructor?(roles)
    end

    # [Core §A.2.3.1](https://www.imsglobal.org/spec/lti/v1p3/#context-sub-roles)
    test "learner?/1 matches when only sub-role is present" do
      {roles, []} =
        Role.parse_all([
          "http://purl.imsglobal.org/vocab/lis/v2/membership/Learner#GuestLearner"
        ])

      assert Role.learner?(roles)
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

  # --- from_atom/1 ---

  describe "from_atom/1" do
    test "context principal content_developer" do
      assert %Role{
               type: :context,
               name: :content_developer,
               sub_role: nil,
               uri: @context_base <> "ContentDeveloper"
             } =
               Role.from_atom(:content_developer)
    end

    test "context principal mentor" do
      assert %Role{type: :context, name: :mentor, sub_role: nil, uri: @context_base <> "Mentor"} =
               Role.from_atom(:mentor)
    end

    test "institution student" do
      assert %Role{
               type: :institution,
               name: :student,
               sub_role: nil,
               uri: @institution_base <> "Student"
             } =
               Role.from_atom(:student)
    end

    test "institution staff" do
      assert %Role{
               type: :institution,
               name: :staff,
               sub_role: nil,
               uri: @institution_base <> "Staff"
             } =
               Role.from_atom(:staff)
    end

    test "raises on unknown atom" do
      assert_raise ArgumentError, ~r/unknown role atom/, fn ->
        Role.from_atom(:not_a_role)
      end
    end
  end
end
