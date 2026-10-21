defmodule Ltix.ServiceCollectionFailuresTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.CollectionTooLarge
  alias Ltix.Errors.Invalid.MalformedResponse
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.Errors.Security.AccessDenied
  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.GradeService
  alias Ltix.GradeService.Endpoint, as: GradeServiceEndpoint
  alias Ltix.GradeService.LineItem
  alias Ltix.GradeService.Result
  alias Ltix.MembershipsService
  alias Ltix.MembershipsService.Endpoint, as: MembershipsServiceEndpoint
  alias Ltix.MembershipsService.Member
  alias Ltix.MembershipsService.MembershipContainer
  alias Ltix.OAuth.AccessToken
  alias Ltix.OAuth.Client

  setup do
    %{registration: Ltix.Test.setup_platform!().registration}
  end

  for collection <- [:line_items, :members] do
    test "#{collection} returns a tuple for HTTP failure", context do
      collection = unquote(collection)
      failed_page = 2
      next_page = failed_page + 1
      client = build_client(context.registration)

      stub_pages(collection, failed_page, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("link", "<#{page_url(collection, next_page)}>; rel=\"next\"")
        |> Plug.Conn.send_resp(500, "unavailable")
      end)

      assert {:error, %TransportError{status: 500, body: "unavailable", url: url}} =
               fetch_collection(collection, client)

      assert url == page_url(collection, failed_page)
      assert_receive {:requested_page, 1}
      assert_receive {:requested_page, ^failed_page}
      refute_received {:requested_page, ^next_page}
    end
  end

  test "line_items returns TransportError for a connection failure", context do
    collection = :line_items
    failed_page = 2
    client = build_client(context.registration)
    stub_pages(collection, failed_page, &Req.Test.transport_error(&1, :timeout))

    assert {:error, %TransportError{status: nil, url: url}} =
             fetch_collection(collection, client)

    assert url == page_url(collection, failed_page)

    assert_receive {:requested_page, ^failed_page}
  end

  test "members returns AccessDenied for HTTP 401", context do
    collection = :members
    failed_page = 1
    status = 401
    client = build_client(context.registration)

    stub_pages(collection, failed_page, &Plug.Conn.send_resp(&1, status, "denied"))

    assert {:error, %AccessDenied{status: ^status, body: "denied", url: url}} =
             fetch_collection(collection, client)

    assert url == page_url(collection, failed_page)
  end

  for collection <- [:line_items, :members] do
    test "lazy #{collection} raise only when HTTP failure page is consumed", context do
      collection = unquote(collection)
      failed_page = 2
      client = build_client(context.registration)

      stub_pages(collection, failed_page, fn conn ->
        Plug.Conn.send_resp(conn, 500, "unavailable")
      end)

      assert {:ok, stream} = stream_collection(collection, client)
      assert_receive {:requested_page, 1}
      refute_received {:requested_page, ^failed_page}
      assert [first] = Enum.take(stream, 1)
      assert collection_identifier(collection, first) == "user-1"
      refute_received {:requested_page, ^failed_page}
      assert_raise TransportError, fn -> Enum.to_list(stream) end
      assert_receive {:requested_page, ^failed_page}
    end
  end

  test "roster limit stops traversal before an unnecessary failing page", context do
    client = build_client(context.registration)
    stub_pages(:members, 3, fn conn -> Plug.Conn.send_resp(conn, 500, "unavailable") end)

    assert {:error, %CollectionTooLarge{count: 2, max: 1}} =
             MembershipsService.list_members(client, max_members: 1)

    assert_receive {:requested_page, 2}
    refute_received {:requested_page, 3}
  end

  test "line_items rejects malformed successful containers", context do
    collection = :line_items
    page = 2
    client = build_client(context.registration)

    body = %{}
    stub_pages(collection, page, &Req.Test.json(&1, body))

    assert {:error, %MalformedResponse{service: GradeService, reason: "expected JSON array"}} =
             fetch_collection(collection, client)
  end

  test "lazy line_items reject malformed containers when page is consumed", context do
    collection = :line_items
    page = 2
    client = build_client(context.registration)

    for body <- [%{}, [nil]] do
      stub_pages(collection, page, &Req.Test.json(&1, body))
      assert {:ok, stream} = stream_collection(collection, client)
      assert_raise MalformedResponse, fn -> Enum.to_list(stream) end
    end
  end

  test "line_items rejects nonobject entries without a partial list", context do
    collection = :line_items
    page = 2
    client = build_client(context.registration)

    entry = nil
    body = [hd(page_body(collection, page)), entry]
    stub_pages(collection, page, &Req.Test.json(&1, body))

    assert {:error,
            %MalformedResponse{
              service: GradeService,
              reason: "expected JSON object in collection"
            }} = fetch_collection(collection, client)
  end

  test "members reject nonobject containers", context do
    page = 2
    client = build_client(context.registration)

    body = []
    stub_pages(:members, page, &Req.Test.json(&1, body))

    assert {:error,
            %MalformedResponse{service: MembershipsService, reason: "expected JSON object"}} =
             MembershipsService.list_members(client)
  end

  test "members require an array in the members property", context do
    page = 2
    client = build_client(context.registration)
    body = Map.delete(page_body(:members, page), "members")

    stub_pages(:members, page, &Req.Test.json(&1, body))

    assert {:error,
            %MalformedResponse{
              service: MembershipsService,
              reason: "expected members to be a JSON array"
            }} = MembershipsService.list_members(client)
  end

  test "lazy members reject malformed containers when page is consumed", context do
    page = 2
    client = build_client(context.registration)

    for body <- [[], false, Map.put(page_body(:members, page), "members", %{}), %{}] do
      stub_pages(:members, page, &Req.Test.json(&1, body))
      assert {:ok, stream} = MembershipsService.stream_members(client)
      assert_raise MalformedResponse, fn -> Enum.to_list(stream) end
    end
  end

  test "member parsing errors remain classified without a partial roster", context do
    page = 2
    client = build_client(context.registration)

    body =
      Map.put(page_body(:members, page), "members", [
        %{"user_id" => "valid", "roles" => []},
        nil
      ])

    stub_pages(:members, page, &Req.Test.json(&1, body))

    assert {:error, %MissingClaim{claim: "member.user_id and member.roles"}} =
             MembershipsService.list_members(client)

    assert {:ok, stream} = MembershipsService.stream_members(client)
    assert_raise MissingClaim, fn -> Enum.to_list(stream) end
  end

  test "collections accept empty collections and follow empty pages", context do
    client = build_client(context.registration)

    for collection <- [:line_items, :results, :members] do
      empty =
        if collection == :members, do: Map.put(page_body(:members, 1), "members", []), else: []

      stub_pages(collection, 1, &Req.Test.json(&1, empty))

      assert {:ok, values} = fetch_collection(collection, client)
      assert Enum.to_list(values) == []

      Req.Test.stub(
        if(collection == :members, do: MembershipsService, else: GradeService),
        fn conn ->
          if conn.query_string == "page=2" do
            Req.Test.json(conn, page_body(collection, 2))
          else
            conn
            |> Plug.Conn.put_resp_header("link", "<#{page_url(collection, 2)}>; rel=\"next\"")
            |> Req.Test.json(empty)
          end
        end
      )

      assert {:ok, values} = fetch_collection(collection, client)
      assert Enum.map(values, &collection_identifier(collection, &1)) == ["user-2"]
    end
  end

  test "grade collections keep unrecognized properties", context do
    client = build_client(context.registration)
    unrecognized = %{"vendor" => %{"flag" => true}}

    stub_pages(
      :line_items,
      1,
      &Req.Test.json(&1, [%{"id" => "item-1", "vendor" => unrecognized["vendor"]}])
    )

    assert {:ok, [%LineItem{id: "item-1", unrecognized: ^unrecognized}]} =
             GradeService.list_line_items(client)

    stub_pages(
      :results,
      1,
      &Req.Test.json(&1, [%{"userId" => "user-1", "vendor" => unrecognized["vendor"]}])
    )

    assert {:ok, [%Result{user_id: "user-1", unrecognized: ^unrecognized}]} =
             GradeService.list_results(client)
  end

  test "members retain parsed messages and accept unrecognized properties", context do
    client = build_client(context.registration)

    body = %{
      "context" => %{"id" => "course-1", "unknown" => "accepted"},
      "unknown" => true,
      "members" => [
        %{
          "user_id" => "user-1",
          "roles" => ["Instructor", "https://vendor.example.com/role"],
          "unknown" => true,
          "message" => [
            %{
              "https://purl.imsglobal.org/spec/lti/claim/message_type" =>
                "LtiResourceLinkRequest",
              "https://purl.imsglobal.org/spec/lti/claim/custom" => %{"country" => "Canada"},
              "https://vendor.example.com/claim" => "extension"
            }
          ]
        }
      ]
    }

    stub_pages(:members, 1, &Req.Test.json(&1, body))

    assert {:ok, %MembershipContainer{context: %{id: "course-1"}, members: [member]}} =
             MembershipsService.list_members(client)

    assert %Member{
             user_id: "user-1",
             status: :active,
             roles: ["Instructor", "https://vendor.example.com/role"],
             message: [
               %{message_type: "LtiResourceLinkRequest", custom: %{"country" => "Canada"}} =
                 message
             ]
           } = member

    assert Map.reject(message, fn {_claim, value} -> value == nil end) == %{
             message_type: "LtiResourceLinkRequest",
             custom: %{"country" => "Canada"},
             roles: []
           }

    assert {:ok, stream} = MembershipsService.stream_members(client)

    assert [
             %Member{
               user_id: "user-1",
               status: :active,
               roles: ["Instructor", "https://vendor.example.com/role"],
               message: [%{custom: %{"country" => "Canada"}}]
             }
           ] = Enum.to_list(stream)
  end

  test "a malformed page stops eager traversal before any later request", context do
    client = build_client(context.registration)

    Req.Test.stub(GradeService, fn conn ->
      case conn.query_string do
        "" ->
          conn
          |> Plug.Conn.put_resp_header("link", "<#{page_url(:results, 2)}>; rel=\"next\"")
          |> Req.Test.json(page_body(:results, 1))

        "page=2" ->
          conn
          |> Plug.Conn.put_resp_header("link", "<#{page_url(:results, 3)}>; rel=\"next\"")
          |> Req.Test.json(%{})

        _ ->
          flunk("fetched another page after a malformed collection")
      end
    end)

    assert {:error, %MalformedResponse{}} = GradeService.list_results(client)
  end

  test "line_items returns rejected next links as error tuples", context do
    collection = :line_items
    page = 2
    client = build_client(context.registration)

    for invalid_url <- ["http://platform.example.com/next", "https://evil.example.com/next"] do
      stub_pages(collection, page, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("link", "<#{invalid_url}>; rel=\"next\"")
        |> Req.Test.json(page_body(collection, page))
      end)

      assert {:error, %TransportError{}} = fetch_collection(collection, client)
    end
  end

  defp request_options, do: [plug: {Req.Test, __MODULE__}, retry: false]

  defp build_client(registration) do
    scopes = [
      "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem.readonly",
      "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly",
      "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"
    ]

    %Client{
      token: %AccessToken{
        access_token: "collection-token",
        token_type: "bearer",
        expires_at: DateTime.add(DateTime.utc_now(), 3600),
        granted_scopes: MapSet.new(scopes)
      },
      registration: registration,
      req_options: request_options(),
      endpoints: %{
        GradeService => %GradeServiceEndpoint{
          line_items: page_url(:line_items, 1),
          line_item: "https://platform.example.com/lineitems/1",
          scopes: scopes
        },
        MembershipsService => MembershipsServiceEndpoint.new!(page_url(:members, 1))
      }
    }
  end

  defp stub_pages(collection, last_page, last_response) do
    owner = self()

    response = fn conn ->
      page = String.to_integer(Plug.Conn.fetch_query_params(conn).query_params["page"] || "1")
      send(owner, {:requested_page, page})

      if page == last_page do
        last_response.(conn)
      else
        conn
        |> Plug.Conn.put_resp_header("link", "<#{page_url(collection, page + 1)}>; rel=\"next\"")
        |> Req.Test.json(page_body(collection, page))
      end
    end

    for name <- [GradeService, MembershipsService] do
      Req.Test.stub(name, response)
    end
  end

  defp page_url(collection, page) do
    path =
      case collection do
        :line_items -> "lineitems"
        :results -> "lineitems/1/results"
        :members -> "memberships"
      end

    suffix = if page == 1, do: "", else: "?page=#{page}"
    "https://platform.example.com/#{path}#{suffix}"
  end

  defp page_body(:line_items, page), do: [%{"id" => "user-#{page}"}]
  defp page_body(:results, page), do: [%{"userId" => "user-#{page}"}]

  defp page_body(:members, page) do
    %{
      "id" => page_url(:members, 1),
      "context" => %{"id" => "course-1"},
      "members" => [%{"user_id" => "user-#{page}", "roles" => []}]
    }
  end

  defp fetch_collection(:line_items, client), do: GradeService.list_line_items(client)
  defp fetch_collection(:results, client), do: GradeService.list_results(client)
  defp fetch_collection(:members, client), do: MembershipsService.list_members(client)

  defp stream_collection(:line_items, client), do: GradeService.stream_line_items(client)
  defp stream_collection(:members, client), do: MembershipsService.stream_members(client)

  defp collection_identifier(:line_items, item), do: item.id
  defp collection_identifier(_collection, item), do: item.user_id
end
