defmodule Ltix.RoleTest do
  use ExUnit.Case, async: true

  alias Ltix.Role
  alias Ltix.Test.StorageAdapter

  doctest Ltix.Role

  @vendor_role "https://vendor.example.com/roles#Grader"

  # The checks only build launches, so they share one platform.
  setup_all do
    %{platform: Ltix.Test.setup_platform!()}
  end

  # [Core §5.3.7](https://www.imsglobal.org/spec/lti/v1p3/#roles-claim)
  test "a launch's roles are the URIs the platform sent" do
    # Stubs the platform's key set for this test's process.
    platform = Ltix.Test.setup_platform!()
    StorageAdapter.set_pid(start_supervised!({StorageAdapter, platforms: [platform]}))
    sent = [Role.context_instructor(), @vendor_role, "Learner"]

    assert {:ok, launch} = LaunchFlow.launch(platform, roles: sent)
    assert launch.claims.roles == sent
  end

  # [Core §A.2](https://www.imsglobal.org/spec/lti/v1p3/#role-vocabularies)
  describe "predicates" do
    for {predicate, [matching, other]} <- [
          instructor?: [
            [Role.context_instructor(), Role.instructor_teaching_assistant(), "Instructor"],
            [Role.context_learner(), Role.institution_instructor(), Role.learner_instructor()]
          ],
          learner?: [
            [Role.context_learner(), Role.learner_guest_learner(), "Learner"],
            [Role.institution_learner(), Role.person_learner(), Role.context_instructor()]
          ],
          mentor?: [
            [Role.context_mentor(), Role.mentor_advisor(), "Mentor"],
            [Role.institution_mentor(), Role.person_mentor(), Role.context_learner()]
          ],
          content_developer?: [
            [
              Role.context_content_developer(),
              Role.content_developer_librarian(),
              "ContentDeveloper"
            ],
            [Role.context_instructor(), @vendor_role]
          ],
          context_administrator?: [
            [Role.context_administrator(), Role.administrator_support(), "Administrator"],
            [Role.institution_administrator(), Role.system_administrator()]
          ],
          administrator?: [
            [Role.institution_administrator(), Role.person_administrator()],
            [Role.context_administrator(), "Administrator", Role.system_administrator()]
          ],
          teaching_assistant?: [
            [Role.instructor_teaching_assistant()],
            [Role.context_instructor(), "Instructor", Role.instructor_grader()]
          ]
        ] do
      test "#{predicate} is true for its roles in every form", %{platform: platform} do
        for role <- unquote(matching) do
          roles = launch_roles(platform, [@vendor_role, role])
          assert apply(Role, unquote(predicate), [roles]), "expected #{role} to match"
        end
      end

      test "#{predicate} is false for other roles", %{platform: platform} do
        for role <- unquote(other) do
          roles = launch_roles(platform, [role])
          refute apply(Role, unquote(predicate), [roles]), "expected #{role} not to match"
        end
      end
    end
  end

  describe "has?/2" do
    test "finds a role given its constant", %{platform: platform} do
      roles = launch_roles(platform, [Role.context_learner(), Role.system_test_user()])

      assert Role.has?(roles, Role.system_test_user())
      refute Role.has?(roles, Role.context_instructor())
    end

    test "finds a role sent in its deprecated form", %{platform: platform} do
      assert Role.has?(launch_roles(platform, ["Instructor"]), Role.context_instructor())

      roles = launch_roles(platform, [Role.person_administrator()])
      assert Role.has?(roles, Role.institution_administrator())
      assert Role.has?(roles, Role.system_administrator())
    end

    test "finds only the role given", %{platform: platform} do
      roles = launch_roles(platform, [Role.instructor_teaching_assistant()])

      refute Role.has?(roles, Role.context_instructor())

      refute Role.has?(
               launch_roles(platform, [Role.institution_administrator()]),
               Role.system_administrator()
             )
    end
  end

  # [Core §A.2](https://www.imsglobal.org/spec/lti/v1p3/#role-vocabularies)
  describe "filters by kind" do
    @context_forms [
      "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor",
      "http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant",
      "Learner",
      "http://purl.imsglobal.org/vocab/lis/v2/membership/Officer#Vice-Chair"
    ]
    @institution_forms [
      "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Faculty",
      "http://purl.imsglobal.org/vocab/lis/v2/person#Student"
    ]
    @system_forms [
      "http://purl.imsglobal.org/vocab/lis/v2/system/person#SysAdmin",
      "http://purl.imsglobal.org/vocab/lti/system/person#TestUser",
      "http://purl.imsglobal.org/vocab/lis/v2/person#AccountAdmin"
    ]
    # [Core §A.2.1](https://www.imsglobal.org/spec/lti/v1p3/#lis-vocabulary-for-system-roles)
    # [Core §A.2.2](https://www.imsglobal.org/spec/lti/v1p3/#lis-vocabulary-for-institution-roles)
    @both_forms [
      "http://purl.imsglobal.org/vocab/lis/v2/person#Administrator",
      "http://purl.imsglobal.org/vocab/lis/v2/person#None"
    ]
    @no_kind [@vendor_role, "Faculty"]
    @sent @no_kind ++ @context_forms ++ @institution_forms ++ @system_forms

    test "each filter keeps the roles of its kind in every form, and only those",
         %{platform: platform} do
      roles = launch_roles(platform, @sent)

      assert by_kind(roles) == {@context_forms, @institution_forms, @system_forms}
    end

    test "a deprecated person# role in both the institution and system vocabularies is both kinds",
         %{platform: platform} do
      roles = launch_roles(platform, @both_forms)

      assert by_kind(roles) == {[], @both_forms, @both_forms}
    end

    test "a role the specification doesn't list has the kind of its vocabulary",
         %{platform: platform} do
      context = [
        "http://purl.imsglobal.org/vocab/lis/v2/membership#Guest",
        "http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#Assistant"
      ]

      institution = ["http://purl.imsglobal.org/vocab/lis/v2/institution/person#Dean"]

      system = [
        "http://purl.imsglobal.org/vocab/lis/v2/system/person#Auditor",
        "http://purl.imsglobal.org/vocab/lti/system/person#Proctor"
      ]

      # A `person#` URI has a kind only for a name the institution or system vocabulary lists.
      no_kind = [
        "http://purl.imsglobal.org/vocab/lis/v2/person#Dean",
        "http://purl.imsglobal.org/vocab/lis/v2/person#TestUser"
      ]

      roles = launch_roles(platform, no_kind ++ context ++ institution ++ system)

      assert by_kind(roles) == {context, institution, system}
    end
  end

  defp launch_roles(platform, roles) do
    Ltix.Test.build_launch_context(platform, roles: roles).claims.roles
  end

  defp by_kind(roles) do
    {Role.context_roles(roles), Role.institution_roles(roles), Role.system_roles(roles)}
  end
end
