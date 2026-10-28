defmodule Ltix.Plugins.ClaimsTest do
  use ExUnit.Case, async: true

  import LaunchFlow

  alias Ltix.Claims.Check
  alias Ltix.Claims.LaunchPresentation
  alias Ltix.Claims.Override
  alias Ltix.Errors.Invalid
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.Errors.Unknown.InvalidPluginSet
  alias Ltix.PluginSet.Conflict
  alias Ltix.Role
  alias Ltix.Test.StorageAdapter
  alias TestPlugins.Modules

  @lti "https://purl.imsglobal.org/spec/lti/claim/"
  @role_scope_mentor @lti <> "role_scope_mentor"
  @context @lti <> "context"
  @version @lti <> "version"
  @launch_presentation @lti <> "launch_presentation"
  @session "https://vendor.example.com/session"
  @untitled %{"id" => "course-1"}

  setup do
    platform = Ltix.Test.setup_platform!()
    StorageAdapter.set_pid(start_supervised!({StorageAdapter, platforms: [platform]}))
    %{platform: platform}
  end

  doctest Ltix.Claims
  doctest Ltix.Claims.Check
  doctest Ltix.Claims.Override

  describe "a vendor's claim" do
    test "is parsed when a plugin declares it", %{platform: platform} do
      session = %{"id" => "s-1", "started_at" => 1_700_000_000, "room" => "A"}

      assert {:ok, launch} =
               launch(platform, [claims: %{@session => session}],
                 plugins: [{Modules, add: [TestPlugins.Session]}]
               )

      assert %TestPlugins.Session{
               id: "s-1",
               started_at: 1_700_000_000,
               unrecognized: %{"room" => "A"}
             } = launch.claims.session

      assert {:error, %MissingClaim{claim: "session.id"}} =
               launch(platform, [claims: %{@session => %{}}],
                 plugins: [{Modules, add: [TestPlugins.Session]}]
               )
    end

    test "has the properties other modules declare on it, with the plugin that declares it only extending it",
         %{platform: platform} do
      assert {:ok, launch} =
               launch(platform, [claims: %{@session => %{"id" => "s-1", "room" => "A"}}],
                 plugins: [{Modules, add: [TestPlugins.Session, TestPlugins.SessionRoom]}]
               )

      assert launch.claims.session.extensions == %{room: "A"}
      assert launch.claims.session.unrecognized == %{}
    end

    test "that is a scalar claim is parsed when a plugin adds it", %{platform: platform} do
      assert {:ok, launch} =
               launch(platform, [claims: %{"https://tool.example.com/claim/traced" => "t"}],
                 plugins: [
                   {Modules, add: [TestPlugins.Traced]}
                 ]
               )

      assert launch.claims.traced == "t"
    end
  end

  describe "launch steps" do
    test "before ClaimsReceived write claims, and steps after ClaimsParsed read the parsed claims",
         %{
           platform: platform
         } do
      plugins = [
        {Modules, add: [TestPlugins.Session, TestPlugins.ReadClaims, TestPlugins.WriteClaims]}
      ]

      assert {:ok, launch} = launch(platform, [], plugins: plugins)

      assert_received {:claims, %{tenant: "acme", session: %TestPlugins.Session{id: "from-step"}}}
      assert launch.claims.tenant == "acme"
      assert launch.claims.session.id == "from-step"
    end
  end

  describe "added checks" do
    test "scoped to a message type run only in it", %{platform: platform} do
      plugins = [{Modules, add: [TestPlugins.TitledContext]}]

      assert {:error,
              %InvalidClaim{
                claim: "context",
                message: "must have a title"
              }} =
               launch(platform, [message_type: :deep_linking, claims: %{@context => @untitled}],
                 plugins: plugins
               )

      assert {:ok, launch} =
               launch(platform, [claims: %{@context => @untitled}], plugins: plugins)

      assert launch.claims.context.id == "course-1"
    end

    test "without message types run in every message type", %{platform: platform} do
      plugins = [{Modules, add: [TestPlugins.LabeledContext]}]

      for message_type <- [:resource_link, :deep_linking] do
        assert {:error,
                %InvalidClaim{
                  claim: "context",
                  message: "must have a label"
                }} =
                 launch(platform, [message_type: message_type, claims: %{@context => @untitled}],
                   plugins: plugins
                 )
      end
    end

    test "a plugin adds with Ltix.Claims.Check.add/2 run their function", %{platform: platform} do
      build =
        &Check.add(&1,
          claim: @context,
          message_types: ["LtiDeepLinkingRequest"],
          check: fn context, _claims ->
            if context.title, do: :ok, else: {:error, "must have a title"}
          end
        )

      plugins = [{Modules, build: build}]

      assert {:error, %InvalidClaim{claim: "context", message: "must have a title"}} =
               launch(platform, [message_type: :deep_linking, claims: %{@context => @untitled}],
                 plugins: plugins
               )

      assert {:ok, _launch} =
               launch(platform, [claims: %{@context => @untitled}], plugins: plugins)
    end

    test "Ltix.Claims.Check.add/2 raises for missing or invalid options" do
      assert_raise ArgumentError, ~r/:check/, fn ->
        Check.add(Ltix.Plugin.new(), claim: @context)
      end

      assert_raise ArgumentError, ~r/:check/, fn ->
        Check.add(Ltix.Plugin.new(), claim: @context, check: fn _value -> :ok end)
      end
    end

    test "must all pass, and run only for claims the launch has", %{platform: platform} do
      plugins = [{Modules, add: [TestPlugins.TitledContext, TestPlugins.LabeledContext]}]

      assert {:error, %Invalid{errors: errors}} =
               launch(platform, [message_type: :deep_linking, claims: %{@context => @untitled}],
                 plugins: plugins
               )

      assert Enum.sort(Enum.map(errors, & &1.message)) ==
               ["must have a label", "must have a title"]

      assert {:ok, launch} =
               launch(platform, [message_type: :deep_linking, claims: %{@context => nil}],
                 plugins: plugins
               )

      assert launch.claims.context == nil
    end
  end

  describe "overrides" do
    test "replace a check in the message types they name", %{platform: platform} do
      plugins = [
        {Modules, add: [TestPlugins.TestRequest, TestPlugins.MentorWithoutRole]}
      ]

      mentor = %{@role_scope_mentor => ["user-2"]}

      assert {:ok, launch} =
               launch(platform, [message_type: "LtiTestRequest", claims: mentor],
                 plugins: plugins
               )

      assert launch.claims.role_scope_mentor == ["user-2"]

      assert {:error, %InvalidClaim{claim: "role_scope_mentor"}} =
               launch(platform, [claims: mentor], plugins: plugins)
    end

    test "replace the version check, and their errors are reported", %{platform: platform} do
      plugins = [
        {Modules, add: [TestPlugins.TestRequest, TestPlugins.NextVersion]}
      ]

      assert {:ok, launch} =
               launch(
                 platform,
                 [message_type: "LtiTestRequest", claims: %{@version => "1.4.0"}],
                 plugins: plugins
               )

      assert launch.claims.version == "1.4.0"

      assert {:error, %InvalidClaim{claim: "version", message: "must be 1.4.0"}} =
               launch(platform, [message_type: "LtiTestRequest"], plugins: plugins)

      assert {:error, %InvalidClaim{claim: "version", message: "unrecognized LTI version"}} =
               launch(platform, [claims: %{@version => "1.4.0"}], plugins: plugins)
    end

    test "a plugin adds with Ltix.Claims.Override.add/2 replace a check with their function",
         %{platform: platform} do
      build =
        &Override.add(&1,
          check: Ltix.Claims.RoleScopeMentor,
          message_types: ["LtiTestRequest"],
          with: fn _subjects, _claims -> :ok end
        )

      plugins = [{Modules, add: [TestPlugins.TestRequest], build: build}]
      mentor = %{@role_scope_mentor => ["user-2"]}

      assert {:ok, launch} =
               launch(platform, [message_type: "LtiTestRequest", claims: mentor],
                 plugins: plugins
               )

      assert launch.claims.role_scope_mentor == ["user-2"]

      assert {:error, %InvalidClaim{claim: "role_scope_mentor"}} =
               launch(platform, [claims: mentor], plugins: plugins)
    end
  end

  describe "properties on claims" do
    test "are parsed into the claim's extensions", %{platform: platform} do
      presentation = %{"document_target" => "iframe", "placement" => ["ContentArea"]}

      assert {:ok, launch} =
               launch(platform, [claims: %{@launch_presentation => presentation}],
                 plugins: [{Modules, add: [TestPlugins.Placement]}]
               )

      assert %LaunchPresentation{
               document_target: "iframe",
               extensions: %{placement: ["ContentArea"]},
               unrecognized: %{}
             } = launch.claims.launch_presentation
    end

    test "a plugin adds with add_property/2 are parsed with their schema", %{platform: platform} do
      build =
        &LaunchPresentation.add_property(&1,
          property: "placement",
          name: :placement,
          schema: Zoi.list(Zoi.string())
        )

      presentation = %{"document_target" => "iframe", "placement" => ["ContentArea"]}

      assert {:ok, launch} =
               launch(platform, [claims: %{@launch_presentation => presentation}],
                 plugins: [{Modules, build: build}]
               )

      assert launch.claims.launch_presentation.extensions == %{placement: ["ContentArea"]}
    end

    test "no plugin declares are unrecognized", %{platform: platform} do
      presentation = %{"document_target" => "iframe", "placement" => ["ContentArea"]}

      assert {:ok, launch} = launch(platform, claims: %{@launch_presentation => presentation})

      assert %LaunchPresentation{extensions: %{}, unrecognized: %{"placement" => ["ContentArea"]}} =
               launch.claims.launch_presentation
    end

    test "that are malformed fail the launch, or make a claim declared with strict: false nil",
         %{platform: platform} do
      plugins = [{Modules, add: [TestPlugins.Placement, TestPlugins.LinkColor]}]

      assert {:error,
              %InvalidClaim{claim: "resource_link.color", value: 1, message: "must be a string"}} =
               launch(
                 platform,
                 [claims: %{(@lti <> "resource_link") => %{"id" => "link-1", "color" => 1}}],
                 plugins: plugins
               )

      assert {:ok, launch} =
               launch(platform, [claims: %{@launch_presentation => %{"placement" => "top"}}],
                 plugins: plugins
               )

      assert launch.claims.launch_presentation == nil
    end
  end

  describe "claims conflict" do
    for {parties, reason} <- [
          {[TestPlugins.MentorWithoutRole, TestPlugins.OtherMentorWithoutRole],
           "both override the check of Ltix.Claims.RoleScopeMentor in LtiTestRequest"},
          {[TestPlugins.Placement, TestPlugins.OtherPlacement],
           ~s(both declare the property "placement" on Ltix.Claims.LaunchPresentation)},
          {[TestPlugins.UndeclaredCheck],
           "checks the claim https://tool.example.com/claim/undeclared, which no plugin declares"}
        ] do
      test "when #{inspect(parties)} #{reason}", %{platform: platform} do
        assert {:error, %InvalidPluginSet{conflicts: [conflict]} = error} =
                 launch(platform, [], plugins: [{Modules, add: unquote(parties)}])

        assert %Conflict{parties: entries, reason: unquote(reason)} = conflict
        assert Enum.map(entries, & &1.module) == unquote(parties)

        for party <- unquote(parties),
            do: assert(Exception.message(error) =~ "#{inspect(party)} (Modules 1.0.0)")
      end
    end
  end

  describe "the version check" do
    test "rejects a version other than 1.3.0", %{platform: platform} do
      assert {:error,
              %InvalidClaim{
                claim: "version",
                message: "unrecognized LTI version",
                value: "1.2.0"
              }} = launch(platform, claims: %{@version => "1.2.0"})
    end
  end

  describe "the role_scope_mentor check" do
    test "rejects subject identifiers without the Mentor role", %{platform: platform} do
      assert {:error, %InvalidClaim{} = error} =
               launch(platform, claims: %{@role_scope_mentor => ["user-2"]})

      assert %{claim: "role_scope_mentor", value: ["user-2"]} = error
    end

    test "accepts subject identifiers with the Mentor role, and an empty list", %{
      platform: platform
    } do
      assert {:ok, launch} =
               launch(platform,
                 roles: [Role.context_mentor()],
                 claims: %{@role_scope_mentor => ["user-2"]}
               )

      assert launch.claims.role_scope_mentor == ["user-2"]

      assert {:ok, launch} = launch(platform, claims: %{@role_scope_mentor => []})
      assert launch.claims.role_scope_mentor == []
    end
  end
end
