defmodule Ltix.MembershipsService.MemberTest do
  use ExUnit.Case, async: true

  import MembershipsServiceFixtures

  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.MembershipsService.Member

  doctest Member

  setup do
    %{client: create_client()}
  end

  test "parses every field", %{client: client} do
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
      "roles" => ["http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"]
    }

    assert {{:ok, %{members: [member]}}, {:ok, [member]}} = list_and_stream(client, [json])

    assert member == %Member{
             user_id: "user-1",
             status: :inactive,
             name: "Jane Q. Public",
             picture: "https://platform.example.edu/jane.jpg",
             given_name: "Jane",
             family_name: "Public",
             middle_name: "Q",
             email: "jane@platform.example.edu",
             lis_person_source_id: "59254-6782-12ab",
             lti_1_1_legacy_user_id: "668321221-2879",
             roles: ["http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"]
           }
  end

  # [NRPS, Membership status](https://standards.1edtech.org/lti/specifications/services/names_roles/names-role-provisioning-spec#membership-status)
  test "reads a status in any case and with surrounding spaces", %{client: client} do
    statuses = ["Active", "Inactive", "Deleted", " active ", "ACTIVE", "inactive", "DELETED"]
    members = for status <- statuses, do: Map.put(member("user-1"), "status", status)

    assert {{:ok, %{members: members}}, {:ok, members}} = list_and_stream(client, members)

    assert Enum.map(members, & &1.status) ==
             [:active, :inactive, :deleted, :active, :active, :inactive, :deleted]
  end

  # [NRPS, Sharing of personal data](https://standards.1edtech.org/lti/specifications/services/names_roles/names-role-provisioning-spec#sharing-of-personal-data)
  test "reports a missing user_id or roles", %{client: client} do
    for {json, claim} <- [
          {%{"roles" => []}, "member.user_id"},
          {%{"user_id" => "user-1"}, "member.roles"},
          {%{}, "member.user_id and member.roles"}
        ] do
      assert {{:error, %MissingClaim{claim: ^claim}}, {:error, %MissingClaim{claim: ^claim}}} =
               list_and_stream(client, [json])
    end
  end

  test "keeps properties no plugin declares in unrecognized", %{client: client} do
    json =
      Map.merge(member("user-1"), %{
        "https://lms.example.com/student_number" => "s-42",
        "nickname" => "JJ"
      })

    assert {{:ok, %{members: [member]}}, {:ok, [member]}} = list_and_stream(client, [json])

    assert member.unrecognized == %{
             "https://lms.example.com/student_number" => "s-42",
             "nickname" => "JJ"
           }
  end
end
