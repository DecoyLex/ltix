defmodule Ltix.MembershipsService.MemberTest do
  use ExUnit.Case, async: true

  alias Ltix.MembershipsService.Member

  doctest Member

  describe "from_json/1" do
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

    test "maps status strings to atoms [NRPS §2.3]" do
      for {string, atom} <- [{"Active", :active}, {"Inactive", :inactive}, {"Deleted", :deleted}] do
        json = %{"user_id" => "user-1", "roles" => [], "status" => string}
        assert {:ok, %Member{status: ^atom}} = Member.from_json(json)
      end
    end

    test "handles minor variations in status string formatting" do
      for {string, atom} <- [
            {" active ", :active},
            {"ACTIVE", :active},
            {"inactive", :inactive},
            {"DELETED", :deleted}
          ] do
        json = %{"user_id" => "user-1", "roles" => [], "status" => string}
        assert {:ok, %Member{status: ^atom}} = Member.from_json(json)
      end
    end

    test "keeps unrecognized fields in extensions" do
      json = %{
        "user_id" => "user-1",
        "roles" => [],
        "name" => "Jane",
        "lis_person_sourcedid" => "sis-1",
        "https://canvas.instructure.com/lti/sis_user_id" => "sis-1",
        "nickname" => "JJ"
      }

      assert {:ok, %Member{} = member} = Member.from_json(json)

      assert member.extensions == %{
               "https://canvas.instructure.com/lti/sis_user_id" => "sis-1",
               "nickname" => "JJ"
             }
    end
  end

  describe "to_map/1" do
    test "serializes a member built without extensions" do
      member = %Member{user_id: "user-1", roles: [], extensions: nil}
      assert Member.to_map(member) == %{"user_id" => "user-1", "roles" => []}
    end

    test "leaves out the message section" do
      member = %Member{user_id: "user-1", roles: [], message: [%Ltix.LaunchClaims{}]}

      refute Map.has_key?(Member.to_map(member), "message")
    end

    test "round-trips every field except message through from_json/1" do
      json = %{
        "user_id" => "user-1",
        "status" => "Inactive",
        "name" => "Jane Q. Public",
        "picture" => "https://platform.example.edu/jane.jpg",
        "given_name" => "Jane",
        "family_name" => "Public",
        "middle_name" => "Q",
        "email" => "jane@platform.example.edu",
        "lis_person_sourcedid" => "59254-6782-12ab",
        "lti11_legacy_user_id" => "668321221-2879",
        "roles" => [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor",
          "http://example.com/custom/role"
        ],
        "https://lms.example.com/student_number" => "s-42"
      }

      {:ok, member} = Member.from_json(json)
      assert Member.to_map(member) == json
    end
  end
end
