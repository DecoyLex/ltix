defmodule Ltix.TestTest do
  use ExUnit.Case, async: true

  alias Ltix.GradeService.Score
  alias Ltix.LaunchClaims.MembershipsEndpoint
  alias Ltix.LaunchClaims.Role
  alias Ltix.LaunchContext
  alias Ltix.Test.StorageAdapter

  @launch_url "https://tool.example.com/launch"

  setup do
    platform = Ltix.Test.setup_platform!()

    {:ok, pid} =
      StorageAdapter.start_link(
        registrations: [platform.registration],
        deployments: [platform.deployment]
      )

    StorageAdapter.set_pid(pid)

    %{platform: platform}
  end

  describe "full OIDC flow via test helpers" do
    test "login → callback → LaunchContext with default roles", %{platform: platform} do
      {:ok, login_result} =
        Ltix.handle_login(
          Ltix.Test.login_params(platform),
          @launch_url,
          storage_adapter: Ltix.Test.StorageAdapter
        )

      nonce = Ltix.Test.extract_nonce(login_result.redirect_uri)

      {:ok, context} =
        Ltix.handle_callback(
          Ltix.Test.launch_params(platform, nonce: nonce, state: login_result.state),
          login_result.state,
          storage_adapter: StorageAdapter,
          req_options: [plug: {Req.Test, Ltix.JWT.KeySet}]
        )

      assert %LaunchContext{} = context
      assert context.registration == platform.registration
      assert context.deployment == platform.deployment
      assert Role.instructor?(context.claims.roles)
    end

    test "launch with atom roles", %{platform: platform} do
      {:ok, login_result} = do_login(platform)
      nonce = Ltix.Test.extract_nonce(login_result.redirect_uri)

      {:ok, context} =
        do_callback(platform, login_result, nonce, roles: [:learner])

      assert Role.learner?(context.claims.roles)
      refute Role.instructor?(context.claims.roles)
    end

    test "launch with sub-role struct", %{platform: platform} do
      {:ok, login_result} = do_login(platform)
      nonce = Ltix.Test.extract_nonce(login_result.redirect_uri)

      ta_role = %Role{type: :context, name: :instructor, sub_role: :teaching_assistant}

      {:ok, context} =
        do_callback(platform, login_result, nonce, roles: [ta_role])

      assert Role.teaching_assistant?(context.claims.roles)
    end

    test "launch with URI string roles", %{platform: platform} do
      {:ok, login_result} = do_login(platform)
      nonce = Ltix.Test.extract_nonce(login_result.redirect_uri)

      uri = "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"

      {:ok, context} =
        do_callback(platform, login_result, nonce, roles: [uri])

      assert Role.learner?(context.claims.roles)
    end

    test "launch with PII claims", %{platform: platform} do
      {:ok, login_result} = do_login(platform)
      nonce = Ltix.Test.extract_nonce(login_result.redirect_uri)

      {:ok, context} =
        do_callback(platform, login_result, nonce,
          name: "Jane Doe",
          email: "jane@example.com",
          given_name: "Jane",
          family_name: "Doe"
        )

      assert context.claims.name == "Jane Doe"
      assert context.claims.email == "jane@example.com"
      assert context.claims.given_name == "Jane"
      assert context.claims.family_name == "Doe"
    end

    test "launch with context", %{platform: platform} do
      {:ok, login_result} = do_login(platform)
      nonce = Ltix.Test.extract_nonce(login_result.redirect_uri)

      {:ok, context} =
        do_callback(platform, login_result, nonce,
          context: %{id: "course-1", label: "CS101", title: "Intro to CS"}
        )

      assert context.claims.context.id == "course-1"
      assert context.claims.context.label == "CS101"
      assert context.claims.context.title == "Intro to CS"
    end

    test "launch with custom claims override", %{platform: platform} do
      {:ok, login_result} = do_login(platform)
      nonce = Ltix.Test.extract_nonce(login_result.redirect_uri)

      {:ok, context} =
        do_callback(platform, login_result, nonce,
          claims: %{
            "https://purl.imsglobal.org/spec/lti/claim/custom" => %{
              "canvas_course_id" => "12345"
            }
          }
        )

      assert context.claims.custom == %{"canvas_course_id" => "12345"}
    end

    test "launch with custom subject", %{platform: platform} do
      {:ok, login_result} = do_login(platform)
      nonce = Ltix.Test.extract_nonce(login_result.redirect_uri)

      {:ok, context} =
        do_callback(platform, login_result, nonce, subject: "student-42")

      assert context.claims.subject == "student-42"
    end

    test "includes a default context when none is specified", %{platform: platform} do
      {:ok, login_result} = do_login(platform)
      nonce = Ltix.Test.extract_nonce(login_result.redirect_uri)

      {:ok, context} = do_callback(platform, login_result, nonce, [])

      assert context.claims.context.id == "context-001"
    end
  end

  describe "build_launch_context/2" do
    test "builds a valid context without the OIDC flow", %{platform: platform} do
      context = Ltix.Test.build_launch_context(platform, roles: [:instructor])

      assert %LaunchContext{} = context
      assert context.registration == platform.registration
      assert context.deployment == platform.deployment
      assert Role.instructor?(context.claims.roles)
    end

    test "includes PII and context claims", %{platform: platform} do
      context =
        Ltix.Test.build_launch_context(platform,
          roles: [:learner],
          name: "John Smith",
          email: "john@example.com",
          context: %{id: "course-1", title: "Elixir 101"}
        )

      assert context.claims.name == "John Smith"
      assert context.claims.email == "john@example.com"
      assert Role.learner?(context.claims.roles)
      assert context.claims.context.id == "course-1"
      assert context.claims.context.title == "Elixir 101"
    end

    test "handles sub-role structs", %{platform: platform} do
      ta_role = %Role{type: :context, name: :instructor, sub_role: :teaching_assistant}
      context = Ltix.Test.build_launch_context(platform, roles: [ta_role])

      assert Role.teaching_assistant?(context.claims.roles)
      assert Role.instructor?(context.claims.roles)
    end

    test "includes a default context when none is specified", %{platform: platform} do
      context = Ltix.Test.build_launch_context(platform)

      assert context.claims.context.id == "context-001"
    end

    test "explicit context overrides the default", %{platform: platform} do
      context =
        Ltix.Test.build_launch_context(platform,
          context: %{id: "my-course", label: "CS101", title: "Intro to CS"}
        )

      assert context.claims.context.id == "my-course"
      assert context.claims.context.label == "CS101"
      assert context.claims.context.title == "Intro to CS"
    end
  end

  describe "setup_platform!/1" do
    test "accepts custom issuer, client_id, and deployment_id" do
      platform =
        Ltix.Test.setup_platform!(
          issuer: "https://custom.lms.edu",
          client_id: "my-tool",
          deployment_id: "dep-99"
        )

      assert platform.registration.issuer == "https://custom.lms.edu"
      assert platform.registration.client_id == "my-tool"
      assert platform.deployment.deployment_id == "dep-99"
    end

    test "storage adapter resolves the registration", %{platform: platform} do
      assert {:ok, reg} =
               StorageAdapter.get_registration(
                 platform.registration.issuer,
                 platform.registration.client_id
               )

      assert reg == platform.registration
    end

    test "storage adapter resolves the deployment", %{platform: platform} do
      assert {:ok, dep} =
               StorageAdapter.get_deployment(
                 platform.registration,
                 platform.deployment.deployment_id
               )

      assert dep == platform.deployment
    end
  end

  describe "setup_platform!/1 with custom structs" do
    setup do
      tool_jwk = Ltix.JWK.generate()

      registration = %CustomRegistration{
        id: "reg-uuid-001",
        tenant_id: "tenant-1",
        platform_issuer: "https://custom-lms.example.com",
        oauth_client_id: "custom-tool-client",
        oidc_auth_url: "https://custom-lms.example.com/auth",
        platform_jwks_url: "https://custom-lms.example.com/.well-known/jwks.json",
        platform_token_url: "https://custom-lms.example.com/token",
        signing_key: tool_jwk
      }

      deployment = %CustomDeployment{
        id: "dep-uuid-001",
        registration_id: "reg-uuid-001",
        platform_deployment_id: "custom-dep-001",
        label: "My Course Section"
      }

      %{custom_registration: registration, custom_deployment: deployment}
    end

    test "accepts custom registration and deployment structs",
         %{custom_registration: reg, custom_deployment: dep} do
      platform = Ltix.Test.setup_platform!(registration: reg, deployment: dep)

      assert %CustomRegistration{id: "reg-uuid-001"} = platform.registration
      assert %CustomDeployment{id: "dep-uuid-001"} = platform.deployment
    end

    test "raises when :registration and :issuer are both set",
         %{custom_registration: reg} do
      assert_raise ArgumentError, fn ->
        Ltix.Test.setup_platform!(registration: reg, issuer: "https://other.example.com")
      end
    end

    test "raises when :registration and :client_id are both set",
         %{custom_registration: reg} do
      assert_raise ArgumentError, fn ->
        Ltix.Test.setup_platform!(registration: reg, client_id: "other-client")
      end
    end

    test "raises when :deployment and :deployment_id are both set",
         %{custom_deployment: dep} do
      assert_raise ArgumentError, fn ->
        Ltix.Test.setup_platform!(deployment: dep, deployment_id: "other-dep")
      end
    end

    test "build_launch_context carries custom structs through",
         %{custom_registration: reg, custom_deployment: dep} do
      platform = Ltix.Test.setup_platform!(registration: reg, deployment: dep)
      context = Ltix.Test.build_launch_context(platform, roles: [:instructor])

      assert %CustomRegistration{id: "reg-uuid-001"} = context.registration
      assert %CustomDeployment{id: "dep-uuid-001"} = context.deployment
      assert context.claims.issuer == "https://custom-lms.example.com"
      assert context.claims.audience == "custom-tool-client"
      assert context.claims.deployment_id == "custom-dep-001"
    end

    test "full OIDC flow carries custom structs through",
         %{custom_registration: reg, custom_deployment: dep} do
      platform = Ltix.Test.setup_platform!(registration: reg, deployment: dep)

      {:ok, pid} =
        StorageAdapter.start_link(
          registrations: [platform.registration],
          deployments: [platform.deployment]
        )

      StorageAdapter.set_pid(pid)

      {:ok, login_result} = do_login(platform)
      nonce = Ltix.Test.extract_nonce(login_result.redirect_uri)

      {:ok, context} = do_callback(platform, login_result, nonce, [])

      assert %CustomRegistration{id: "reg-uuid-001"} = context.registration
      assert %CustomDeployment{id: "dep-uuid-001"} = context.deployment
    end
  end

  # --- Service Stub Helpers ---

  describe "stub_token_response/1" do
    test "stubs a successful OAuth token response", %{platform: platform} do
      Ltix.Test.stub_token_response(
        scopes: ["https://purl.imsglobal.org/spec/lti-ags/scope/score"],
        access_token: "my-token"
      )

      context =
        Ltix.Test.build_launch_context(platform,
          ags_endpoint: %Ltix.LaunchClaims.AgsEndpoint{
            lineitem: "https://platform.example.com/lineitems/1",
            scope: ["https://purl.imsglobal.org/spec/lti-ags/scope/score"]
          }
        )

      assert {:ok, client} =
               Ltix.GradeService.authenticate(context,
                 req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
               )

      assert client.access_token == "my-token"
    end
  end

  describe "stub_list_line_items/1" do
    test "returns serialized line items", %{platform: platform} do
      alias Ltix.GradeService.LineItem

      items = [
        %LineItem{id: "https://lms.example.com/items/1", label: "Quiz 1", score_maximum: 100},
        %LineItem{id: "https://lms.example.com/items/2", label: "Quiz 2", score_maximum: 50}
      ]

      Ltix.Test.stub_token_response(
        scopes: [
          "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem"
        ]
      )

      Ltix.Test.stub_list_line_items(items)

      client = build_grade_client(platform)

      assert {:ok, [%LineItem{label: "Quiz 1"}, %LineItem{label: "Quiz 2"}]} =
               Ltix.GradeService.list_line_items(client)
    end
  end

  describe "stub_get_line_item/1" do
    test "returns a single serialized line item", %{platform: platform} do
      alias Ltix.GradeService.LineItem

      item = %LineItem{
        id: "https://lms.example.com/items/1",
        label: "Final Exam",
        score_maximum: 200
      }

      Ltix.Test.stub_get_line_item(item)

      client = build_grade_client(platform)

      assert {:ok, %LineItem{label: "Final Exam", score_maximum: 200}} =
               Ltix.GradeService.get_line_item(client)
    end
  end

  describe "stub_create_line_item/1" do
    test "returns the created line item with 201", %{platform: platform} do
      alias Ltix.GradeService.LineItem

      item = %LineItem{
        id: "https://lms.example.com/items/new",
        label: "New Quiz",
        score_maximum: 100
      }

      Ltix.Test.stub_create_line_item(item)

      client = build_grade_client(platform)

      assert {:ok, %LineItem{id: "https://lms.example.com/items/new", label: "New Quiz"}} =
               Ltix.GradeService.create_line_item(client, label: "New Quiz", score_maximum: 100)
    end
  end

  describe "stub_update_line_item/1" do
    test "returns the updated line item", %{platform: platform} do
      alias Ltix.GradeService.LineItem

      item = %LineItem{
        id: "https://lms.example.com/items/1",
        label: "Updated",
        score_maximum: 100
      }

      Ltix.Test.stub_update_line_item(item)

      client = build_grade_client(platform)

      assert {:ok, %LineItem{label: "Updated"}} =
               Ltix.GradeService.update_line_item(client, item)
    end
  end

  describe "stub_delete_line_item/0" do
    test "succeeds with 204", %{platform: platform} do
      Ltix.Test.stub_delete_line_item()

      client = build_grade_client(platform)
      assert :ok = Ltix.GradeService.delete_line_item(client, "https://lms.example.com/items/99")
    end
  end

  describe "stub_post_score/0" do
    test "succeeds", %{platform: platform} do
      Ltix.Test.stub_post_score()

      client =
        build_grade_client(platform,
          scopes: [
            "https://purl.imsglobal.org/spec/lti-ags/scope/score"
          ]
        )

      {:ok, score} =
        Score.new(
          user_id: "student-1",
          score_given: 85,
          score_maximum: 100,
          activity_progress: :completed,
          grading_progress: :fully_graded
        )

      assert :ok = Ltix.GradeService.post_score(client, score)
    end
  end

  describe "stub_get_results/1" do
    test "returns serialized results", %{platform: platform} do
      alias Ltix.GradeService.Result

      results = [
        %Result{user_id: "student-1", result_score: 0.85, result_maximum: 1},
        %Result{user_id: "student-2", result_score: 0.92, result_maximum: 1}
      ]

      Ltix.Test.stub_get_results(results)

      client =
        build_grade_client(platform,
          scopes: [
            "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly"
          ]
        )

      assert {:ok, [%Result{user_id: "student-1"}, %Result{user_id: "student-2"}]} =
               Ltix.GradeService.get_results(client)
    end
  end

  describe "stub_get_members/1" do
    test "returns serialized members in a container", %{platform: platform} do
      alias Ltix.MembershipsService.Member
      alias Ltix.MembershipsService.MembershipContainer

      members = [
        %Member{user_id: "student-1", roles: [Role.from_atom(:learner)], name: "Alice"},
        %Member{user_id: "teacher-1", roles: [Role.from_atom(:instructor)], name: "Bob"}
      ]

      Ltix.Test.stub_get_members(members,
        context: %Ltix.LaunchClaims.Context{
          id: "course-42",
          title: "Elixir 101"
        }
      )

      client = build_memberships_client(platform)

      assert {:ok, %MembershipContainer{} = roster} =
               Ltix.MembershipsService.get_members(client)

      assert roster.context.id == "course-42"
      assert roster.context.title == "Elixir 101"
      assert length(roster.members) == 2

      alice = Enum.find(roster.members, &(&1.user_id == "student-1"))
      assert alice.name == "Alice"
      assert Role.learner?(alice.roles)
    end

    test "uses default context when none given", %{platform: platform} do
      alias Ltix.MembershipsService.Member
      alias Ltix.MembershipsService.MembershipContainer

      Ltix.Test.stub_get_members([
        %Member{user_id: "student-1", roles: [Role.from_atom(:learner)]}
      ])

      client = build_memberships_client(platform)

      assert {:ok, %MembershipContainer{} = roster} =
               Ltix.MembershipsService.get_members(client)

      assert roster.context.id == "context-001"
    end
  end

  # -- Helpers --

  defp build_grade_client(platform, opts \\ []) do
    scopes =
      Keyword.get(opts, :scopes, [
        "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
        "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly",
        "https://purl.imsglobal.org/spec/lti-ags/scope/score"
      ])

    %Ltix.OAuth.Client{
      access_token: "test-token",
      expires_at: DateTime.add(DateTime.utc_now(), 3600),
      scopes: MapSet.new(scopes),
      registration: platform.registration,
      req_options: [plug: {Req.Test, Ltix.GradeService}, retry: false],
      endpoints: %{
        Ltix.GradeService => %Ltix.LaunchClaims.AgsEndpoint{
          lineitems: "https://lms.example.com/lineitems",
          lineitem: "https://lms.example.com/lineitems/1",
          scope: scopes
        }
      }
    }
  end

  defp build_memberships_client(platform) do
    %Ltix.OAuth.Client{
      access_token: "test-token",
      expires_at: DateTime.add(DateTime.utc_now(), 3600),
      scopes:
        MapSet.new([
          "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"
        ]),
      registration: platform.registration,
      req_options: [plug: {Req.Test, Ltix.MembershipsService}, retry: false],
      endpoints: %{
        Ltix.MembershipsService => MembershipsEndpoint.new("https://lms.example.com/memberships")
      }
    }
  end

  # -- OIDC Flow Helpers --

  defp do_login(platform) do
    Ltix.handle_login(
      Ltix.Test.login_params(platform),
      @launch_url,
      storage_adapter: Ltix.Test.StorageAdapter
    )
  end

  defp do_callback(platform, login_result, nonce, opts) do
    params =
      Ltix.Test.launch_params(
        platform,
        Keyword.merge([nonce: nonce, state: login_result.state], opts)
      )

    Ltix.handle_callback(
      params,
      login_result.state,
      storage_adapter: StorageAdapter,
      req_options: [plug: {Req.Test, Ltix.JWT.KeySet}]
    )
  end
end
