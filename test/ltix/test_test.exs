defmodule Ltix.TestTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.Errors.Invalid.InvalidOption
  alias Ltix.Errors.Security.KidMissing
  alias Ltix.Errors.Security.KidNotFound
  alias Ltix.Errors.Security.SignatureInvalid
  alias Ltix.GradeService
  alias Ltix.GradeService.LineItem
  alias Ltix.GradeService.Result
  alias Ltix.GradeService.Score
  alias Ltix.JWT.Token
  alias Ltix.LaunchClaims.AGSEndpoint
  alias Ltix.LaunchClaims.Context
  alias Ltix.LaunchClaims.MembershipsEndpoint
  alias Ltix.LaunchClaims.Role
  alias Ltix.LaunchContext
  alias Ltix.MembershipsService.Member
  alias Ltix.MembershipsService.MembershipContainer
  alias Ltix.OAuth.Client
  alias Ltix.Test.StorageAdapter

  @launch_url "https://tool.example.com/launch"

  setup do
    platform = Ltix.Test.setup_platform!()

    {:ok, pid} =
      StorageAdapter.start_link(platforms: [platform])

    StorageAdapter.set_pid(pid)

    %{platform: platform}
  end

  describe "options" do
    test "every helper raises on unknown options", %{platform: platform} do
      for call <- [
            fn -> Ltix.Test.setup_platform!(unknown: true) end,
            fn -> Ltix.Test.login_params(platform, unknown: true) end,
            fn -> Ltix.Test.launch_params(platform, nonce: "n", state: "s", unknown: true) end,
            fn -> Ltix.Test.build_launch_context(platform, unknown: true) end,
            fn -> Ltix.Test.stub_token_response(unknown: true) end,
            fn -> Ltix.Test.stub_list_members([], unknown: true) end,
            fn -> Ltix.Test.sign_id_token(%{}, platform.jwk, unknown: true) end,
            fn -> StorageAdapter.start_link(unknown: true) end
          ] do
        assert_raise InvalidOption, "Option :unknown is unknown", call
      end
    end

    test "helpers raise on missing and invalid options", %{platform: platform} do
      assert_raise InvalidOption, "Option :nonce is required", fn ->
        Ltix.Test.launch_params(platform, state: "s")
      end

      assert_raise InvalidOption, ~r/Option :scopes is invalid/, fn ->
        Ltix.Test.stub_token_response(
          scopes: "https://purl.imsglobal.org/spec/lti-ags/scope/score"
        )
      end
    end
  end

  describe "full OIDC flow via test helpers" do
    test "login → callback → LaunchContext with default roles", %{platform: platform} do
      {:ok, login_result} =
        Ltix.handle_login(
          Ltix.Test.login_params(platform),
          @launch_url,
          storage_adapter: StorageAdapter
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

  describe "launch options shared by launch_params/2 and build_launch_context/2" do
    @custom_role "http://example.com/roles#Grader"
    @course_type "http://purl.imsglobal.org/vocab/lis/v2/course#CourseOffering"
    @ags_scope "https://purl.imsglobal.org/spec/lti-ags/scope/score"

    test "both helpers build the same claims", %{platform: platform} do
      for opts <- [
            [roles: [:learner, @custom_role], subject: "student-1"],
            [context: %{id: "course-1", label: "CS101", type: [@course_type]}],
            [context: %Context{id: "course-2", title: "Elixir"}],
            [resource_link: %{id: "quiz-1", title: "Quiz", description: "First quiz"}],
            [message_type: :deep_linking, deep_linking_settings: %{accept_line_item: true}],
            [ags_endpoint: %{line_item: "https://lms.example.com/items/1", scopes: [@ags_scope]}],
            [memberships_endpoint: "https://lms.example.com/memberships"],
            [
              memberships_endpoint: %{
                context_memberships_url: "https://lms.example.com/memberships",
                service_versions: ["2.0"]
              }
            ],
            [claims: %{"https://purl.imsglobal.org/spec/lti/claim/custom" => %{"a" => "b"}}]
          ] do
        assert comparable(launch_context(platform, opts)) ==
                 comparable(Ltix.Test.build_launch_context(platform, opts)),
               "claims differ for #{inspect(opts)}"
      end
    end

    test "default to an instructor with a subject and context", %{platform: platform} do
      for context <- [launch_context(platform, []), Ltix.Test.build_launch_context(platform)] do
        assert Role.instructor?(context.claims.roles)
        assert context.claims.subject == "user-12345"
        assert context.claims.context.id == "context-001"
      end
    end

    test "keep custom role URIs in unrecognized_roles", %{platform: platform} do
      context = Ltix.Test.build_launch_context(platform, roles: [:learner, @custom_role])

      assert Role.learner?(context.claims.roles)
      assert context.claims.unrecognized_roles == [@custom_role]
    end

    test "set the subject", %{platform: platform} do
      context = Ltix.Test.build_launch_context(platform, subject: "student-1")

      assert context.claims.subject == "student-1"
    end

    test "take the context as a struct", %{platform: platform} do
      context =
        Ltix.Test.build_launch_context(platform,
          context: %Context{id: "course-2", title: "Elixir"}
        )

      assert context.claims.context.id == "course-2"
      assert context.claims.context.title == "Elixir"
    end

    test "set the resource link", %{platform: platform} do
      context =
        Ltix.Test.build_launch_context(platform,
          resource_link: %{id: "quiz-1", title: "Quiz", description: "First quiz"}
        )

      assert context.claims.resource_link.id == "quiz-1"
      assert context.claims.resource_link.title == "Quiz"
      assert context.claims.resource_link.description == "First quiz"
    end

    test "set deep linking settings over the defaults", %{platform: platform} do
      context =
        Ltix.Test.build_launch_context(platform,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_line_item: true, accept_multiple: false}
        )

      assert context.claims.deep_linking_settings.accept_line_item == true
      assert context.claims.deep_linking_settings.accept_multiple == false
    end

    test "set the grade service endpoint", %{platform: platform} do
      context =
        Ltix.Test.build_launch_context(platform,
          ags_endpoint: %{line_item: "https://lms.example.com/items/1", scopes: [@ags_scope]}
        )

      assert context.claims.ags_endpoint.line_item == "https://lms.example.com/items/1"
      assert context.claims.ags_endpoint.scopes == [@ags_scope]
    end

    test "take the memberships endpoint as a map", %{platform: platform} do
      context =
        Ltix.Test.build_launch_context(platform,
          memberships_endpoint: %{
            context_memberships_url: "https://lms.example.com/memberships",
            service_versions: ["1.0", "2.0"]
          }
        )

      assert context.claims.memberships_endpoint.context_memberships_url ==
               "https://lms.example.com/memberships"

      assert context.claims.memberships_endpoint.service_versions == ["1.0", "2.0"]
    end

    test "subject: nil makes an anonymous launch", %{platform: platform} do
      context =
        Ltix.Test.build_launch_context(platform, message_type: :deep_linking, subject: nil)

      assert context.claims.subject == nil
    end

    test "claims override the built claims", %{platform: platform} do
      context = Ltix.Test.build_launch_context(platform, claims: %{"sub" => "override"})

      assert context.claims.subject == "override"
    end

    test "a launch with service endpoints authenticates both services", %{platform: platform} do
      Ltix.Test.stub_token_response()

      context =
        launch_context(platform,
          ags_endpoint: %{line_items: "https://lms.example.com/items", scopes: [@ags_scope]},
          memberships_endpoint: "https://lms.example.com/memberships"
        )

      opts = [req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]]

      assert {:ok, grade_client} = Ltix.GradeService.authenticate(context, opts)

      assert grade_client.endpoints[Ltix.GradeService].line_items ==
               "https://lms.example.com/items"

      assert {:ok, memberships_client} = Ltix.MembershipsService.authenticate(context, opts)

      assert memberships_client.endpoints[Ltix.MembershipsService].context_memberships_url ==
               "https://lms.example.com/memberships"
    end

    test "raise for endpoints the services would reject", %{platform: platform} do
      for {opts, message} <- [
            {[ags_endpoint: %{line_item: "https://lms.example.com/items/1"}], ~r"scopes"},
            {[memberships_endpoint: "http://lms.example.com/memberships"], ~r"HTTPS"}
          ] do
        assert_raise InvalidField, message, fn ->
          Ltix.Test.build_launch_context(platform, opts)
        end
      end
    end

    test "raise for unknown keys in nested options and unknown roles", %{platform: platform} do
      for {key, value} <- [
            context: %{id: "c", name: "Course"},
            resource_link: %{id: "r", url: "https://tool.example.com"},
            deep_linking_settings: %{accept_lineitem: true},
            ags_endpoint: %{lineitem: "https://lms.example.com/items/1", scopes: [@ags_scope]},
            memberships_endpoint: %{url: "https://lms.example.com/memberships"}
          ] do
        error =
          assert_raise InvalidOption, fn ->
            Ltix.Test.build_launch_context(platform, [{key, value}])
          end

        assert %{key: ^key, value: ^value} = error
      end

      for {opts, message} <- [
            {[roles: [:not_a_role]], "Option :roles is invalid, it is not a known role"},
            {[roles: [%Role{type: :custom, name: :reviewer}]],
             "Option :roles is invalid, it is not a known role"}
          ] do
        assert_raise InvalidOption, message, fn ->
          Ltix.Test.build_launch_context(platform, opts)
        end
      end
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

    test "launches with each new platform's key when platforms share a key set URL" do
      registration =
        Ltix.Registration.new!(%{
          issuer: "https://platform.example.com",
          client_id: "tool-client-id",
          auth_endpoint: "https://platform.example.com/auth",
          jwks_uri:
            "https://platform.example.com/.well-known/jwks-#{System.unique_integer([:positive])}.json",
          tool_jwk: Ltix.JWK.generate(key_size: 2048)
        })

      for _platform <- 1..2 do
        platform = Ltix.Test.setup_platform!(registration: registration)
        {:ok, pid} = StorageAdapter.start_link(platforms: [platform])
        StorageAdapter.set_pid(pid)

        {:ok, login_result} = do_login(platform)
        nonce = Ltix.Test.extract_nonce(login_result.redirect_uri)

        assert {:ok, %LaunchContext{}} = do_callback(platform, login_result, nonce, [])
      end
    end
  end

  describe "setup_platform!/1 validation" do
    test "raises the validation errors for an invalid issuer or deployment_id" do
      assert_raise Ltix.Errors.Invalid, ~r/issuer/, fn ->
        Ltix.Test.setup_platform!(issuer: "http://insecure.example.com")
      end

      assert_raise InvalidField, ~r/deployment_id/, fn ->
        Ltix.Test.setup_platform!(deployment_id: "")
      end
    end

    test "raises the validation error for an invalid registration struct" do
      registration = %{Ltix.Test.setup_platform!().registration | issuer: "not a url"}

      assert_raise InvalidField, ~r/issuer/, fn ->
        Ltix.Test.setup_platform!(registration: registration)
      end
    end

    test "raises InvalidOption for a registration that doesn't convert" do
      registration = %BareRegistration{registration: Ltix.Test.setup_platform!().registration}

      assert_raise InvalidOption, ~r/Option :registration is invalid/, fn ->
        Ltix.Test.setup_platform!(registration: registration)
      end
    end
  end

  describe "Ltix.Test.StorageAdapter" do
    test "finds deployments only under the registration they belong to" do
      first = Ltix.Test.setup_platform!(client_id: "first-tool", deployment_id: "first-dep")
      second = Ltix.Test.setup_platform!(client_id: "second-tool", deployment_id: "second-dep")
      {:ok, pid} = StorageAdapter.start_link(platforms: [first, second])
      StorageAdapter.set_pid(pid)

      assert {:ok, _deployment} = StorageAdapter.get_deployment(second.registration, "second-dep")

      assert {:error, :not_found} =
               StorageAdapter.get_deployment(second.registration, "first-dep")
    end

    test "launches from each of two platforms set up in one test" do
      first = Ltix.Test.setup_platform!(client_id: "first-tool")
      second = Ltix.Test.setup_platform!(client_id: "second-tool")
      {:ok, pid} = StorageAdapter.start_link(platforms: [first, second])
      StorageAdapter.set_pid(pid)

      for platform <- [first, second] do
        {:ok, login_result} = do_login(platform)
        nonce = Ltix.Test.extract_nonce(login_result.redirect_uri)

        assert {:ok, %LaunchContext{}} = do_callback(platform, login_result, nonce, [])
      end
    end

    test "serves processes the test starts", %{platform: platform} do
      task =
        Task.async(fn ->
          {:ok, login_result} = do_login(platform)
          nonce = Ltix.Test.extract_nonce(login_result.redirect_uri)
          do_callback(platform, login_result, nonce, [])
        end)

      assert {:ok, %LaunchContext{}} = Task.await(task)
    end

    test "resolves registrations given without a deployment" do
      platform = Ltix.Test.setup_platform!(client_id: "new-tool")
      {:ok, pid} = StorageAdapter.start_link(registrations: [platform.registration])
      StorageAdapter.set_pid(pid)

      assert {:ok, registration} =
               StorageAdapter.get_registration(platform.registration.issuer, "new-tool")

      assert {:error, :not_found} =
               StorageAdapter.get_deployment(registration, platform.deployment.deployment_id)
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
      assert_raise InvalidOption,
                   "Option :issuer is invalid, cannot be combined with a :registration struct",
                   fn ->
                     Ltix.Test.setup_platform!(
                       registration: reg,
                       issuer: "https://other.example.com"
                     )
                   end
    end

    test "raises when :registration and :client_id are both set",
         %{custom_registration: reg} do
      assert_raise InvalidOption,
                   "Option :client_id is invalid, cannot be combined with a :registration struct",
                   fn ->
                     Ltix.Test.setup_platform!(registration: reg, client_id: "other-client")
                   end
    end

    test "raises when :deployment and :deployment_id are both set",
         %{custom_deployment: dep} do
      assert_raise InvalidOption,
                   "Option :deployment_id is invalid, cannot be combined with a :deployment struct",
                   fn ->
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
        StorageAdapter.start_link(platforms: [platform])

      StorageAdapter.set_pid(pid)

      {:ok, login_result} = do_login(platform)
      nonce = Ltix.Test.extract_nonce(login_result.redirect_uri)

      {:ok, context} = do_callback(platform, login_result, nonce, [])

      assert %CustomRegistration{id: "reg-uuid-001"} = context.registration
      assert %CustomDeployment{id: "dep-uuid-001"} = context.deployment
    end
  end

  describe "valid_lti_claims/2" do
    test "builds claims that launch against the platform" do
      platform =
        Ltix.Test.setup_platform!(
          issuer: "https://custom.lms.edu",
          client_id: "my-tool",
          deployment_id: "dep-99"
        )

      {:ok, pid} =
        StorageAdapter.start_link(platforms: [platform])

      StorageAdapter.set_pid(pid)
      {:ok, login_result} = do_login(platform)
      nonce = Ltix.Test.extract_nonce(login_result.redirect_uri)

      claims =
        Ltix.Test.valid_lti_claims(platform, %{"nonce" => nonce, "sub" => "student-1"})

      params = %{
        "id_token" => Ltix.Test.sign_id_token(claims, platform.jwk),
        "state" => login_result.state
      }

      assert {:ok, context} =
               Ltix.handle_callback(params, login_result.state,
                 storage_adapter: StorageAdapter,
                 req_options: [plug: {Req.Test, Ltix.JWT.KeySet}]
               )

      assert context.claims.issuer == "https://custom.lms.edu"
      assert context.claims.audience == "my-tool"
      assert context.claims.deployment_id == "dep-99"
      assert context.claims.subject == "student-1"
    end
  end

  describe "verify_deep_linking_response/2" do
    test "returns SignatureInvalid for a response signed with another key",
         %{platform: platform} do
      token = Ltix.Test.sign_id_token(%{"sub" => "user"}, platform.jwk)

      assert {:error, %SignatureInvalid{}} =
               Ltix.Test.verify_deep_linking_response(platform, token)
    end

    test "returns SignatureInvalid for malformed tokens", %{platform: platform} do
      context = Ltix.Test.build_launch_context(platform, message_type: :deep_linking)
      {:ok, response} = Ltix.DeepLinking.build_response(context)

      for token <- [
            response.jwt <> "tampered",
            nil
          ] do
        assert {:error, %SignatureInvalid{}} =
                 Ltix.Test.verify_deep_linking_response(platform, token)
      end
    end
  end

  describe "sign_id_token/3" do
    test "kid: nil leaves the key ID out of the header", %{platform: platform} do
      token =
        Ltix.Test.sign_id_token(Ltix.Test.valid_lti_claims(platform), platform.jwk, kid: nil)

      assert {:error, %KidMissing{}} = verify_token(token, platform)
    end

    test "kid overrides the key ID in the header", %{platform: platform} do
      token =
        Ltix.Test.sign_id_token(Ltix.Test.valid_lti_claims(platform), platform.jwk, kid: "other")

      assert {:error, %KidNotFound{kid: "other"}} = verify_token(token, platform)
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
          ags_endpoint: %AGSEndpoint{
            line_item: "https://platform.example.com/lineitems/1",
            scopes: ["https://purl.imsglobal.org/spec/lti-ags/scope/score"]
          }
        )

      assert {:ok, client} =
               Ltix.GradeService.authenticate(context,
                 req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
               )

      assert client.access_token == "my-token"
    end
  end

  describe "service stub routing" do
    @quiz %LineItem{id: "https://lms.example.com/lineitems/7", label: "Quiz", score_maximum: 10}

    test "stubs for different operations answer together", %{platform: platform} do
      Ltix.Test.stub_create_line_item(@quiz)
      Ltix.Test.stub_list_line_items([@quiz])
      Ltix.Test.stub_post_score()
      client = build_grade_client(platform)

      assert {:ok, item} = GradeService.create_line_item(client, label: "Quiz", score_maximum: 10)
      assert :ok = GradeService.post_score(client, score(), line_item: item)
      assert {:ok, [listed]} = GradeService.list_line_items(client)
      assert :ok = GradeService.post_score(client, score(), line_item: listed)
    end

    test "stubbing an operation again replaces its stub", %{platform: platform} do
      Ltix.Test.stub_get_line_item(@quiz)
      Ltix.Test.stub_get_line_item(%{@quiz | label: "Renamed"})

      assert {:ok, %LineItem{label: "Renamed"}} =
               GradeService.get_line_item(build_grade_client(platform))
    end

    test "a request without a matching stub fails with its method and URL", %{platform: platform} do
      Ltix.Test.stub_post_score()

      assert_raise RuntimeError,
                   ~r"GET https://lms\.example\.com/lineitems/1/results.*stub_list_results",
                   fn -> GradeService.list_results(build_grade_client(platform)) end
    end

    test "line_item limits a stub to one line item", %{platform: platform} do
      other = %LineItem{@quiz | id: "https://lms.example.com/lineitems/8", label: "Other"}
      Ltix.Test.stub_get_line_item(@quiz, line_item: @quiz)
      Ltix.Test.stub_get_line_item(other, line_item: other.id)
      Ltix.Test.stub_post_score(line_item: @quiz)
      client = build_grade_client(platform)

      assert {:ok, %LineItem{label: "Quiz"}} =
               GradeService.get_line_item(client, line_item: @quiz)

      assert {:ok, %LineItem{label: "Other"}} =
               GradeService.get_line_item(client, line_item: other)

      assert :ok = GradeService.post_score(client, score(), line_item: @quiz)

      assert_raise RuntimeError, ~r"POST https://lms\.example\.com/lineitems/8/scores", fn ->
        GradeService.post_score(client, score(), line_item: other)
      end

      Ltix.Test.stub_post_score(line_item: "https://lms.example.com/lineitems/9/")

      assert :ok =
               GradeService.post_score(client, score(),
                 line_item: "https://lms.example.com/lineitems/9/"
               )

      assert_raise InvalidOption,
                   "Option :line_item is invalid, it must be an absolute HTTPS URL",
                   fn ->
                     Ltix.Test.stub_post_score(line_item: "http://lms.example.com/lineitems/9")
                   end
    end

    test "stubs answer processes allowed to use them", %{platform: platform} do
      Ltix.Test.stub_list_line_items([@quiz])
      client = build_grade_client(platform)
      test = self()

      pid =
        spawn(fn ->
          receive do
            :go -> send(test, {:listed, GradeService.list_line_items(client)})
          end
        end)

      Req.Test.allow(GradeService, self(), pid)
      send(pid, :go)

      assert_receive {:listed, {:ok, [%LineItem{label: "Quiz"}]}}
    end

    test "each process keeps its own stubs", %{platform: platform} do
      Ltix.Test.stub_list_line_items([@quiz])
      client = build_grade_client(platform)

      task =
        Task.async(fn ->
          Ltix.Test.stub_list_line_items([%{@quiz | label: "Task"}])
          GradeService.list_line_items(client)
        end)

      assert {:ok, [%LineItem{label: "Task"}]} = Task.await(task)
      assert {:ok, [%LineItem{label: "Quiz"}]} = GradeService.list_line_items(client)
    end

    test "list stubs answer page by page", %{platform: platform} do
      items = for n <- 1..5, do: %LineItem{@quiz | id: "#{@quiz.id}#{n}", label: "Quiz #{n}"}
      results = for n <- 1..3, do: %Result{user_id: "student-#{n}", result_score: n}
      Ltix.Test.stub_list_line_items(items)
      Ltix.Test.stub_list_results(results)
      client = build_grade_client(platform)

      page =
        first_page(
          "https://lms.example.com/lineitems",
          GradeService,
          "application/vnd.ims.lis.v2.lineitemcontainer+json"
        )

      assert length(page.body) == 2
      assert [_next] = Req.Response.get_header(page, "link")

      assert {:ok, ^items} = GradeService.list_line_items(client, per_page: 2)
      assert Enum.to_list(GradeService.stream_line_items!(client, per_page: 2)) == items

      assert Enum.take(GradeService.stream_line_items!(client, per_page: 2), 3) ==
               Enum.take(items, 3)

      assert {:error, %Ltix.Errors.Invalid.CollectionTooLarge{}} =
               GradeService.list_line_items(client, per_page: 2, max_line_items: 4)

      assert {:ok, listed} = GradeService.list_results(client, per_page: 1)
      assert Enum.map(listed, & &1.user_id) == ["student-1", "student-2", "student-3"]

      assert Enum.map(GradeService.stream_results!(client, per_page: 2), & &1.user_id) ==
               ["student-1", "student-2", "student-3"]
    end

    test "memberships stubs answer page by page", %{platform: platform} do
      members =
        for n <- 1..3, do: %Member{user_id: "user-#{n}", roles: [Role.from_atom(:learner)]}

      Ltix.Test.stub_list_members(members)
      client = build_memberships_client(platform)

      assert {:ok, roster} = Ltix.MembershipsService.list_members(client, per_page: 2)
      assert Enum.map(roster.members, & &1.user_id) == ["user-1", "user-2", "user-3"]

      assert Enum.map(Ltix.MembershipsService.stream_members!(client, per_page: 1), & &1.user_id) ==
               ["user-1", "user-2", "user-3"]

      page =
        first_page(
          "https://lms.example.com/memberships",
          Ltix.MembershipsService,
          "application/vnd.ims.lti-nrps.v2.membershipcontainer+json"
        )

      assert length(page.body["members"]) == 2
      assert [_next] = Req.Response.get_header(page, "link")
    end
  end

  describe "stub_list_line_items/1" do
    test "returns serialized line items", %{platform: platform} do
      items = [
        %LineItem{id: "https://lms.example.com/items/1", label: "Quiz 1", score_maximum: 100},
        %LineItem{id: "https://lms.example.com/items/2", label: "Quiz 2", score_maximum: 50}
      ]

      Ltix.Test.stub_list_line_items(items)

      client = build_grade_client(platform)

      assert {:ok, [%LineItem{label: "Quiz 1"}, %LineItem{label: "Quiz 2"}]} =
               Ltix.GradeService.list_line_items(client)
    end
  end

  describe "stub_get_line_item/1" do
    test "returns a single serialized line item", %{platform: platform} do
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

      assert :ok =
               Ltix.GradeService.delete_line_item(client,
                 line_item: "https://lms.example.com/items/99"
               )
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

  describe "stub_list_members/2" do
    test "takes the container context as a struct too", %{platform: platform} do
      Ltix.Test.stub_list_members([], context: %Context{id: "course-7"})

      assert {:ok, %MembershipContainer{context: %{id: "course-7"}}} =
               Ltix.MembershipsService.list_members(build_memberships_client(platform))
    end

    test "raises for unknown context keys" do
      error =
        assert_raise InvalidOption, fn ->
          Ltix.Test.stub_list_members([], context: %{id: "c", name: "Course"})
        end

      assert %{key: :context, value: %{id: "c", name: "Course"}} = error
    end

    test "returns serialized members in a container", %{platform: platform} do
      members = [
        %Member{user_id: "student-1", roles: [Role.from_atom(:learner)], name: "Alice"},
        %Member{user_id: "teacher-1", roles: [Role.from_atom(:instructor)], name: "Bob"}
      ]

      Ltix.Test.stub_list_members(members, context: %{id: "course-42", title: "Elixir 101"})

      client = build_memberships_client(platform)

      assert {:ok, %MembershipContainer{} = roster} =
               Ltix.MembershipsService.list_members(client)

      assert roster.context.id == "course-42"
      assert roster.context.title == "Elixir 101"
      assert length(roster.members) == 2

      alice = Enum.find(roster.members, &(&1.user_id == "student-1"))
      assert alice.name == "Alice"
      assert Role.learner?(alice.roles)
    end

    test "uses default context when none given", %{platform: platform} do
      Ltix.Test.stub_list_members([
        %Member{user_id: "student-1", roles: [Role.from_atom(:learner)]}
      ])

      client = build_memberships_client(platform)

      assert {:ok, %MembershipContainer{} = roster} =
               Ltix.MembershipsService.list_members(client)

      assert roster.context.id == "context-001"
    end
  end

  # -- Helpers --

  # Requests the first page of two items the way a service does.
  defp first_page(url, service, media_type) do
    Req.get!(url,
      params: [limit: 2],
      headers: [accept: media_type],
      plug: {Req.Test, service},
      retry: false
    )
  end

  defp score do
    Score.new!(
      user_id: "student-1",
      score_given: 8,
      score_maximum: 10,
      activity_progress: :completed,
      grading_progress: :fully_graded
    )
  end

  defp build_grade_client(platform, opts \\ []) do
    scopes =
      Keyword.get(opts, :scopes, [
        "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
        "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly",
        "https://purl.imsglobal.org/spec/lti-ags/scope/score"
      ])

    build_client(
      platform,
      GradeService,
      %AGSEndpoint{
        line_items: "https://lms.example.com/lineitems",
        line_item: "https://lms.example.com/lineitems/1",
        scopes: scopes
      },
      scopes
    )
  end

  defp build_memberships_client(platform) do
    build_client(
      platform,
      Ltix.MembershipsService,
      MembershipsEndpoint.new!("https://lms.example.com/memberships"),
      ["https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"]
    )
  end

  defp build_client(platform, service, endpoint, scopes) do
    %Client{
      access_token: "test-token",
      expires_at: DateTime.add(DateTime.utc_now(), 3600),
      scopes: MapSet.new(scopes),
      registration: platform.registration,
      req_options: [plug: {Req.Test, service}, retry: false],
      endpoints: %{service => endpoint}
    }
  end

  defp launch_context(platform, opts) do
    {:ok, login_result} = do_login(platform)
    nonce = Ltix.Test.extract_nonce(login_result.redirect_uri)
    {:ok, context} = do_callback(platform, login_result, nonce, opts)
    context
  end

  # Launch time fields differ between two launches.
  defp comparable(%LaunchContext{claims: claims}) do
    %{claims | nonce: nil, expires_at: nil, issued_at: nil}
  end

  defp verify_token(token, platform) do
    Token.verify(token, platform.registration, req_options: [plug: {Req.Test, Ltix.JWT.KeySet}])
  end

  # -- OIDC Flow Helpers --

  defp do_login(platform) do
    Ltix.handle_login(
      Ltix.Test.login_params(platform),
      @launch_url,
      storage_adapter: StorageAdapter
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
