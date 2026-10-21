defmodule Ltix.MembershipsMemberPayloadTest do
  use ExUnit.Case, async: false

  import Ltix.Test.MembershipsServiceHelper

  alias Ltix.Claims.Context
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim

  alias Ltix.MembershipsService
  alias Ltix.MembershipsService.Member
  alias Ltix.MembershipsService.MembershipContainer

  setup do
    %{client: create_client()}
  end

  for field <- ["user_id", "roles", "status", "message"] do
    test "invalid member #{field} types remain classified", %{client: client} do
      field = unquote(field)
      claim = "member.#{field}"

      body =
        Map.put(container(1), "members", [
          member("valid"),
          Map.put(member("invalid"), field, 123)
        ])

      stub_pages(1, body)

      assert {:error, %InvalidClaim{claim: ^claim}} =
               MembershipsService.list_members(client)

      assert {:ok, stream} = MembershipsService.stream_members(client)
      error = assert_raise InvalidClaim, fn -> Enum.to_list(stream) end
      assert error.claim == claim
    end
  end

  for field <-
        ~w(name given_name family_name middle_name email picture lis_person_sourcedid lti11_legacy_user_id) do
    test "malformed optional member #{field} is omitted", %{client: client} do
      field = unquote(field)

      profile = %{
        "user_id" => "profile",
        "roles" => [],
        "name" => "Profile User",
        "given_name" => "Profile",
        "family_name" => "User",
        "middle_name" => "A",
        "email" => "profile@example.com",
        "picture" => "https://example.com/profile.png",
        "lis_person_sourcedid" => "profile-source",
        "lti11_legacy_user_id" => "profile-legacy"
      }

      body =
        Map.put(container(1), "members", [
          member("valid"),
          Map.put(profile, field, 123)
        ])

      expected_profile =
        Map.put(
          %Member{
            user_id: "profile",
            roles: [],
            status: :active,
            name: "Profile User",
            given_name: "Profile",
            family_name: "User",
            middle_name: "A",
            email: "profile@example.com",
            picture: "https://example.com/profile.png",
            lis_person_source_id: "profile-source",
            lti_1_1_legacy_user_id: "profile-legacy"
          },
          Map.get_lazy(
            %{
              "lis_person_sourcedid" => :lis_person_source_id,
              "lti11_legacy_user_id" => :lti_1_1_legacy_user_id
            },
            field,
            fn -> String.to_existing_atom(field) end
          ),
          nil
        )

      expected =
        [
          %Member{user_id: "valid", roles: [], status: :active},
          expected_profile
        ]

      stub_pages(1, body)

      assert {:ok, %MembershipContainer{members: ^expected}} =
               MembershipsService.list_members(client)

      assert {:ok, stream} = MembershipsService.stream_members(client)
      assert Enum.to_list(stream) == expected
    end
  end

  test "role array entries are strings", %{client: client} do
    body =
      Map.put(container(1), "members", [
        Map.put(member("invalid"), "roles", ["Instructor", 123])
      ])

    stub_pages(1, body)

    assert {:error, %InvalidClaim{claim: "member.roles.1", value: 123}} =
             MembershipsService.list_members(client)

    assert {:ok, stream} = MembershipsService.stream_members(client)
    assert_raise InvalidClaim, fn -> Enum.to_list(stream) end
  end

  test "message array entries are objects", %{client: client} do
    body =
      Map.put(container(1), "members", [
        Map.put(member("invalid"), "message", [%{}, 123])
      ])

    stub_pages(1, body)

    assert {:error, %InvalidClaim{claim: "member.message"}} =
             MembershipsService.list_members(client)

    assert {:ok, stream} = MembershipsService.stream_members(client)
    assert_raise InvalidClaim, fn -> Enum.to_list(stream) end
  end

  test "required member fields and context identifiers reject null values", %{
    client: client
  } do
    for field <- ["user_id", "roles"] do
      body = Map.put(container(1), "members", [Map.put(member("invalid"), field, nil)])
      stub_pages(1, body)
      claim = "member.#{field}"
      assert {:error, %InvalidClaim{claim: ^claim}} = MembershipsService.list_members(client)
      assert {:ok, stream} = MembershipsService.stream_members(client)
      assert_raise InvalidClaim, fn -> Enum.to_list(stream) end
    end

    stub_pages(1, Map.put(container(1), "context", %{"id" => nil}))

    assert {:error, %InvalidClaim{claim: "context.id", value: nil}} =
             MembershipsService.list_members(client)

    assert {:ok, stream} = MembershipsService.stream_members(client)
    error = assert_raise InvalidClaim, fn -> Enum.to_list(stream) end

    assert %InvalidClaim{claim: "context.id", value: nil} = error
  end

  for page <- [1, 2] do
    test "container context requires an object on page #{page}", %{client: client} do
      page = unquote(page)

      stub_pages(page, Map.put(container(page), "context", 123))

      assert {:error, %InvalidClaim{claim: "context", value: 123}} =
               MembershipsService.list_members(client)

      assert {:ok, stream} = MembershipsService.stream_members(client)
      error = assert_raise InvalidClaim, fn -> Enum.to_list(stream) end

      assert %InvalidClaim{claim: "context", value: 123} = error
    end
  end

  test "missing context identifiers propagate parse errors", %{client: client} do
    for body <- [
          Map.delete(container(1), "context"),
          Map.put(container(1), "context", nil),
          Map.put(container(1), "context", %{})
        ] do
      stub_pages(1, body)

      assert {:error, %MissingClaim{claim: "context.id"}} =
               MembershipsService.list_members(client)

      assert {:ok, stream} = MembershipsService.stream_members(client)
      error = assert_raise MissingClaim, fn -> Enum.to_list(stream) end
      assert %MissingClaim{claim: "context.id"} = error
    end
  end

  test "context identifiers remain validated", %{client: client} do
    stub_pages(1, Map.put(container(1), "context", %{"id" => 123}))

    assert {:error, %InvalidClaim{claim: "context.id", value: 123}} =
             MembershipsService.list_members(client)

    assert {:ok, stream} = MembershipsService.stream_members(client)
    error = assert_raise InvalidClaim, fn -> Enum.to_list(stream) end

    assert %InvalidClaim{claim: "context.id", value: 123} = error
  end

  test "container identifier types remain classified", %{client: client} do
    stub_pages(1, Map.put(container(1), "id", 123))

    assert {:error, %InvalidClaim{claim: "membership.id"}} =
             MembershipsService.list_members(client)

    assert {:ok, stream} = MembershipsService.stream_members(client)
    assert_raise InvalidClaim, fn -> Enum.to_list(stream) end
  end

  test "optional null fields, empty arrays and unknown properties remain accepted", %{
    client: client
  } do
    optional =
      Map.new(
        ~w(status message name given_name family_name middle_name email picture lis_person_sourcedid lti11_legacy_user_id),
        &{&1, nil}
      )

    first = Map.merge(member("user-1"), optional)
    second = Map.put(member("user-2"), "message", [])

    body = %{
      "id" => nil,
      "context" => %{
        "id" => "course",
        "label" => nil,
        "title" => nil,
        "type" => nil,
        "unknown" => [%{}]
      },
      "members" => [Map.put(first, "unknown", %{"arbitrary" => [123]}), second]
    }

    stub_pages(1, body)

    assert {:ok,
            %MembershipContainer{
              id: nil,
              context: %Context{id: "course", label: nil, title: nil, type: nil},
              members: [
                %Member{user_id: "user-1", roles: [], status: :active, message: nil},
                %Member{user_id: "user-2", roles: [], message: []}
              ]
            }} = MembershipsService.list_members(client)

    assert {:ok, stream} = MembershipsService.stream_members(client)

    assert [%Member{user_id: "user-1", status: :active}, %Member{user_id: "user-2", message: []}] =
             Enum.to_list(stream)
  end

  test "unknown status strings retain the existing classified error", %{client: client} do
    stub_pages(
      1,
      Map.put(container(1), "members", [Map.put(member("invalid"), "status", "Unknown")])
    )

    assert {:error, %InvalidClaim{claim: "member.status"}} =
             MembershipsService.list_members(client)
  end
end
