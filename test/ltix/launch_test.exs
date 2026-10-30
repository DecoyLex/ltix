defmodule Ltix.LaunchTest do
  use ExUnit.Case, async: true

  import LaunchFlow

  doctest Ltix.Launch

  alias Ltix.Claims.ActualUser
  alias Ltix.Claims.Context
  alias Ltix.Claims.LaunchPresentation
  alias Ltix.Claims.LIS
  alias Ltix.Claims.Organization
  alias Ltix.Claims.ToolPlatform
  alias Ltix.DeepLinking.Settings
  alias Ltix.Errors.Invalid
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.Errors.Invalid.RegistrationNotFound
  alias Ltix.Errors.Security.NonceReused
  alias Ltix.Errors.Security.SignatureInvalid
  alias Ltix.Errors.Security.StateMismatch
  alias Ltix.Errors.Unknown.InvalidPluginSet
  alias Ltix.GradeService.Endpoint
  alias Ltix.JWT.Token
  alias Ltix.Launch
  alias Ltix.MembershipsService.Endpoint, as: MembershipsServiceEndpoint
  alias Ltix.PluginSet.Conflict
  alias Ltix.PluginSet.Entry
  alias Ltix.Role
  alias Ltix.Test.StorageAdapter
  alias TestPlugins.Modules

  @lti "https://purl.imsglobal.org/spec/lti/claim/"
  @deep_linking_settings "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings"
  @traced "https://tool.example.com/claim/traced"
  @tenant "https://tool.example.com/claim/tenant"
  @ags_scope "https://purl.imsglobal.org/spec/lti-ags/scope/score"

  setup do
    platform = Ltix.Test.setup_platform!()
    StorageAdapter.set_pid(start_supervised!({StorageAdapter, platforms: [platform]}))
    %{platform: platform}
  end

  # Launches with the claim `TestPlugins.Failing` declares, which it fails to
  # parse as `failing_opts` say.
  defp launch_failing(platform, failing_opts) do
    launch(platform, [claims: %{"https://tool.example.com/claim/failing" => "value"}],
      plugins: [{Modules, add: [{TestPlugins.Failing, failing_opts}]}]
    )
  end

  # Logs in and returns the params of a launch with `opts`, and the state.
  defp launch_params(platform, opts) do
    login = login!(platform)

    {Ltix.Test.launch_params(platform, [nonce: nonce(login), state: login.state] ++ opts),
     login.state}
  end

  describe "a resource link launch" do
    test "returns the launch", %{platform: platform} do
      {params, state} =
        launch_params(platform,
          ags_endpoint: %{line_item: "https://platform.example.com/items/1", scopes: [@ags_scope]}
        )

      assert {:ok, %Launch{} = launch} = callback(params, state)

      assert launch.registration == platform.registration
      assert launch.deployment == platform.deployment
      assert launch.source_registration == platform.registration
      assert launch.source_deployment == platform.deployment

      {:ok, raw} = Token.peek_claims(params["id_token"])
      assert launch.raw == raw

      assert launch.claims.message_type == "LtiResourceLinkRequest"
      assert launch.claims.subject == "user-12345"
      assert launch.claims.resource_link.id == "resource-link-001"
      assert launch.claims.roles == [Role.context_instructor()]

      assert %Endpoint{line_item: "https://platform.example.com/items/1"} =
               Launch.get_endpoint(launch, Ltix.GradeService)

      assert launch.claims.ags_endpoint == Launch.get_endpoint(launch, Ltix.GradeService)
      assert launch.errors == []
    end

    test "reports a missing resource link and roles", %{platform: platform} do
      assert {:error, %Invalid{errors: errors}} =
               launch_with_claims(platform, fn claims ->
                 Map.drop(claims, [@lti <> "resource_link", @lti <> "roles"])
               end)

      assert [%MissingClaim{claim: "resource_link"}, %MissingClaim{claim: "roles"}] =
               Enum.sort_by(errors, & &1.claim)
    end

    test "requires a subject unless anonymous launches are allowed", %{platform: platform} do
      assert {:error, %MissingClaim{claim: "sub"}} = launch(platform, subject: nil)

      assert {:ok, launch} = launch(platform, [subject: nil], allow_anonymous: true)
      assert launch.claims.subject == nil
    end

    test "rejects an empty subject", %{platform: platform} do
      assert {:error,
              %InvalidClaim{
                claim: "sub",
                value: "",
                message: "must be a non-empty string"
              }} = launch(platform, [subject: ""], allow_anonymous: true)
    end
  end

  describe "plugin steps" do
    test "run in login and launch from one module with a clause for each", %{platform: platform} do
      plugins = [plugins: [{Modules, add: [TestPlugins.LoginAndLaunch]}]]

      {:ok, login} =
        Ltix.handle_login(
          Ltix.Test.login_params(platform),
          "https://tool.example.com/launch",
          plugins
        )

      assert_received {:ran, :login}

      params = Ltix.Test.launch_params(platform, nonce: nonce(login), state: login.state)
      assert {:ok, _launch} = callback(params, login.state, plugins)
      assert_received {:ran, :launch}
    end
  end

  describe "phases" do
    test "a step after Ltix.Launch.Verified reads the registration and raw claims",
         %{platform: platform} do
      step = {TestPlugins.ReadVerified, pid: self()}

      assert {:ok, launch} = launch(platform, [], plugins: [{Modules, add: [step]}])

      assert_received {:verified, verified}
      assert verified.registration == platform.registration
      assert verified.raw == launch.raw
    end

    test "a step after Ltix.Launch.Verified doesn't run for a message that fails verification",
         %{platform: platform} do
      plugins = [plugins: [{Modules, add: [{TestPlugins.ReadVerified, pid: self()}]}]]

      {params, _state} = launch_params(platform, [])
      assert {:error, %StateMismatch{}} = callback(params, "other-state", plugins)
      refute_received {:verified, _launch}

      login = login!(platform)
      claims = Ltix.Test.valid_lti_claims(platform, %{"nonce" => nonce(login)})

      params = %{
        "id_token" =>
          Ltix.Test.sign_id_token(claims, Ltix.JWK.generate(key_size: 2048),
            kid: platform.jwk.kid
          ),
        "state" => login.state
      }

      assert {:error, %SignatureInvalid{}} = callback(params, login.state, plugins)
      refute_received {:verified, _launch}
    end

    test "Ltix parses the raw claims a step before Ltix.Launch.ClaimsReceived changes",
         %{platform: platform} do
      step = {TestPlugins.RewriteSubject, subject: "rewritten"}

      assert {:ok, launch} = launch(platform, [], plugins: [{Modules, add: [step]}])

      assert launch.claims.subject == "rewritten"
    end

    test "a step after Ltix.Launch.ClaimsParsed reads the parsed claims",
         %{platform: platform} do
      assert {:ok, _launch} =
               launch(platform, [], plugins: [{Modules, add: [TestPlugins.ReadClaims]}])

      assert_received {:claims,
                       %{subject: "user-12345", resource_link: %{id: "resource-link-001"}}}
    end

    test "a step after Ltix.Launch.Validated reads the missing claim errors",
         %{platform: platform} do
      step = {TestPlugins.ReadValidated, pid: self()}

      assert {:error, %MissingClaim{claim: "resource_link"}} =
               launch_with_claims(platform, &Map.delete(&1, @lti <> "resource_link"),
                 plugins: [{Modules, add: [step]}]
               )

      assert_received {:validated, %Launch{errors: [%MissingClaim{claim: "resource_link"}]}}
    end

    test "a step after every module reads the deployment, even when a later plugin orders a step before Ltix.Launch.Validated",
         %{platform: platform} do
      plugins = [
        {Modules, add: [{TestPlugins.ReadLast, pid: self()}]},
        {Modules, name: "Later", add: [TestPlugins.BeforeValidated]}
      ]

      assert {:ok, _launch} = launch(platform, [], plugins: plugins)

      assert_received {:last, last}
      assert last.deployment == platform.deployment
    end

    test "an anonymous step that run_after/3 orders after Ltix.Launch.ClaimsParsed reads the parsed claims",
         %{platform: platform} do
      build = fn plugin ->
        Ltix.Launch.run_after(plugin, Ltix.Launch.ClaimsParsed, fn plugin ->
          Ltix.Launch.add_step(plugin, fn launch ->
            send(self(), {:subject, launch.claims.subject})
            {:ok, launch}
          end)
        end)
      end

      assert {:ok, _launch} = launch(platform, [], plugins: [{Modules, build: build}])
      assert_received {:subject, "user-12345"}
    end

    test "an anonymous step after Ltix.Launch.DeploymentFound reads the deployment",
         %{platform: platform} do
      build = fn plugin ->
        Ltix.Launch.run_after(plugin, Ltix.Launch.DeploymentFound, fn plugin ->
          Ltix.Launch.add_step(plugin, fn launch ->
            send(self(), {:deployment, launch.deployment})
            {:ok, launch}
          end)
        end)
      end

      plugins = [
        {Modules, build: build},
        {Modules, name: "Later", add: [{TestPlugins.ReadLast, pid: self()}]}
      ]

      assert {:ok, _launch} = launch(platform, [], plugins: plugins)
      assert_received {:deployment, deployment}
      assert deployment == platform.deployment
    end
  end

  describe "the deployment" do
    test "is looked up after the claims pass", %{platform: platform} do
      assert {:ok, launch} = launch(platform, [], storage_adapter: LaunchStorageAdapter)
      assert_received {:get_deployment, "deployment-001"}
      assert launch.deployment == platform.deployment
    end

    test "isn't looked up for a launch whose claims fail", %{platform: platform} do
      for {claims, error} <- [
            {%{(@lti <> "resource_link") => %{"title" => "No ID"}}, MissingClaim},
            {%{(@lti <> "version") => "1.2.0"}, InvalidClaim},
            {%{(@lti <> "message_type") => "LtiUnknownRequest"}, InvalidClaim},
            {%{(@lti <> "roles") => nil}, MissingClaim}
          ] do
        assert {:error, %^error{}} =
                 launch(platform, [claims: claims], storage_adapter: LaunchStorageAdapter)

        refute_received {:get_deployment, _deployment_id}
      end
    end
  end

  describe "a Deep Linking request" do
    test "is accepted without a resource link or roles", %{platform: platform} do
      assert {:ok, launch} =
               launch(platform, message_type: :deep_linking, claims: %{(@lti <> "roles") => nil})

      assert %Settings{} = launch.claims.deep_linking_settings
      assert launch.claims.resource_link == nil
      assert launch.claims.roles == []
    end

    test "is accepted with an empty subject", %{platform: platform} do
      assert {:ok, launch} = launch(platform, message_type: :deep_linking, subject: "")
      assert launch.claims.subject == ""
    end
  end

  describe "claims" do
    test "have a nil key for each declared claim the platform didn't send", %{platform: platform} do
      assert {:ok, launch} =
               launch_with_claims(
                 platform,
                 &(&1
                   |> Map.delete(@lti <> "context")
                   |> Map.put("https://lms.example.com/claim/undeclared", true)),
                 plugins: [{Modules, add: [TestPlugins.Traced]}]
               )

      assert launch.claims.context == nil
      assert launch.claims.traced == nil
      assert launch.claims.lis == nil
      refute Map.has_key?(launch.claims, :undeclared)
      assert launch.raw["https://lms.example.com/claim/undeclared"] == true
    end

    test "parse the organization and the actual user", %{platform: platform} do
      assert {:ok, launch} =
               launch(platform,
                 claims: %{
                   (@lti <> "organization") => %{"id" => "example.edu", "type" => "institution"},
                   (@lti <> "actual_user") => %{
                     "id" => "admin-1",
                     "name" => "Ada Admin",
                     "roles" => [Role.institution_administrator()]
                   }
                 }
               )

      assert %Organization{id: "example.edu", type: "institution", name: nil} =
               launch.claims.organization

      assert %ActualUser{id: "admin-1", name: "Ada Admin"} = launch.claims.actual_user
      assert launch.claims.actual_user.roles == [Role.institution_administrator()]
      assert Role.administrator?(launch.claims.actual_user.roles)
    end

    test "declared with strict: false are nil when malformed, stay in the raw claims, and the launch succeeds",
         %{
           platform: platform
         } do
      for {claim, value} <- [{"lis", 123}, {"context", %{"title" => "No ID"}}] do
        assert {:ok, launch} = launch(platform, claims: %{(@lti <> claim) => value})

        assert launch.claims[String.to_existing_atom(claim)] == nil
        assert launch.raw[@lti <> claim] == value
      end
    end

    test "make a malformed optional field nil", %{platform: platform} do
      presentation = %{"width" => "abc", "height" => 600, "document_target" => "iframe"}

      assert {:ok, launch} =
               launch(platform, claims: %{(@lti <> "launch_presentation") => presentation})

      assert %LaunchPresentation{width: nil, height: 600, document_target: "iframe"} =
               launch.claims.launch_presentation
    end

    test "fail the launch for a malformed resource link or Deep Linking settings", %{
      platform: platform
    } do
      for message_type <- [:resource_link, :deep_linking] do
        assert {:error, %MissingClaim{claim: "resource_link.id"}} =
                 launch(platform,
                   message_type: message_type,
                   claims: %{(@lti <> "resource_link") => %{"title" => "No ID"}}
                 )

        assert {:error, %InvalidClaim{claim: "deep_linking_settings", value: "settings"}} =
                 launch(platform,
                   message_type: message_type,
                   claims: %{@deep_linking_settings => "settings"}
                 )
      end
    end

    test "report a malformed claim together with the claims the launch is missing", %{
      platform: platform
    } do
      assert {:error, %Invalid{errors: errors}} =
               launch(platform,
                 claims: %{
                   (@lti <> "resource_link") => %{"title" => "No ID"},
                   (@lti <> "roles") => nil
                 }
               )

      assert [%MissingClaim{claim: "resource_link.id"}, %MissingClaim{claim: "roles"}] =
               Enum.sort_by(errors, & &1.claim)
    end

    test "keep undeclared claims in the raw claims, and unrecognized properties in unrecognized",
         %{
           platform: platform
         } do
      assert {:ok, launch} =
               launch(platform,
                 claims: %{
                   "https://vendor.example.com/session" => "s-1",
                   (@lti <> "launch_presentation") => %{
                     "placement" => "sidebar",
                     "locale" => "en"
                   }
                 }
               )

      assert launch.raw["https://vendor.example.com/session"] == "s-1"
      refute Enum.any?(Map.values(launch.claims), &(&1 == "s-1"))

      assert %LaunchPresentation{locale: "en", unrecognized: %{"placement" => "sidebar"}} =
               launch.claims.launch_presentation
    end

    test "aren't parsed after a security check halts the launch", %{platform: platform} do
      plugins = [plugins: [{Modules, add: [TestPlugins.Traced]}]]
      traced = %{@traced => "value"}

      {params, _state} = launch_params(platform, claims: traced)
      assert {:error, %StateMismatch{}} = callback(params, "other-state", plugins)

      {params, state} = launch_params(platform, claims: traced)
      assert {:ok, _launch} = callback(params, state, plugins)
      assert_received {:parsed, "value"}
      assert {:error, %NonceReused{}} = callback(params, state, plugins)

      assert {:error, %RegistrationNotFound{}} =
               launch_with_claims(
                 platform,
                 &Map.merge(&1, Map.put(traced, "iss", "https://unknown.example.com")),
                 plugins
               )

      login = login!(platform)

      claims =
        Ltix.Test.valid_lti_claims(platform, %{"nonce" => nonce(login), @traced => "value"})

      params = %{
        "id_token" =>
          Ltix.Test.sign_id_token(claims, Ltix.JWK.generate(key_size: 2048),
            kid: platform.jwk.kid
          ),
        "state" => login.state
      }

      assert {:error, %SignatureInvalid{}} = callback(params, login.state, plugins)
      refute_received {:parsed, _value}
    end

    test "parse every claim Ltix declares", %{platform: platform} do
      claims = %{
        "email" => "jane@example.com",
        "name" => "Jane Doe",
        "given_name" => "Jane",
        "family_name" => "Doe",
        "middle_name" => "Q",
        "picture" => "https://example.com/jane.jpg",
        "locale" => "en-US",
        "azp" => "tool-client-id",
        (@lti <> "role_scope_mentor") => ["user-001", "user-002"],
        (@lti <> "custom") => %{"country" => "Canada"},
        (@lti <> "tool_platform") => %{"guid" => "platform-1", "product_family_code" => "lms"},
        (@lti <> "lis") => %{
          "person_sourcedid" => "sis-person",
          "course_offering_sourcedid" => "sis-course",
          "course_section_sourcedid" => "sis-section"
        },
        "https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice" => %{
          "context_memberships_url" => "https://platform.example.com/members",
          "service_versions" => ["2.0"]
        }
      }

      {params, state} = launch_params(platform, roles: [Role.context_mentor()], claims: claims)
      assert {:ok, launch} = callback(params, state)

      assert %{
               issuer: "https://platform.example.com",
               subject: "user-12345",
               audience: "tool-client-id",
               expires_at: exp,
               issued_at: iat,
               nonce: nonce,
               authorized_party: "tool-client-id",
               email: "jane@example.com",
               name: "Jane Doe",
               given_name: "Jane",
               family_name: "Doe",
               middle_name: "Q",
               picture: "https://example.com/jane.jpg",
               locale: "en-US",
               message_type: "LtiResourceLinkRequest",
               version: "1.3.0",
               deployment_id: "deployment-001",
               target_link_uri: "https://tool.example.com/launch",
               role_scope_mentor: ["user-001", "user-002"],
               custom: %{"country" => "Canada"},
               tool_platform: %ToolPlatform{
                 guid: "platform-1",
                 product_family_code: "lms"
               },
               lis: %LIS{
                 person_source_id: "sis-person",
                 course_offering_source_id: "sis-course",
                 course_section_source_id: "sis-section"
               },
               memberships_endpoint: %MembershipsServiceEndpoint{
                 context_memberships_url: "https://platform.example.com/members",
                 service_versions: ["2.0"]
               }
             } = launch.claims

      assert {exp, iat, nonce} == {launch.raw["exp"], launch.raw["iat"], launch.raw["nonce"]}

      assert Launch.get_endpoint(launch, Ltix.MembershipsService) ==
               launch.claims.memberships_endpoint
    end

    test "that are null count as absent", %{platform: platform} do
      assert {:ok, launch} =
               launch(platform, [claims: %{@traced => nil}],
                 plugins: [{Modules, add: [TestPlugins.Traced]}]
               )

      refute_received {:parsed, _value}
      assert launch.claims.traced == nil
    end

    test "report every malformed claim", %{platform: platform} do
      assert {:error, %Invalid{} = error} =
               launch(platform, claims: %{"sub" => 2, (@lti <> "message_type") => 1})

      assert [
               %InvalidClaim{claim: "message_type", value: 1},
               %InvalidClaim{claim: "sub", value: 2}
             ] =
               Enum.sort_by(error.errors, & &1.claim)

      assert Enum.sort(String.split(Exception.message(error), "\n")) == [
               "* Invalid LTI claim message_type: must be a string (got 1)",
               "* Invalid LTI claim sub: must be a string (got 2)"
             ]
    end

    test "report a declared claim's parse error", %{platform: platform} do
      for {reason, message} <- [
            {"must be an object", "must be an object"},
            {:no_session, ":no_session"},
            {RuntimeError.exception("parse failed"), "parse failed"}
          ] do
        assert {:error, %InvalidClaim{claim: "failing", value: "value", message: ^message}} =
                 launch_failing(platform, reason: reason)
      end

      ltix_error = InvalidClaim.exception(claim: "failing.id", value: "value", message: "no ID")

      assert {:error, %InvalidClaim{claim: "failing.id", message: "no ID"}} =
               launch_failing(platform, reason: ltix_error)
    end

    test "raise what a declared claim raises", %{platform: platform} do
      assert_raise ArgumentError, "parser bug", fn ->
        launch_failing(platform, raise: ArgumentError.exception("parser bug"))
      end
    end

    test "a plugin adds with Ltix.Claim.add/2 are parsed with their schema",
         %{platform: platform} do
      build = &Ltix.Claim.add(&1, claim: @tenant, name: :tenant, schema: Zoi.string())
      plugins = [plugins: [{Modules, build: build}]]

      assert {:ok, launch} = launch(platform, [claims: %{@tenant => "acme"}], plugins)
      assert launch.claims.tenant == "acme"

      assert {:error, %InvalidClaim{claim: "tenant", value: 123}} =
               launch(platform, [claims: %{@tenant => 123}], plugins)
    end

    test "a plugin adds with Ltix.Claim.add/2 have their default when absent or, with strict: false, malformed",
         %{platform: platform} do
      build =
        &Ltix.Claim.add(&1,
          claim: @tenant,
          name: :tenant,
          schema: Zoi.string(),
          strict: false,
          default: "none"
        )

      plugins = [plugins: [{Modules, build: build}]]

      for claims <- [%{}, %{@tenant => 123}] do
        assert {:ok, launch} = launch(platform, [claims: claims], plugins)
        assert launch.claims.tenant == "none"
      end
    end

    test "Ltix.Claim.add/2 raises for missing or invalid options" do
      assert_raise ArgumentError, ~r/:name/, fn ->
        Ltix.Plugin.new()
        |> Ltix.Claim.add(claim: @tenant)
      end

      assert_raise ArgumentError, ~r/must be a Zoi schema/, fn ->
        Ltix.Plugin.new()
        |> Ltix.Claim.add(claim: @tenant, name: :tenant, schema: :string)
      end
    end

    test "use Ltix.Claim raises for an option value of the wrong type" do
      for {opts, message} <- [
            {[claim: "", name: :tenant], "Ltix.Claim's :claim option must be a non-empty string"},
            {[claim: @tenant, name: "tenant"], "Ltix.Claim's :name option must be an atom"},
            {[claim: @tenant, name: :tenant, strict: "no"],
             "Ltix.Claim's :strict option must be a boolean"},
            {[claim: @tenant, name: :tenant, schema: :string],
             "Ltix.Claim's :schema option must be a Zoi schema"},
            {[claim: @tenant, name: :tenant, service: "grades"],
             "Ltix.Claim's :service option must be a module"}
          ] do
        assert_raise ArgumentError, ~r/^#{Regex.escape(message)}/, fn ->
          Code.compile_quoted(
            quote do
              defmodule InvalidTenant do
                use Ltix.Claim, unquote(opts)
              end
            end
          )
        end
      end
    end

    test "have the properties plugins declare on each object claim", %{platform: platform} do
      note = %{"https://vendor.example.com/note" => "n"}

      claims = %{
        (@lti <> "tool_platform") => Map.put(note, "guid", "platform-1"),
        (@lti <> "lis") => note,
        (@lti <> "organization") => Map.put(note, "id", "example.edu"),
        (@lti <> "actual_user") => Map.put(note, "id", "admin-1"),
        @deep_linking_settings =>
          Map.merge(note, %{
            "deep_link_return_url" => "https://platform.example.com/deep_links",
            "accept_types" => ["link"],
            "accept_presentation_document_targets" => ["iframe"]
          }),
        "https://purl.imsglobal.org/spec/lti-ags/claim/endpoint" =>
          Map.merge(note, %{
            "scope" => [@ags_scope],
            "lineitem" => "https://platform.example.com/items/1"
          }),
        "https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice" =>
          Map.merge(note, %{
            "context_memberships_url" => "https://platform.example.com/members",
            "service_versions" => ["2.0"]
          })
      }

      assert {:ok, launch} =
               launch(platform, [claims: claims], plugins: [{Modules, add: [TestPlugins.Note]}])

      for name <- [
            :tool_platform,
            :lis,
            :organization,
            :actual_user,
            :deep_linking_settings,
            :ags_endpoint,
            :memberships_endpoint
          ] do
        assert launch.claims[name].extensions == %{note: "n"}, "no note on #{name}"
      end
    end
  end

  describe "declared claims conflict" do
    for {default, module, reason} <- [
          {Context, TestPlugins.OtherContext,
           "both declare the claim https://purl.imsglobal.org/spec/lti/claim/context"},
          {Context, TestPlugins.Course, "both declare the short name :context"},
          {Endpoint, TestPlugins.Grades, "both declare the endpoint of Ltix.GradeService"}
        ] do
      test "when #{inspect(module)} #{reason}", %{platform: platform} do
        {default, module} = {unquote(default), unquote(module)}

        assert {:error, %InvalidPluginSet{conflicts: [conflict]} = error} =
                 launch(platform, [], plugins: [{Modules, add: [module]}])

        assert %Conflict{
                 parties: [%Entry{module: ^default}, %Entry{module: ^module}],
                 reason: unquote(reason)
               } = conflict

        assert Exception.message(error) =~ "#{inspect(default)} (LTI"
        assert Exception.message(error) =~ "#{inspect(module)} (Modules 1.0.0)"
      end
    end

    test "when two plugins add one module with different options", %{platform: platform} do
      plugins = [
        {Modules, name: "First", add: [{TestPlugins.Traced, label: :first}]},
        {Modules, name: "Second", add: [{TestPlugins.Traced, label: :second}]}
      ]

      assert {:error, %InvalidPluginSet{conflicts: [_conflict]} = error} =
               launch(platform, [], plugins: plugins)

      assert Exception.message(error) ==
               "TestPlugins.Traced (First 1.0.0) and TestPlugins.Traced (Second 1.0.0) both declare the claim #{@traced}"
    end

    test "when an anonymous claim and a claim module declare one claim", %{platform: platform} do
      plugins = [
        {Modules, name: "First", add: [TestPlugins.Traced]},
        {Modules, name: "Second", build: &Ltix.Claim.add(&1, claim: @traced, name: :other)}
      ]

      assert {:error, %InvalidPluginSet{} = error} = launch(platform, [], plugins: plugins)

      assert Exception.message(error) ==
               "TestPlugins.Traced (First 1.0.0) and an anonymous claim of Second 1.0.0 both declare the claim #{@traced}"
    end

    test "not when two plugins add one module with the same options", %{platform: platform} do
      plugins = [
        {Modules, name: "First", add: [{TestPlugins.Traced, label: :shared}]},
        {Modules, name: "Second", add: [{TestPlugins.Traced, label: :shared}]}
      ]

      assert {:ok, launch} = launch(platform, [claims: %{@traced => "value"}], plugins: plugins)
      assert launch.claims.traced == "value"
      assert_received {:parsed, "value"}
      refute_received {:parsed, _value}
    end
  end
end
