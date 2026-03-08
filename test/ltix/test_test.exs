defmodule Ltix.TestTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchContext
  alias Ltix.LaunchClaims.Role
  alias Ltix.Test.StorageAdapter

  @launch_url "https://tool.example.com/launch"

  setup do
    platform = Ltix.Test.setup_platform!()

    on_exit(fn ->
      Application.delete_env(:ltix, :storage_adapter)
    end)

    %{platform: platform}
  end

  describe "full OIDC flow via test helpers" do
    test "login → callback → LaunchContext with default roles", %{platform: platform} do
      {:ok, login_result} =
        Ltix.handle_login(
          Ltix.Test.login_params(platform),
          @launch_url
        )

      nonce = Ltix.Test.extract_nonce(login_result.redirect_uri)

      {:ok, context} =
        Ltix.handle_callback(
          Ltix.Test.launch_params(platform, nonce: nonce, state: login_result.state),
          login_result.state,
          Ltix.Test.callback_opts(platform)
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

  # -- Helpers --

  defp do_login(platform) do
    Ltix.handle_login(
      Ltix.Test.login_params(platform),
      @launch_url
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
      Ltix.Test.callback_opts(platform)
    )
  end
end
