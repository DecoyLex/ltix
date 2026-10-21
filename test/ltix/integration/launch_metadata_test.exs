defmodule Ltix.Integration.LaunchMetadataTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Security.NonceReused
  alias Ltix.Launch
  alias Ltix.Role
  alias Ltix.Test.StorageAdapter

  @lti "https://purl.imsglobal.org/spec/lti/claim/"
  @ags "https://purl.imsglobal.org/spec/lti-ags/claim/endpoint"
  @memberships "https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice"
  @deep_linking "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings"

  setup do
    platform = Ltix.Test.setup_platform!()

    pid =
      start_supervised!({StorageAdapter, platforms: [platform]})

    StorageAdapter.set_pid(pid)
    %{platform: platform}
  end

  for field <- ~w(name email given_name family_name middle_name picture locale) do
    test "launch leaves a malformed #{field} nil without losing identity or valid metadata",
         context do
      field = unquote(field)

      for value <- [123, false, [], [%{}], %{"name" => "not a string"}] do
        {login, params} = begin_launch(context.platform, %{field => value, "custom-raw" => value})

        assert {:ok, %Launch{claims: claims} = launch} = callback(login, params)
        assert claims[String.to_existing_atom(field)] == nil
        assert claims.subject == "user-12345"
        assert claims.resource_link.id == "resource-link-001"
        assert Role.instructor?(claims.roles)
        assert launch.raw["custom-raw"] == value
        assert claims.custom == %{"arbitrary" => value}
        assert {:error, %NonceReused{}} = callback(login, params)
      end
    end
  end

  for {key, field, json, expected} <- [
        {@lti <> "context", :context,
         %{"id" => "course", "title" => "Course", "label" => false, "type" => [123]},
         %{id: "course", title: "Course", label: nil, type: nil}},
        {@lti <> "resource_link", :resource_link,
         %{"id" => "link", "title" => "Resource", "description" => 123},
         %{id: "link", title: "Resource", description: nil}},
        {@lti <> "tool_platform", :tool_platform,
         %{"guid" => "platform", "name" => "Platform", "url" => [], "version" => false},
         %{guid: "platform", name: "Platform", url: nil, version: nil}},
        {@lti <> "launch_presentation", :launch_presentation,
         %{"document_target" => "tab", "height" => %{}, "width" => 640, "locale" => false},
         %{document_target: "tab", height: nil, width: 640, locale: nil}},
        {@lti <> "lis", :lis,
         %{"person_sourcedid" => "person", "course_offering_sourcedid" => 123},
         %{person_source_id: "person", course_offering_source_id: nil}},
        {@ags, :ags_endpoint,
         %{"lineitems" => "https://platform.example.com/items", "scope" => [false]},
         %{line_items: "https://platform.example.com/items", scopes: nil}},
        {@memberships, :memberships_endpoint,
         %{
           "context_memberships_url" => "https://platform.example.com/members",
           "service_versions" => [123]
         },
         %{context_memberships_url: "https://platform.example.com/members", service_versions: nil}}
      ] do
    test "launch preserves valid #{field} data alongside malformed optional fields", context do
      {login, params} =
        begin_launch(context.platform, %{unquote(key) => unquote(Macro.escape(json))})

      assert {:ok, %Launch{claims: claims}} = callback(login, params)
      parsed = Map.fetch!(claims, unquote(field))
      assert Map.take(parsed, unquote(Map.keys(expected))) == unquote(Macro.escape(expected))
      assert claims.subject == "user-12345"
    end
  end

  for {key, field} <- [
        {@lti <> "context", :context},
        {@lti <> "tool_platform", :tool_platform},
        {@lti <> "launch_presentation", :launch_presentation},
        {@lti <> "lis", :lis},
        {@ags, :ags_endpoint},
        {@memberships, :memberships_endpoint},
        {@lti <> "role_scope_mentor", :role_scope_mentor}
      ] do
    test "launch leaves an unusable optional #{field} claim nil", context do
      for value <- [123, false, "invalid", [123]] do
        {login, params} = begin_launch(context.platform, %{unquote(key) => value})
        assert {:ok, %Launch{claims: claims}} = callback(login, params)
        assert claims[unquote(field)] == nil
        assert claims.subject == "user-12345"
        assert claims.resource_link.id == "resource-link-001"
      end
    end
  end

  test "launch leaves optional objects with unusable identifiers nil", context do
    for field <- [:context, :tool_platform], value <- [%{}, %{"id" => 123}] do
      {login, params} = begin_launch(context.platform, %{(@lti <> to_string(field)) => value})

      assert {:ok, %Launch{claims: claims}} = callback(login, params)
      assert claims[field] == nil
    end
  end

  test "deep linking preserves required settings and omits malformed preferences", context do
    settings = %{
      "deep_link_return_url" => "https://platform.example.com/return",
      "accept_types" => ["ltiResourceLink"],
      "accept_presentation_document_targets" => ["iframe"],
      "accept_multiple" => 123,
      "accept_lineitem" => "true",
      "auto_create" => [],
      "accept_media_types" => false,
      "title" => 123,
      "text" => %{},
      "data" => "opaque"
    }

    {login, params} =
      begin_launch(context.platform, %{
        (@lti <> "message_type") => "LtiDeepLinkingRequest",
        @deep_linking => settings
      })

    assert {:ok, %Launch{claims: %{deep_linking_settings: parsed}}} =
             callback(login, params)

    assert parsed.deep_link_return_url == settings["deep_link_return_url"]
    assert parsed.accept_types == ["ltiResourceLink"]
    assert parsed.accept_presentation_document_targets == ["iframe"]
    assert parsed.data == "opaque"
    assert parsed.accept_multiple == nil
    assert parsed.accept_line_item == nil
    assert parsed.auto_create == nil
    assert parsed.accept_media_types == nil
    assert parsed.title == nil
    assert parsed.text == nil
  end

  test "malformed identity and essential resource launch fields are invalid", context do
    for {overrides, claim, value} <- [
          {%{"sub" => 123}, "sub", 123},
          {%{"sub" => ""}, "sub", ""},
          {%{(@lti <> "resource_link") => %{"id" => 123}}, "resource_link.id", 123},
          {%{(@lti <> "resource_link") => 123}, "resource_link", 123},
          {%{(@lti <> "target_link_uri") => false}, "target_link_uri", false},
          {%{(@lti <> "deployment_id") => []}, "deployment_id", []},
          {%{(@lti <> "roles") => "Instructor"}, "roles", "Instructor"},
          {%{(@lti <> "roles") => [123]}, "roles.0", 123}
        ] do
      {login, params} = begin_launch(context.platform, overrides)
      assert {:error, %InvalidClaim{claim: ^claim, value: ^value}} = callback(login, params)
    end
  end

  test "malformed Deep Linking settings or resource links fail every launch", context do
    settings = %{
      "deep_link_return_url" => "https://platform.example.com/return",
      "accept_types" => ["ltiResourceLink"],
      "accept_presentation_document_targets" => ["iframe"]
    }

    for message_type <- ["LtiResourceLinkRequest", "LtiDeepLinkingRequest"] do
      for field <- ~w(deep_link_return_url accept_types accept_presentation_document_targets),
          value <- [123, false, %{}] do
        {login, params} =
          begin_launch(context.platform, %{
            (@lti <> "message_type") => message_type,
            @deep_linking => Map.put(settings, field, value)
          })

        claim = "deep_linking_settings." <> field
        assert {:error, %InvalidClaim{claim: ^claim, value: ^value}} = callback(login, params)
      end

      for {resource_link, claim} <- [{123, "resource_link"}, {%{"id" => 123}, "resource_link.id"}] do
        {login, params} =
          begin_launch(context.platform, %{
            (@lti <> "message_type") => message_type,
            @deep_linking => settings,
            (@lti <> "resource_link") => resource_link
          })

        assert {:error, %InvalidClaim{claim: ^claim}} = callback(login, params)
      end
    end
  end

  test "launch accepts unambiguous numeric string dimensions", context do
    {login, params} =
      begin_launch(context.platform, %{
        (@lti <> "launch_presentation") => %{
          "height" => "600",
          "width" => "800.5",
          "document_target" => "iframe"
        }
      })

    assert {:ok,
            %Launch{
              claims: %{
                launch_presentation: %{
                  height: 600,
                  width: 800.5,
                  document_target: "iframe"
                }
              }
            }} = callback(login, params)
  end

  test "deep linking returns opaque JSON data from a nonconforming platform unchanged", context do
    for data <- [
          %{"session" => 123, "flags" => [false, nil, %{"vendor" => "value"}]},
          ["opaque", 123, false, nil],
          123,
          123.5,
          false,
          true,
          [],
          %{},
          "opaque"
        ] do
      {login, params} =
        begin_launch(context.platform, %{
          (@lti <> "message_type") => "LtiDeepLinkingRequest",
          @deep_linking => %{
            "deep_link_return_url" => "https://platform.example.com/return",
            "accept_types" => ["ltiResourceLink"],
            "accept_presentation_document_targets" => ["iframe"],
            "title" => [%{}],
            "data" => data
          }
        })

      assert {:ok, %Launch{} = launch} = callback(login, params)
      assert launch.claims.deep_linking_settings.title == nil
      assert launch.claims.deep_linking_settings.data == data
      assert {:ok, response} = Ltix.DeepLinking.build_response(launch)
      assert response.return_url == "https://platform.example.com/return"

      assert {:ok, claims} =
               Ltix.Test.verify_deep_linking_response(context.platform, response.jwt)

      [_header, payload, _signature] = String.split(response.jwt, ".")

      json_claims =
        payload
        |> Base.url_decode64!(padding: false)
        |> Ltix.AppConfig.json_library!().decode!()

      assert json_claims["https://purl.imsglobal.org/spec/lti-dl/claim/data"] == data
      assert claims[@lti <> "message_type"] == "LtiDeepLinkingResponse"
      assert claims["https://purl.imsglobal.org/spec/lti-dl/claim/content_items"] == []
    end
  end

  defp begin_launch(platform, overrides) do
    {:ok, login} =
      Ltix.handle_login(Ltix.Test.login_params(platform), "https://tool.example.com/launch",
        storage_adapter: StorageAdapter
      )

    claims =
      Ltix.Test.valid_lti_claims(
        platform,
        Map.merge(
          %{
            "nonce" => Ltix.Test.extract_nonce(login.redirect_uri),
            (@lti <> "custom") => %{"arbitrary" => overrides["custom-raw"]}
          },
          overrides
        )
      )

    token = Ltix.Test.sign_id_token(claims, platform.jwk)
    {login, %{"id_token" => token, "state" => login.state}}
  end

  defp callback(login, params, opts \\ []) do
    Ltix.handle_callback(
      params,
      login.state,
      Keyword.merge(
        [storage_adapter: StorageAdapter, req_options: [plug: {Req.Test, Ltix.JWT.KeySet}]],
        opts
      )
    )
  end
end
