defmodule Ltix.MembershipsService.MembershipContainerTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchClaims.Context
  alias Ltix.MembershipsService.Member
  alias Ltix.MembershipsService.MembershipContainer

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
      refute Enum.member?(container, %Member{user_id: "user-4", status: :active, roles: []})
    end

    test "Enum.map/2 iterates over members", %{container: container} do
      ids = Enum.map(container, & &1.user_id)
      assert ids == ["user-1", "user-2", "user-3"]
    end
  end
end
