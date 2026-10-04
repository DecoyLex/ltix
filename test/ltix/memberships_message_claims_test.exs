defmodule Ltix.MembershipsMessageClaimsTest do
  use ExUnit.Case, async: false

  import Ltix.Test.MembershipsServiceHelper

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.LaunchClaims
  alias Ltix.LaunchClaims.Context
  alias Ltix.LaunchClaims.MembershipsEndpoint

  alias Ltix.MembershipsService
  alias Ltix.MembershipsService.Member
  alias Ltix.MembershipsService.MembershipContainer

  setup do
    %{client: create_client()}
  end

  defmodule CustomMessage do
    defstruct [:value]
  end

  for page <- [1, 2, 3] do
    test "standard message claim shapes stay classified on page #{page}", %{client: client} do
      page = unquote(page)

      messages = [
        {%{"https://purl.imsglobal.org/spec/lti/claim/message_type" => 123}, "message_type", 123,
         "Core §5.3"},
        {%{"aud" => [123]}, "aud.0", 123, "Core §5.3"},
        {%{"exp" => "invalid"}, "exp", "invalid", "Core §5.3"},
        {%{"https://purl.imsglobal.org/spec/lti/claim/resource_link" => []}, "resource_link", [],
         "Core §5.3.5"},
        {%{"https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings" => 123},
         "deep_linking_settings", 123, "DL §4.4.1"}
      ]

      for {message, claim, value, spec_ref} <- messages do
        body =
          Map.put(container(page), "members", [Map.put(member("invalid"), "message", [message])])

        stub_pages(page, body)

        assert {:error, %InvalidClaim{claim: ^claim, value: ^value, spec_ref: ^spec_ref}} =
                 MembershipsService.get_members(client)

        assert {:ok, stream} = MembershipsService.stream_members(client)
        error = assert_raise InvalidClaim, fn -> Enum.to_list(stream) end

        assert %InvalidClaim{claim: ^claim, value: ^value, spec_ref: ^spec_ref} = error
      end
    end

    for {key, field} <- [
          {"name", :name},
          {"email", :email},
          {"given_name", :given_name},
          {"family_name", :family_name},
          {"middle_name", :middle_name},
          {"picture", :picture},
          {"locale", :locale},
          {"https://purl.imsglobal.org/spec/lti/claim/context", :context},
          {"https://purl.imsglobal.org/spec/lti/claim/tool_platform", :tool_platform},
          {"https://purl.imsglobal.org/spec/lti/claim/lis", :lis},
          {"https://purl.imsglobal.org/spec/lti/claim/launch_presentation", :launch_presentation},
          {"https://purl.imsglobal.org/spec/lti-ags/claim/endpoint", :ags_endpoint},
          {"https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice",
           :memberships_endpoint},
          {"https://purl.imsglobal.org/spec/lti/claim/role_scope_mentor", :role_scope_mentor}
        ] do
      test "malformed optional message #{field} is omitted on page #{page}", %{client: client} do
        page = unquote(page)

        for value <- [123, false, [%{}]] do
          message = %{
            unquote(key) => value,
            "sub" => "user",
            "https://vendor.example.com/raw" => value
          }

          body =
            Map.put(container(page), "members", [Map.put(member("profile"), "message", [message])])

          stub_pages(page, body)

          assert {:ok, %MembershipContainer{members: members}} =
                   MembershipsService.get_members(client)

          assert %Member{user_id: "profile", message: [claims]} = List.last(members)
          assert Map.fetch!(claims, unquote(field)) == nil
          assert claims.subject == "user"
          assert claims.extensions["https://vendor.example.com/raw"] == value
          assert {:ok, stream} = MembershipsService.stream_members(client)
          assert Enum.to_list(stream) == members
        end
      end
    end

    test "invalid builtin message roles remain classified on page #{page}", %{client: client} do
      page = unquote(page)

      for roles <- [123, [123], [false], [nil], [[]], [%{}]] do
        message = %{"https://purl.imsglobal.org/spec/lti/claim/roles" => roles}

        body =
          Map.put(container(page), "members", [Map.put(member("invalid"), "message", [message])])

        stub_pages(page, body)

        assert {:error, %InvalidClaim{claim: "roles", value: ^roles}} =
                 MembershipsService.get_members(client)

        assert {:ok, stream} = MembershipsService.stream_members(client)
        assert_raise InvalidClaim, fn -> Enum.to_list(stream) end
      end
    end

    test "nullable builtin message fields and valid empty arrays remain accepted on page #{page}",
         %{client: client} do
      page = unquote(page)

      message = %{
        "https://purl.imsglobal.org/spec/lti/claim/context" => %{
          "id" => "course",
          "label" => nil,
          "title" => nil,
          "type" => []
        },
        "https://purl.imsglobal.org/spec/lti/claim/resource_link" => %{
          "id" => "link",
          "title" => nil,
          "description" => nil
        },
        "https://purl.imsglobal.org/spec/lti/claim/tool_platform" => %{
          "guid" => "platform",
          "name" => nil,
          "contact_email" => nil,
          "description" => nil,
          "url" => nil,
          "product_family_code" => nil,
          "version" => nil
        },
        "https://purl.imsglobal.org/spec/lti/claim/launch_presentation" => %{
          "document_target" => "tab",
          "height" => nil,
          "width" => nil,
          "return_url" => nil,
          "locale" => nil
        },
        "https://purl.imsglobal.org/spec/lti/claim/lis" => %{
          "person_sourcedid" => nil,
          "course_offering_sourcedid" => nil,
          "course_section_sourcedid" => nil
        },
        "https://purl.imsglobal.org/spec/lti-ags/claim/endpoint" => %{
          "scope" => [],
          "lineitems" => nil,
          "lineitem" => nil
        },
        "https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice" => %{
          "context_memberships_url" => nil,
          "service_versions" => []
        },
        "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings" => %{
          "deep_link_return_url" => "https://platform.example.com/return",
          "accept_types" => [],
          "accept_presentation_document_targets" => [],
          "accept_multiple" => nil,
          "accept_lineitem" => nil,
          "auto_create" => nil,
          "accept_media_types" => nil,
          "title" => nil,
          "text" => nil,
          "data" => nil
        }
      }

      body = Map.put(container(page), "members", [Map.put(member("valid"), "message", [message])])
      stub_pages(page, body)

      assert {:ok, %MembershipContainer{members: members}} =
               MembershipsService.get_members(client)

      assert %Member{
               message: [
                 %LaunchClaims{
                   context: %Context{id: "course", label: nil, title: nil, type: []},
                   resource_link: %Ltix.LaunchClaims.ResourceLink{
                     id: "link",
                     title: nil,
                     description: nil
                   },
                   tool_platform: %Ltix.LaunchClaims.ToolPlatform{guid: "platform", name: nil},
                   launch_presentation: %Ltix.LaunchClaims.LaunchPresentation{
                     document_target: "tab",
                     height: nil,
                     width: nil,
                     return_url: nil
                   },
                   lis: %Ltix.LaunchClaims.LIS{person_source_id: nil},
                   ags_endpoint: %Ltix.LaunchClaims.AGSEndpoint{scopes: [], line_items: nil},
                   memberships_endpoint: %MembershipsEndpoint{
                     service_versions: [],
                     context_memberships_url: nil
                   },
                   deep_linking_settings: %Ltix.LaunchClaims.DeepLinkingSettings{
                     accept_types: [],
                     accept_presentation_document_targets: [],
                     accept_multiple: nil,
                     data: nil
                   }
                 }
               ]
             } = List.last(members)

      assert {:ok, stream} = MembershipsService.stream_members(client)
      assert Enum.to_list(stream) == members
    end
  end

  test "registered custom message parsers and standard context parsing remain available", %{
    client: client
  } do
    configure_claim_parsers(%{
      "https://vendor.example.com/claim" => fn %{"value" => value} ->
        {:ok, %CustomMessage{value: value}}
      end
    })

    message = %{
      "exp" => 123.5,
      "iat" => 122.5,
      "https://purl.imsglobal.org/spec/lti/claim/context" => %{"id" => "course"},
      "https://purl.imsglobal.org/spec/lti/claim/roles" => ["Instructor"],
      "https://purl.imsglobal.org/spec/lti/claim/custom" => %{"country" => "Canada"},
      "https://vendor.example.com/claim" => %{"value" => 123},
      "https://vendor.example.com/unknown" => [123]
    }

    stub_pages(
      1,
      Map.put(container(1), "members", [Map.put(member("user-1"), "message", [message])])
    )

    assert {:ok, %MembershipContainer{members: [%Member{message: [claims]}]}} =
             MembershipsService.get_members(client)

    assert %LaunchClaims{
             expires_at: 123.5,
             issued_at: 122.5,
             context: %{id: "course"},
             roles: [%{name: :instructor}],
             custom: %{"country" => "Canada"},
             extensions: %{
               "https://vendor.example.com/claim" => %CustomMessage{value: 123},
               "https://vendor.example.com/unknown" => [123]
             }
           } = claims

    assert {:ok, stream} = MembershipsService.stream_members(client)

    assert [
             %Member{
               message: [
                 %LaunchClaims{
                   extensions: %{"https://vendor.example.com/claim" => %CustomMessage{value: 123}}
                 }
               ]
             }
           ] = Enum.to_list(stream)
  end

  for page <- [1, 2, 3] do
    for {key, field} <- [
          {"https://purl.imsglobal.org/spec/lti/claim/context", :context},
          {"https://purl.imsglobal.org/spec/lti/claim/roles", :roles},
          {"https://purl.imsglobal.org/spec/lti-ags/claim/endpoint", :ags_endpoint},
          {"name", :name},
          {"aud", :audience},
          {"exp", :expires_at},
          {"https://purl.imsglobal.org/spec/lti/claim/message_type", :message_type},
          {"https://purl.imsglobal.org/spec/lti/claim/custom", :custom}
        ] do
      test "configured #{field} overrides builtin parsing on page #{page}", %{client: client} do
        page = unquote(page)
        key = unquote(key)
        field = unquote(field)

        configure_claim_parsers(%{
          key => fn raw ->
            send(self(), {:parsed_claim, raw})
            {:ok, %CustomMessage{value: raw}}
          end
        })

        for raw <- [123, false, nil, [], %{"id" => [%{}]}] do
          message = %{key => raw}

          body =
            Map.put(container(page), "members", [
              Map.put(member("overridden"), "message", [message])
            ])

          stub_pages(page, body)

          assert {:ok, %MembershipContainer{members: members}} =
                   MembershipsService.get_members(client)

          assert %Member{message: [%LaunchClaims{} = claims]} = List.last(members)
          assert Map.fetch!(claims, field) == %CustomMessage{value: raw}
          assert_received {:parsed_claim, ^raw}
          refute_received {:parsed_claim, _}

          assert {:ok, stream} = MembershipsService.stream_members(client)
          assert Enum.to_list(stream) == members
          assert_received {:parsed_claim, ^raw}
          refute_received {:parsed_claim, _}
        end
      end
    end

    test "configured parsers can delegate prepared claims to the builtin schema on page #{page}",
         %{client: client} do
      page = unquote(page)

      configure_claim_parsers(%{
        "https://purl.imsglobal.org/spec/lti/claim/context" => fn %{"vendor_id" => id} ->
          Context.from_json(%Context{id: id})
        end
      })

      for id <- ["vendor-course", 123] do
        message = %{"https://purl.imsglobal.org/spec/lti/claim/context" => %{"vendor_id" => id}}

        body =
          Map.put(container(page), "members", [Map.put(member("vendor"), "message", [message])])

        stub_pages(page, body)

        case id do
          "vendor-course" ->
            assert {:ok, %MembershipContainer{members: members}} =
                     MembershipsService.get_members(client)

            assert %Member{message: [%LaunchClaims{context: %Context{id: "vendor-course"}}]} =
                     List.last(members)

            assert {:ok, stream} = MembershipsService.stream_members(client)
            assert Enum.to_list(stream) == members

          123 ->
            assert {:error, %InvalidClaim{claim: "context.id", value: 123}} =
                     MembershipsService.get_members(client)

            assert {:ok, stream} = MembershipsService.stream_members(client)
            error = assert_raise InvalidClaim, fn -> Enum.to_list(stream) end
            assert %InvalidClaim{claim: "context.id", value: 123} = error
        end
      end
    end

    test "configured builtin parser errors propagate unchanged on page #{page}", %{client: client} do
      page = unquote(page)

      expected =
        InvalidClaim.exception(
          claim: "configured.context",
          value: 123,
          message: "invalid vendor context"
        )

      configure_claim_parsers(%{
        "https://purl.imsglobal.org/spec/lti/claim/context" => fn 123 -> {:error, expected} end
      })

      message = %{"https://purl.imsglobal.org/spec/lti/claim/context" => 123}

      body =
        Map.put(container(page), "members", [Map.put(member("invalid"), "message", [message])])

      stub_pages(page, body)

      assert {:error, ^expected} = MembershipsService.get_members(client)
      assert {:ok, stream} = MembershipsService.stream_members(client)
      error = assert_raise InvalidClaim, fn -> Enum.to_list(stream) end
      assert error == expected
    end

    test "custom parser programming errors are not converted into service errors on page #{page}",
         %{client: client} do
      page = unquote(page)

      configure_claim_parsers(%{
        "https://purl.imsglobal.org/spec/lti/claim/context" => fn %{"vendor_id" => id} ->
          {:ok, %CustomMessage{value: id}}
        end
      })

      message = %{"https://purl.imsglobal.org/spec/lti/claim/context" => 123}

      body =
        Map.put(container(page), "members", [Map.put(member("invalid"), "message", [message])])

      stub_pages(page, body)

      assert_raise FunctionClauseError, fn -> MembershipsService.get_members(client) end
      assert {:ok, stream} = MembershipsService.stream_members(client)
      assert_raise FunctionClauseError, fn -> Enum.to_list(stream) end
    end

    test "custom and unknown message values remain unchanged on page #{page}", %{client: client} do
      page = unquote(page)

      configure_claim_parsers(%{
        "https://vendor.example.com/parsed" => fn raw -> {:ok, %CustomMessage{value: raw}} end
      })

      for raw <- [123, false, nil, [], %{"arbitrary" => [123]}] do
        message = %{
          "https://purl.imsglobal.org/spec/lti/claim/custom" => %{"arbitrary" => raw},
          "https://vendor.example.com/parsed" => raw,
          "https://vendor.example.com/unknown" => raw
        }

        body =
          Map.put(container(page), "members", [Map.put(member("custom"), "message", [message])])

        stub_pages(page, body)

        assert {:ok, %MembershipContainer{members: members}} =
                 MembershipsService.get_members(client)

        assert %Member{
                 message: [
                   %LaunchClaims{
                     custom: %{"arbitrary" => ^raw},
                     extensions: %{
                       "https://vendor.example.com/parsed" => %CustomMessage{value: ^raw},
                       "https://vendor.example.com/unknown" => ^raw
                     }
                   }
                 ]
               } = List.last(members)

        assert {:ok, stream} = MembershipsService.stream_members(client)
        assert Enum.to_list(stream) == members
      end
    end
  end

  for page <- [1, 2, 3] do
    for {key, field, type} <- [
          {"iss", :issuer, :string},
          {"sub", :subject, :string},
          {"aud", :audience, :audience},
          {"exp", :expires_at, :number},
          {"iat", :issued_at, :number},
          {"nonce", :nonce, :string},
          {"azp", :authorized_party, :string},
          {"https://purl.imsglobal.org/spec/lti/claim/message_type", :message_type, :string},
          {"https://purl.imsglobal.org/spec/lti/claim/version", :version, :string},
          {"https://purl.imsglobal.org/spec/lti/claim/deployment_id", :deployment_id, :string},
          {"https://purl.imsglobal.org/spec/lti/claim/target_link_uri", :target_link_uri, :string}
        ] do
      invalid_values =
        case type do
          :string -> [{123, ""}, {false, ""}, {%{}, ""}, {[], ""}, {[%{}], ""}]
          :number -> [{"invalid", ""}, {"123", ""}, {false, ""}, {%{}, ""}, {[], ""}]
          :audience -> [{123, ""}, {false, ""}, {%{}, ""}, {[123], ".0"}]
        end

      test "declared #{field} message types are validated on page #{page}", %{client: client} do
        page = unquote(page)
        key = unquote(key)
        claim = String.replace_prefix(key, "https://purl.imsglobal.org/spec/lti/claim/", "")
        invalid_values = unquote(Macro.escape(invalid_values))

        for {value, suffix} <- invalid_values do
          expected_claim = claim <> suffix
          message = %{key => value}

          body =
            Map.put(container(page), "members", [Map.put(member("invalid"), "message", [message])])

          stub_pages(page, body)

          assert {:error, %InvalidClaim{claim: ^expected_claim}} =
                   MembershipsService.get_members(client)

          assert {:ok, stream} = MembershipsService.stream_members(client)
          error = assert_raise InvalidClaim, fn -> Enum.to_list(stream) end
          assert %InvalidClaim{claim: ^expected_claim} = error
        end
      end
    end

    test "partial message scalars accept absence, nulls, fractional dates and either audience form on page #{page}",
         %{client: client} do
      page = unquote(page)

      for message <- [
            %{},
            %{
              "iss" => nil,
              "sub" => nil,
              "aud" => nil,
              "exp" => nil,
              "iat" => nil,
              "nonce" => nil,
              "azp" => nil,
              "email" => nil,
              "name" => nil,
              "given_name" => nil,
              "family_name" => nil,
              "middle_name" => nil,
              "picture" => nil,
              "locale" => nil,
              "https://purl.imsglobal.org/spec/lti/claim/message_type" => nil,
              "https://purl.imsglobal.org/spec/lti/claim/version" => nil,
              "https://purl.imsglobal.org/spec/lti/claim/deployment_id" => nil,
              "https://purl.imsglobal.org/spec/lti/claim/target_link_uri" => nil,
              "https://purl.imsglobal.org/spec/lti/claim/role_scope_mentor" => nil
            },
            %{"aud" => "tool", "exp" => 123.5, "iat" => 122.5},
            %{
              "aud" => ["tool", "other"],
              "exp" => 123,
              "iat" => 122,
              "https://purl.imsglobal.org/spec/lti/claim/role_scope_mentor" => []
            }
          ] do
        body =
          Map.put(container(page), "members", [Map.put(member("partial"), "message", [message])])

        stub_pages(page, body)

        assert {:ok, %MembershipContainer{members: members}} =
                 MembershipsService.get_members(client)

        assert %Member{message: [%LaunchClaims{} = claims]} = List.last(members)
        assert claims.issuer == nil
        assert claims.name == nil
        assert claims.message_type == nil
        assert claims.audience == message["aud"]
        assert claims.expires_at == message["exp"]
        assert claims.issued_at == message["iat"]

        assert claims.role_scope_mentor ==
                 message["https://purl.imsglobal.org/spec/lti/claim/role_scope_mentor"]

        assert {:ok, stream} = MembershipsService.stream_members(client)
        assert Enum.to_list(stream) == members
      end
    end
  end
end
