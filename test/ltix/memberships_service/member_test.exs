defmodule Ltix.MembershipsService.MemberTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchClaims
  alias Ltix.LaunchClaims.Role
  alias Ltix.MembershipsService.Member

  describe "from_json/1" do
    test "parses member with all fields populated" do
      json = %{
        "user_id" => "0ae836b9-7fc9-4060-006f-27b2066ac545",
        "status" => "Active",
        "name" => "Jane Q. Public",
        "picture" => "https://platform.example.edu/jane.jpg",
        "given_name" => "Jane",
        "family_name" => "Doe",
        "middle_name" => "Marie",
        "email" => "jane@platform.example.edu",
        "lis_person_sourcedid" => "59254-6782-12ab",
        "lti11_legacy_user_id" => "668321221-2879",
        "roles" => [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"
        ]
      }

      assert {:ok, %Member{} = member} = Member.from_json(json)
      assert member.user_id == "0ae836b9-7fc9-4060-006f-27b2066ac545"
      assert member.status == :active
      assert member.name == "Jane Q. Public"
      assert member.picture == "https://platform.example.edu/jane.jpg"
      assert member.given_name == "Jane"
      assert member.family_name == "Doe"
      assert member.middle_name == "Marie"
      assert member.email == "jane@platform.example.edu"
      assert member.lis_person_sourcedid == "59254-6782-12ab"
      assert member.lti11_legacy_user_id == "668321221-2879"
      assert [%Role{name: :instructor}] = member.roles
      assert member.unrecognized_roles == []
      assert member.message == nil
    end

    test "parses member with only required fields [NRPS §2.2]" do
      json = %{
        "user_id" => "user-1",
        "roles" => []
      }

      assert {:ok, %Member{} = member} = Member.from_json(json)
      assert member.user_id == "user-1"
      assert member.roles == []
      assert member.status == :active
      assert member.name == nil
      assert member.email == nil
    end

    test "returns error when user_id is missing [NRPS §2.2]" do
      json = %{"roles" => ["Instructor"]}
      assert {:error, error} = Member.from_json(json)
      assert Exception.message(error) =~ "user_id"
    end

    test "returns error when roles is missing [NRPS §2.2]" do
      json = %{"user_id" => "user-1"}
      assert {:error, error} = Member.from_json(json)
      assert Exception.message(error) =~ "roles"
    end

    test "returns error when both user_id and roles are missing [NRPS §2.2]" do
      assert {:error, error} = Member.from_json(%{})
      assert Exception.message(error) =~ "user_id"
    end

    test "defaults status to :active when not specified [NRPS §2.3]" do
      json = %{"user_id" => "user-1", "roles" => []}
      assert {:ok, %Member{status: :active}} = Member.from_json(json)
    end

    test "maps status strings to atoms [NRPS §2.3]" do
      for {string, atom} <- [{"Active", :active}, {"Inactive", :inactive}, {"Deleted", :deleted}] do
        json = %{"user_id" => "user-1", "roles" => [], "status" => string}
        assert {:ok, %Member{status: ^atom}} = Member.from_json(json)
      end
    end

    test "handles minor variations in status string formatting" do
      for string <- [" active ", "ACTIVE", "inactive", "DELETED"] do
        json = %{"user_id" => "user-1", "roles" => [], "status" => string}
        assert {:ok, %Member{status: status}} = Member.from_json(json)
        assert status in [:active, :inactive, :deleted]
      end
    end

    test "returns error for invalid status string [NRPS §2.3]" do
      json = %{"user_id" => "user-1", "roles" => [], "status" => "Unknown"}
      assert {:error, error} = Member.from_json(json)
      assert Exception.message(error) =~ "status"
    end

    test "parses roles into Role structs [NRPS §2.2]" do
      json = %{
        "user_id" => "user-1",
        "roles" => [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor",
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"
        ]
      }

      assert {:ok, %Member{} = member} = Member.from_json(json)
      assert length(member.roles) == 2
      assert Enum.any?(member.roles, &(&1.name == :instructor))
      assert Enum.any?(member.roles, &(&1.name == :learner))
    end

    test "preserves unrecognized role URIs" do
      json = %{
        "user_id" => "user-1",
        "roles" => [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor",
          "http://example.com/custom/role"
        ]
      }

      assert {:ok, %Member{} = member} = Member.from_json(json)
      assert length(member.roles) == 1
      assert [%Role{name: :instructor}] = member.roles
      assert member.unrecognized_roles == ["http://example.com/custom/role"]
    end

    test "PII fields default to nil [NRPS §2.2]" do
      json = %{"user_id" => "user-1", "roles" => []}
      assert {:ok, %Member{} = member} = Member.from_json(json)
      assert member.name == nil
      assert member.picture == nil
      assert member.given_name == nil
      assert member.family_name == nil
      assert member.middle_name == nil
      assert member.email == nil
      assert member.lis_person_sourcedid == nil
      assert member.lti11_legacy_user_id == nil
    end

    test "parses message section for resource link queries [NRPS §3.2]" do
      json = %{
        "user_id" => "user-1",
        "roles" => ["Instructor"],
        "message" => [
          %{
            "https://purl.imsglobal.org/spec/lti/claim/message_type" => "LtiResourceLinkRequest",
            "https://purl.imsglobal.org/spec/lti/claim/custom" => %{
              "country" => "Canada"
            }
          }
        ]
      }

      assert {:ok, %Member{} = member} = Member.from_json(json)
      assert [%LaunchClaims{} = msg] = member.message
      assert msg.message_type == "LtiResourceLinkRequest"
      assert msg.custom == %{"country" => "Canada"}
    end

    test "handles empty message array [NRPS §3.2]" do
      json = %{"user_id" => "user-1", "roles" => [], "message" => []}
      assert {:ok, %Member{message: []}} = Member.from_json(json)
    end

    test "message defaults to nil when absent [NRPS §3.2]" do
      json = %{"user_id" => "user-1", "roles" => []}
      assert {:ok, %Member{message: nil}} = Member.from_json(json)
    end
  end
end
