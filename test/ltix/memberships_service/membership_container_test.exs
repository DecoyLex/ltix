defmodule Ltix.MembershipsService.MembershipContainerTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchClaims.Context
  alias Ltix.MembershipsService.Member
  alias Ltix.MembershipsService.MembershipContainer

  describe "from_json/1" do
    test "parses full membership container response" do
      json = %{
        "id" => "https://lms.example.com/sections/2923/memberships",
        "context" => %{
          "id" => "2923-abc",
          "label" => "CPS 435",
          "title" => "CPS 435 Learning Analytics"
        },
        "members" => [
          %{
            "user_id" => "user-1",
            "roles" => ["http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"]
          },
          %{
            "user_id" => "user-2",
            "roles" => ["http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"]
          }
        ]
      }

      assert {:ok, %MembershipContainer{} = container} = MembershipContainer.from_json(json)
      assert container.id == "https://lms.example.com/sections/2923/memberships"
      assert %Context{id: "2923-abc", label: "CPS 435"} = container.context
      assert length(container.members) == 2
      assert Enum.all?(container.members, &match?(%Member{}, &1))
    end

    test "returns error when context is missing [NRPS §2.2]" do
      json = %{
        "id" => "https://lms.example.com/memberships",
        "members" => []
      }

      assert {:error, error} = MembershipContainer.from_json(json)
      assert Exception.message(error) =~ "context"
    end

    test "returns error when context.id is missing [NRPS §2.2]" do
      json = %{
        "id" => "https://lms.example.com/memberships",
        "context" => %{"label" => "CPS 435"},
        "members" => []
      }

      assert {:error, error} = MembershipContainer.from_json(json)
      assert Exception.message(error) =~ "context.id"
    end

    test "parses empty members list" do
      json = %{
        "id" => "https://lms.example.com/memberships",
        "context" => %{"id" => "ctx-1"},
        "members" => []
      }

      assert {:ok, %MembershipContainer{members: []}} = MembershipContainer.from_json(json)
    end

    test "defaults members to empty list when absent" do
      json = %{
        "context" => %{"id" => "ctx-1"}
      }

      assert {:ok, %MembershipContainer{members: []}} = MembershipContainer.from_json(json)
    end

    test "returns error when a member fails to parse [NRPS §2.2]" do
      json = %{
        "context" => %{"id" => "ctx-1"},
        "members" => [
          %{"roles" => []}
        ]
      }

      assert {:error, error} = MembershipContainer.from_json(json)
      assert Exception.message(error) =~ "user_id"
    end

    test "id is optional" do
      json = %{
        "context" => %{"id" => "ctx-1"},
        "members" => []
      }

      assert {:ok, %MembershipContainer{id: nil}} = MembershipContainer.from_json(json)
    end
  end

  describe "Enumerable" do
    setup do
      container = %MembershipContainer{
        id: "https://lms.example.com/memberships",
        context: %Context{id: "ctx-1"},
        members: [
          %Member{user_id: "user-1", status: :active, roles: []},
          %Member{user_id: "user-2", status: :active, roles: []},
          %Member{user_id: "user-3", status: :inactive, roles: []}
        ]
      }

      %{container: container}
    end

    test "Enum.count/1 returns number of members", %{container: container} do
      assert Enum.count(container) == 3
    end

    test "Enum.member?/2 checks membership", %{container: container} do
      member = Enum.at(container, 0)
      assert Enum.member?(container, member)
    end

    test "Enum.map/2 iterates over members", %{container: container} do
      ids = Enum.map(container, & &1.user_id)
      assert ids == ["user-1", "user-2", "user-3"]
    end

    test "Enum.filter/2 filters members", %{container: container} do
      active = Enum.filter(container, &(&1.status == :active))
      assert length(active) == 2
    end

    test "Enum.reduce/3 reduces over members", %{container: container} do
      count = Enum.reduce(container, 0, fn _member, acc -> acc + 1 end)
      assert count == 3
    end

    test "works with Stream functions", %{container: container} do
      result =
        container
        |> Stream.filter(&(&1.status == :active))
        |> Enum.map(& &1.user_id)

      assert result == ["user-1", "user-2"]
    end

    test "empty container is enumerable" do
      container = %MembershipContainer{
        context: %Context{id: "ctx-1"},
        members: []
      }

      assert Enum.empty?(container)
      assert Enum.to_list(container) == []
    end
  end
end
