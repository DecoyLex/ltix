defmodule Ltix.LaunchClaimsTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchClaims
  alias Ltix.Test.JWTHelper

  alias Ltix.LaunchClaims.AgsEndpoint
  alias Ltix.LaunchClaims.Context
  alias Ltix.LaunchClaims.DeepLinkingSettings
  alias Ltix.LaunchClaims.LaunchPresentation
  alias Ltix.LaunchClaims.Lis
  alias Ltix.LaunchClaims.MembershipsEndpoint
  alias Ltix.LaunchClaims.ResourceLink
  alias Ltix.LaunchClaims.Role
  alias Ltix.LaunchClaims.ToolPlatform

  doctest Ltix.LaunchClaims

  # --- OIDC Claims [Sec §5.1.2] ---

  describe "from_json/2 OIDC claims [Sec §5.1.2]" do
    test "parses all OIDC standard claims" do
      json = %{
        "iss" => "https://platform.example.com",
        "sub" => "user-123",
        "aud" => "tool-client-id",
        "exp" => 1_700_000_000,
        "iat" => 1_699_999_000,
        "nonce" => "nonce-abc",
        "azp" => "tool-client-id"
      }

      assert {:ok, %LaunchClaims{} = claims} = LaunchClaims.from_json(json)
      assert claims.issuer == "https://platform.example.com"
      assert claims.subject == "user-123"
      assert claims.audience == "tool-client-id"
      assert claims.expires_at == 1_700_000_000
      assert claims.issued_at == 1_699_999_000
      assert claims.nonce == "nonce-abc"
      assert claims.authorized_party == "tool-client-id"
    end

    # [OIDC Core §5.1] profile claims; [Core §5.3.6] user identity
    test "parses OIDC profile claims" do
      json = %{
        "email" => "user@example.com",
        "name" => "Jane Doe",
        "given_name" => "Jane",
        "family_name" => "Doe",
        "middle_name" => "M",
        "picture" => "https://example.com/photo.jpg",
        "locale" => "en-US"
      }

      assert {:ok, %LaunchClaims{} = claims} = LaunchClaims.from_json(json)
      assert claims.email == "user@example.com"
      assert claims.name == "Jane Doe"
      assert claims.given_name == "Jane"
      assert claims.family_name == "Doe"
      assert claims.middle_name == "M"
      assert claims.picture == "https://example.com/photo.jpg"
      assert claims.locale == "en-US"
    end
  end

  # --- LTI Claims [Core §5.3, §5.4] ---

  describe "from_json/2 LTI claims [Core §5.3]" do
    test "parses LTI required claims" do
      json = %{
        "https://purl.imsglobal.org/spec/lti/claim/message_type" => "LtiResourceLinkRequest",
        "https://purl.imsglobal.org/spec/lti/claim/version" => "1.3.0",
        "https://purl.imsglobal.org/spec/lti/claim/deployment_id" => "deploy-001",
        "https://purl.imsglobal.org/spec/lti/claim/target_link_uri" =>
          "https://tool.example.com/launch"
      }

      assert {:ok, %LaunchClaims{} = claims} = LaunchClaims.from_json(json)
      assert claims.message_type == "LtiResourceLinkRequest"
      assert claims.version == "1.3.0"
      assert claims.deployment_id == "deploy-001"
      assert claims.target_link_uri == "https://tool.example.com/launch"
    end

    # [Core §5.4.6] custom properties
    test "parses custom claim" do
      json = %{
        "https://purl.imsglobal.org/spec/lti/claim/custom" => %{
          "course_id" => "12345",
          "section_title" => "Section A"
        }
      }

      assert {:ok, %LaunchClaims{custom: custom}} = LaunchClaims.from_json(json)
      assert custom == %{"course_id" => "12345", "section_title" => "Section A"}
    end

    # [Core §5.4.3] role_scope_mentor
    test "parses role_scope_mentor" do
      json = %{
        "https://purl.imsglobal.org/spec/lti/claim/role_scope_mentor" => [
          "user-001",
          "user-002"
        ]
      }

      assert {:ok, %LaunchClaims{role_scope_mentor: mentees}} = LaunchClaims.from_json(json)
      assert mentees == ["user-001", "user-002"]
    end
  end

  # --- Role Parsing [Core §A.2] ---

  describe "from_json/2 roles [Core §5.3.7]" do
    test "parses roles into Role structs" do
      json = %{
        "https://purl.imsglobal.org/spec/lti/claim/roles" => [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor",
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"
        ]
      }

      assert {:ok, %LaunchClaims{roles: roles, unrecognized_roles: []}} =
               LaunchClaims.from_json(json)

      assert [%Role{name: :instructor}, %Role{name: :learner}] = roles
    end

    test "separates unrecognized roles" do
      json = %{
        "https://purl.imsglobal.org/spec/lti/claim/roles" => [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor",
          "http://example.com/custom#CustomRole"
        ]
      }

      assert {:ok, %LaunchClaims{roles: roles, unrecognized_roles: unrecognized}} =
               LaunchClaims.from_json(json)

      assert [%Role{name: :instructor}] = roles
      assert ["http://example.com/custom#CustomRole"] = unrecognized
    end

    # [Core §5.3.7.1] empty roles list (anonymous launch)
    test "handles empty roles list" do
      json = %{
        "https://purl.imsglobal.org/spec/lti/claim/roles" => []
      }

      assert {:ok, %LaunchClaims{roles: [], unrecognized_roles: []}} =
               LaunchClaims.from_json(json)
    end

    test "defaults roles to empty list when absent" do
      assert {:ok, %LaunchClaims{roles: [], unrecognized_roles: []}} =
               LaunchClaims.from_json(%{})
    end
  end

  # --- Nested Claim Structs ---

  describe "from_json/2 nested claims" do
    # [Core §5.4.1] context
    test "parses context into Context struct" do
      json = %{
        "https://purl.imsglobal.org/spec/lti/claim/context" => %{
          "id" => "ctx-001",
          "label" => "CS101",
          "title" => "Intro to CS"
        }
      }

      assert {:ok, %LaunchClaims{context: %Context{id: "ctx-001"}}} =
               LaunchClaims.from_json(json)
    end

    # [Core §5.3.5] resource_link
    test "parses resource_link into ResourceLink struct" do
      json = %{
        "https://purl.imsglobal.org/spec/lti/claim/resource_link" => %{
          "id" => "rl-001",
          "title" => "Assignment 1"
        }
      }

      assert {:ok, %LaunchClaims{resource_link: %ResourceLink{id: "rl-001"}}} =
               LaunchClaims.from_json(json)
    end

    # [Core §5.4.4] launch_presentation
    test "parses launch_presentation into LaunchPresentation struct" do
      json = %{
        "https://purl.imsglobal.org/spec/lti/claim/launch_presentation" => %{
          "document_target" => "iframe",
          "height" => 600,
          "width" => 800
        }
      }

      assert {:ok,
              %LaunchClaims{
                launch_presentation: %LaunchPresentation{document_target: "iframe"}
              }} = LaunchClaims.from_json(json)
    end

    # [Core §5.4.2] tool_platform
    test "parses tool_platform into ToolPlatform struct" do
      json = %{
        "https://purl.imsglobal.org/spec/lti/claim/tool_platform" => %{
          "guid" => "platform-guid",
          "name" => "Example LMS"
        }
      }

      assert {:ok, %LaunchClaims{tool_platform: %ToolPlatform{guid: "platform-guid"}}} =
               LaunchClaims.from_json(json)
    end

    # [Core §5.4.5] lis
    test "parses lis into Lis struct" do
      json = %{
        "https://purl.imsglobal.org/spec/lti/claim/lis" => %{
          "person_sourcedid" => "sis-001"
        }
      }

      assert {:ok, %LaunchClaims{lis: %Lis{person_sourcedid: "sis-001"}}} =
               LaunchClaims.from_json(json)
    end

    # [Core §5.4] missing optional nested claims default to nil
    test "missing optional nested claims default to nil" do
      assert {:ok, %LaunchClaims{} = claims} = LaunchClaims.from_json(%{})
      assert claims.context == nil
      assert claims.resource_link == nil
      assert claims.launch_presentation == nil
      assert claims.tool_platform == nil
      assert claims.lis == nil
    end

    # Present but invalid nested claims propagate errors
    test "invalid context propagates error" do
      json = %{
        "https://purl.imsglobal.org/spec/lti/claim/context" => %{
          "label" => "No ID"
        }
      }

      assert {:error, error} = LaunchClaims.from_json(json)
      assert Exception.message(error) =~ "context.id"
    end

    test "invalid resource_link propagates error" do
      json = %{
        "https://purl.imsglobal.org/spec/lti/claim/resource_link" => %{
          "title" => "No ID"
        }
      }

      assert {:error, error} = LaunchClaims.from_json(json)
      assert Exception.message(error) =~ "resource_link.id"
    end

    test "invalid launch_presentation propagates error" do
      json = %{
        "https://purl.imsglobal.org/spec/lti/claim/launch_presentation" => %{
          "document_target" => "invalid"
        }
      }

      assert {:error, error} = LaunchClaims.from_json(json)
      assert Exception.message(error) =~ "document_target"
    end
  end

  # --- Service Endpoint Claims [Core §6.1] ---

  describe "from_json/2 service endpoint claims [Core §6.1]" do
    test "parses AGS endpoint" do
      json = %{
        "https://purl.imsglobal.org/spec/lti-ags/claim/endpoint" => %{
          "scope" => ["https://purl.imsglobal.org/spec/lti-ags/scope/lineitem"],
          "lineitems" => "https://platform.example.com/lineitems"
        }
      }

      assert {:ok, %LaunchClaims{ags_endpoint: %AgsEndpoint{lineitems: url}}} =
               LaunchClaims.from_json(json)

      assert url == "https://platform.example.com/lineitems"
    end

    test "parses NRPS endpoint" do
      json = %{
        "https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice" => %{
          "context_memberships_url" => "https://platform.example.com/memberships",
          "service_versions" => ["2.0"]
        }
      }

      assert {:ok,
              %LaunchClaims{
                memberships_endpoint: %MembershipsEndpoint{context_memberships_url: url}
              }} =
               LaunchClaims.from_json(json)

      assert url == "https://platform.example.com/memberships"
    end

    test "parses deep linking settings" do
      json = %{
        "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings" => %{
          "deep_link_return_url" => "https://platform.example.com/dl/return",
          "accept_types" => ["link", "ltiResourceLink"]
        }
      }

      assert {:ok,
              %LaunchClaims{
                deep_linking_settings: %DeepLinkingSettings{
                  deep_link_return_url: "https://platform.example.com/dl/return"
                }
              }} = LaunchClaims.from_json(json)
    end

    test "missing service endpoints default to nil" do
      assert {:ok, %LaunchClaims{} = claims} = LaunchClaims.from_json(%{})
      assert claims.ags_endpoint == nil
      assert claims.memberships_endpoint == nil
      assert claims.deep_linking_settings == nil
    end
  end

  # --- Extensions [Core §5.4.7] ---

  describe "from_json/2 extensions [Core §5.4.7]" do
    test "unknown claims preserved in extensions" do
      json = %{
        "https://example.com/custom_claim" => %{"foo" => "bar"},
        "some_unknown_key" => "value"
      }

      assert {:ok, %LaunchClaims{extensions: extensions}} = LaunchClaims.from_json(json)
      assert extensions["https://example.com/custom_claim"] == %{"foo" => "bar"}
      assert extensions["some_unknown_key"] == "value"
    end

    test "extensions map is empty when no unknown claims" do
      json = %{"iss" => "https://platform.example.com"}

      assert {:ok, %LaunchClaims{extensions: extensions}} = LaunchClaims.from_json(json)
      assert extensions == %{}
    end

    test "extension parsers invoked per-call" do
      json = %{
        "https://example.com/custom" => %{"raw" => "data"}
      }

      parser = fn value -> {:ok, Map.put(value, "parsed", true)} end

      assert {:ok, %LaunchClaims{extensions: extensions}} =
               LaunchClaims.from_json(json, parsers: %{"https://example.com/custom" => parser})

      assert extensions["https://example.com/custom"] == %{"raw" => "data", "parsed" => true}
    end

    test "extension parser error halts pipeline" do
      json = %{
        "https://example.com/bad" => "value"
      }

      parser = fn _value -> {:error, RuntimeError.exception("parse failed")} end

      assert {:error, error} =
               LaunchClaims.from_json(json, parsers: %{"https://example.com/bad" => parser})

      assert Exception.message(error) =~ "parse failed"
    end

    test "per-call parsers override config parsers" do
      claim_key = "https://example.com/override-test"
      json = %{claim_key => "raw"}

      config_parser = fn value -> {:ok, {:from_config, value}} end
      call_parser = fn value -> {:ok, {:from_call, value}} end

      Application.put_env(:ltix, :launch_claim_parsers, %{claim_key => config_parser})

      try do
        assert {:ok, %LaunchClaims{extensions: extensions}} =
                 LaunchClaims.from_json(json, parsers: %{claim_key => call_parser})

        assert extensions[claim_key] == {:from_call, "raw"}
      after
        Application.delete_env(:ltix, :launch_claim_parsers)
      end
    end
  end

  # --- Full Parse ---

  describe "from_json/2 full parse" do
    test "parses a complete LTI launch" do
      json = JWTHelper.valid_lti_claims()

      assert {:ok, %LaunchClaims{} = claims} = LaunchClaims.from_json(json)
      assert claims.issuer == "https://platform.example.com"
      assert claims.subject == "user-12345"
      assert claims.message_type == "LtiResourceLinkRequest"
      assert claims.version == "1.3.0"
      assert claims.deployment_id == "deployment-001"
      assert %ResourceLink{id: "resource-link-001"} = claims.resource_link
      assert [%Role{name: :instructor}] = claims.roles
    end
  end
end
