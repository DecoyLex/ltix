defmodule Ltix.MembershipsMemberPayloadTest do
  use ExUnit.Case, async: false

  import Ltix.Test.MembershipsServiceHelper

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.LaunchClaims.Context

  alias Ltix.MembershipsService
  alias Ltix.MembershipsService.Member
  alias Ltix.MembershipsService.MembershipContainer

  setup do
    %{client: create_client()}
  end

  for page <- [1, 2, 3] do
    for field <- ["user_id", "roles", "status", "message"] do
      test "invalid member #{field} types remain classified on page #{page}", %{client: client} do
        field = unquote(field)
        page = unquote(page)
        claim = "member.#{field}"

        for value <- [123, false, %{}, []] do
          if field not in ["roles", "message"] or value != [] do
            body =
              Map.put(container(page), "members", [
                member("valid"),
                Map.put(member("invalid"), field, value)
              ])

            stub_pages(page, body)

            assert {:error, %InvalidClaim{claim: ^claim}} = MembershipsService.get_members(client)
            assert {:ok, stream} = MembershipsService.stream_members(client)
            error = assert_raise InvalidClaim, fn -> Enum.to_list(stream) end
            assert error.claim == claim
          end
        end
      end
    end

    for field <-
          ~w(name given_name family_name middle_name email picture lis_person_sourcedid lti11_legacy_user_id) do
      test "malformed optional member #{field} is omitted on page #{page}", %{client: client} do
        field = unquote(field)
        page = unquote(page)

        for value <- [123, false, %{}, [], [%{}]] do
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
            Map.put(container(page), "members", [
              member("valid"),
              Map.put(profile, field, value)
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
              %Member{user_id: "user-1", roles: [], status: :active},
              %Member{user_id: "user-2", roles: [], status: :active}
            ]
            |> Enum.take(page - 1)
            |> Enum.concat([
              %Member{user_id: "valid", roles: [], status: :active},
              expected_profile
            ])

          stub_pages(page, body)

          assert {:ok, %MembershipContainer{members: ^expected}} =
                   MembershipsService.get_members(client)

          assert {:ok, stream} = MembershipsService.stream_members(client)
          assert Enum.to_list(stream) == expected
        end
      end
    end

    for field <- ~w(label title type) do
      behavior =
        if page == 1, do: "is omitted on the first page", else: "is accepted on page #{page}"

      test "malformed optional context #{field} #{behavior}", %{client: client} do
        field = unquote(field)
        page = unquote(page)

        for value <- [123, false, %{}, [123]] do
          context = Map.put(%{"id" => "course"}, field, value)
          stub_pages(page, Map.put(container(page), "context", context))

          assert {:ok, %MembershipContainer{context: parsed, members: members}} =
                   MembershipsService.get_members(client)

          if page == 1 do
            assert Map.fetch!(parsed, String.to_existing_atom(field)) == nil
          end

          assert parsed == %Context{id: "course"}

          expected =
            Enum.take(
              [
                %Member{user_id: "user-1", roles: [], status: :active},
                %Member{user_id: "user-2", roles: [], status: :active},
                %Member{user_id: "user-3", roles: [], status: :active}
              ],
              page
            )

          assert members == expected
          assert {:ok, stream} = MembershipsService.stream_members(client)
          assert Enum.to_list(stream) == expected
        end
      end
    end

    test "role array entries are strings on page #{page}", %{client: client} do
      page = unquote(page)

      for value <- [123, false, nil, [], %{}] do
        body =
          Map.put(container(page), "members", [
            Map.put(member("invalid"), "roles", ["Instructor", value])
          ])

        stub_pages(page, body)

        assert {:error, %InvalidClaim{claim: "member.roles"}} =
                 MembershipsService.get_members(client)

        assert {:ok, stream} = MembershipsService.stream_members(client)
        assert_raise InvalidClaim, fn -> Enum.to_list(stream) end
      end
    end

    test "message array entries are objects on page #{page}", %{client: client} do
      page = unquote(page)

      for value <- [123, false, nil, [], "invalid"] do
        body =
          Map.put(container(page), "members", [
            Map.put(member("invalid"), "message", [%{}, value])
          ])

        stub_pages(page, body)

        assert {:error, %InvalidClaim{claim: "member.message"}} =
                 MembershipsService.get_members(client)

        assert {:ok, stream} = MembershipsService.stream_members(client)
        assert_raise InvalidClaim, fn -> Enum.to_list(stream) end
      end
    end

    test "required member fields and context identifiers reject null values on page #{page}", %{
      client: client
    } do
      page = unquote(page)

      for field <- ["user_id", "roles"] do
        body = Map.put(container(page), "members", [Map.put(member("invalid"), field, nil)])
        stub_pages(page, body)
        claim = "member.#{field}"
        assert {:error, %InvalidClaim{claim: ^claim}} = MembershipsService.get_members(client)
        assert {:ok, stream} = MembershipsService.stream_members(client)
        assert_raise InvalidClaim, fn -> Enum.to_list(stream) end
      end

      stub_pages(page, Map.put(container(page), "context", %{"id" => nil}))

      assert {:error, %InvalidClaim{claim: "context.id", value: nil, spec_ref: "Core §5.4.1"}} =
               MembershipsService.get_members(client)

      assert {:ok, stream} = MembershipsService.stream_members(client)
      error = assert_raise InvalidClaim, fn -> Enum.to_list(stream) end

      assert %InvalidClaim{claim: "context.id", value: nil, spec_ref: "Core §5.4.1"} = error
    end

    test "container context requires an object on page #{page}", %{client: client} do
      page = unquote(page)

      for context <- [123, false, [], "invalid"] do
        stub_pages(page, Map.put(container(page), "context", context))

        assert {:error, %InvalidClaim{claim: "context", value: ^context, spec_ref: "Core §5.4.1"}} =
                 MembershipsService.get_members(client)

        assert {:ok, stream} = MembershipsService.stream_members(client)
        error = assert_raise InvalidClaim, fn -> Enum.to_list(stream) end

        assert %InvalidClaim{claim: "context", value: ^context, spec_ref: "Core §5.4.1"} = error
      end
    end

    test "missing context identifiers propagate parse errors on page #{page}", %{client: client} do
      page = unquote(page)

      for body <- [
            Map.delete(container(page), "context"),
            Map.put(container(page), "context", nil),
            Map.put(container(page), "context", %{})
          ] do
        stub_pages(page, body)

        assert {:error, %MissingClaim{claim: "context.id"}} =
                 MembershipsService.get_members(client)

        assert {:ok, stream} = MembershipsService.stream_members(client)
        error = assert_raise MissingClaim, fn -> Enum.to_list(stream) end
        assert %MissingClaim{claim: "context.id"} = error
      end
    end

    test "context identifiers remain validated on page #{page}", %{client: client} do
      page = unquote(page)

      for value <- [123, false, %{}, [123]] do
        stub_pages(page, Map.put(container(page), "context", %{"id" => value}))

        assert {:error,
                %InvalidClaim{claim: "context.id", value: ^value, spec_ref: "Core §5.4.1"}} =
                 MembershipsService.get_members(client)

        assert {:ok, stream} = MembershipsService.stream_members(client)
        error = assert_raise InvalidClaim, fn -> Enum.to_list(stream) end

        assert %InvalidClaim{claim: "context.id", value: ^value, spec_ref: "Core §5.4.1"} = error
      end
    end

    test "container identifier types remain classified on page #{page}", %{client: client} do
      page = unquote(page)

      for value <- [123, false, %{}, []] do
        stub_pages(page, Map.put(container(page), "id", value))

        assert {:error, %InvalidClaim{claim: "membership.id"}} =
                 MembershipsService.get_members(client)

        assert {:ok, stream} = MembershipsService.stream_members(client)
        assert_raise InvalidClaim, fn -> Enum.to_list(stream) end
      end
    end
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
            }} = MembershipsService.get_members(client)

    assert {:ok, stream} = MembershipsService.stream_members(client)

    assert [%Member{user_id: "user-1", status: :active}, %Member{user_id: "user-2", message: []}] =
             Enum.to_list(stream)
  end

  test "unknown status strings retain the existing classified error", %{client: client} do
    stub_pages(
      1,
      Map.put(container(1), "members", [Map.put(member("invalid"), "status", "Unknown")])
    )

    assert {:error, %InvalidClaim{claim: "member.status", spec_ref: "NRPS §2.3"}} =
             MembershipsService.get_members(client)
  end
end
