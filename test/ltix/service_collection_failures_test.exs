defmodule Ltix.ServiceCollectionFailuresTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.CollectionTooLarge
  alias Ltix.Errors.Invalid.MalformedResponse
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.Errors.Security.AccessDenied
  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.GradeService
  alias Ltix.GradeService.LineItem
  alias Ltix.GradeService.Result
  alias Ltix.LaunchClaims.AGSEndpoint
  alias Ltix.LaunchClaims.MembershipsEndpoint
  alias Ltix.MembershipsService
  alias Ltix.MembershipsService.Member
  alias Ltix.MembershipsService.MembershipContainer
  alias Ltix.OAuth.Client

  setup do
    %{registration: Ltix.Test.setup_platform!().registration}
  end

  for collection <- [:line_items, :results, :members], page <- [2, 3] do
    test "#{collection} returns a tuple for HTTP failure on page #{page}", context do
      collection = unquote(collection)
      failed_page = unquote(page)
      client = build_client(context.registration)

      stub_pages(collection, failed_page, fn conn ->
        Plug.Conn.send_resp(conn, 500, "unavailable")
      end)

      assert {:error, %TransportError{status: 500, body: "unavailable", url: url}} =
               fetch_collection(collection, client)

      assert url == page_url(collection, failed_page)
      assert_receive {:requested_page, 1}
      assert_receive {:requested_page, ^failed_page}
      refute_received {:requested_page, 4}
    end

    test "#{collection} returns TransportError for a connection failure on page #{page}",
         context do
      collection = unquote(collection)
      failed_page = unquote(page)
      client = build_client(context.registration)
      stub_pages(collection, failed_page, &Req.Test.transport_error(&1, :timeout))

      assert {:error, %TransportError{status: nil, url: url}} =
               fetch_collection(collection, client)

      assert url == page_url(collection, failed_page)

      assert_receive {:requested_page, ^failed_page}
      refute_received {:requested_page, 4}
    end
  end

  for collection <- [:line_items, :results, :members], page <- [1, 2], status <- [401, 403] do
    test "#{collection} returns AccessDenied for HTTP #{status} on page #{page}", context do
      collection = unquote(collection)
      failed_page = unquote(page)
      status = unquote(status)
      client = build_client(context.registration)

      stub_pages(collection, failed_page, &Plug.Conn.send_resp(&1, status, "denied"))

      assert {:error, %AccessDenied{status: ^status, body: "denied", url: url}} =
               fetch_collection(collection, client)

      assert url == page_url(collection, failed_page)
    end
  end

  for collection <- [:line_items, :results, :members], page <- [2, 3] do
    test "lazy #{collection} raise only when HTTP failure page #{page} is consumed", context do
      collection = unquote(collection)
      failed_page = unquote(page)
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

    test "lazy #{collection} raise TransportError for a connection failure on page #{page}",
         context do
      collection = unquote(collection)
      failed_page = unquote(page)
      client = build_client(context.registration)
      stub_pages(collection, failed_page, &Req.Test.transport_error(&1, :timeout))

      assert {:ok, stream} = stream_collection(collection, client)
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

  for collection <- [:line_items, :results], page <- [1, 2, 3] do
    test "#{collection} rejects malformed successful containers on page #{page}", context do
      collection = unquote(collection)
      page = unquote(page)
      client = build_client(context.registration)

      for body <- [%{}, %{"unexpected" => []}, nil, false, 42, "invalid"] do
        stub_pages(collection, page, &Req.Test.json(&1, body))

        assert {:error, %MalformedResponse{service: GradeService, reason: "expected JSON array"}} =
                 fetch_collection(collection, client)
      end
    end

    test "lazy #{collection} reject malformed containers when page #{page} is consumed",
         context do
      collection = unquote(collection)
      page = unquote(page)
      client = build_client(context.registration)

      for body <- [%{}, nil, 42, [nil]] do
        stub_pages(collection, page, &Req.Test.json(&1, body))
        assert {:ok, stream} = stream_collection(collection, client)
        assert_raise MalformedResponse, fn -> Enum.to_list(stream) end
      end
    end

    test "#{collection} rejects nonobject entries without a partial list on page #{page}",
         context do
      collection = unquote(collection)
      page = unquote(page)
      client = build_client(context.registration)

      for entry <- [nil, false, 42, "invalid", []] do
        body = [hd(page_body(collection, page)), entry]
        stub_pages(collection, page, &Req.Test.json(&1, body))

        assert {:error,
                %MalformedResponse{
                  service: GradeService,
                  reason: "expected JSON object in collection"
                }} = fetch_collection(collection, client)
      end
    end
  end

  for page <- [1, 2, 3] do
    test "members reject nonobject containers on page #{page}", context do
      page = unquote(page)
      client = build_client(context.registration)

      for body <- [[], [%{"user_id" => "user-1", "roles" => []}], nil, false, 42, "invalid"] do
        stub_pages(:members, page, &Req.Test.json(&1, body))

        assert {:error,
                %MalformedResponse{service: MembershipsService, reason: "expected JSON object"}} =
                 MembershipsService.list_members(client)
      end
    end

    test "members require an array rather than an absent or malformed members property on page #{page}",
         context do
      page = unquote(page)
      client = build_client(context.registration)
      container = Map.delete(page_body(:members, page), "members")

      bodies = [
        container | Enum.map([nil, false, 42, "invalid", %{}], &Map.put(container, "members", &1))
      ]

      for body <- bodies do
        stub_pages(:members, page, &Req.Test.json(&1, body))

        assert {:error,
                %MalformedResponse{
                  service: MembershipsService,
                  reason: "expected members to be a JSON array"
                }} = MembershipsService.list_members(client)
      end
    end

    test "lazy members reject malformed containers when page #{page} is consumed", context do
      page = unquote(page)
      client = build_client(context.registration)

      for body <- [[], false, Map.put(page_body(:members, page), "members", %{}), %{}] do
        stub_pages(:members, page, &Req.Test.json(&1, body))
        assert {:ok, stream} = MembershipsService.stream_members(client)
        assert_raise MalformedResponse, fn -> Enum.to_list(stream) end
      end
    end

    test "member parsing errors remain classified without a partial roster on page #{page}",
         context do
      page = unquote(page)
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

  test "grade collections retain unknown properties", context do
    client = build_client(context.registration)
    extension = %{"vendor" => %{"flag" => true}}

    stub_pages(
      :line_items,
      1,
      &Req.Test.json(&1, [%{"id" => "item-1", "vendor" => extension["vendor"]}])
    )

    assert {:ok, [%LineItem{id: "item-1", extensions: ^extension}]} =
             GradeService.list_line_items(client)

    stub_pages(
      :results,
      1,
      &Req.Test.json(&1, [%{"userId" => "user-1", "vendor" => extension["vendor"]}])
    )

    assert {:ok, [%Result{user_id: "user-1", extensions: ^extension}]} =
             GradeService.list_results(client)
  end

  test "members retain parsed custom messages and accept unknown properties", context do
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
             roles: [%{name: :instructor}],
             unrecognized_roles: ["https://vendor.example.com/role"],
             message: [
               %{
                 custom: %{"country" => "Canada"},
                 extensions: %{"https://vendor.example.com/claim" => "extension"}
               }
             ]
           } = member

    assert {:ok, stream} = MembershipsService.stream_members(client)

    assert [
             %Member{
               user_id: "user-1",
               status: :active,
               roles: [%{name: :instructor}],
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

  for collection <- [:line_items, :results, :members], page <- [1, 2, 3] do
    test "#{collection} returns rejected next links as error tuples on page #{page}", context do
      collection = unquote(collection)
      page = unquote(page)
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
  end

  defp request_options, do: [plug: {Req.Test, __MODULE__}, retry: false]

  defp build_client(registration) do
    scopes = [
      "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem.readonly",
      "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly",
      "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"
    ]

    %Client{
      access_token: "collection-token",
      expires_at: DateTime.add(DateTime.utc_now(), 3600),
      registration: registration,
      scopes: MapSet.new(scopes),
      req_options: request_options(),
      endpoints: %{
        GradeService => %AGSEndpoint{
          line_items: page_url(:line_items, 1),
          line_item: "https://platform.example.com/lineitems/1",
          scopes: scopes
        },
        MembershipsService => MembershipsEndpoint.new!(page_url(:members, 1))
      }
    }
  end

  defp stub_pages(collection, last_page, last_response) do
    owner = self()

    response = fn conn ->
      page = String.to_integer(Plug.Conn.fetch_query_params(conn).query_params["page"] || "1")
      send(owner, {:requested_page, page})
      send(owner, {:requested_query, page, conn.query_string})

      if page == last_page do
        last_response.(conn)
      else
        conn
        |> Plug.Conn.put_resp_header("link", "<#{page_url(collection, page + 1)}>; rel=\"next\"")
        |> Req.Test.json(page_body(collection, page))
      end
    end

    for name <- [__MODULE__, GradeService, MembershipsService] do
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

  defp fetch_collection(collection, client, opts \\ [])
  defp fetch_collection(:line_items, client, opts), do: GradeService.list_line_items(client, opts)
  defp fetch_collection(:results, client, opts), do: GradeService.list_results(client, opts)
  defp fetch_collection(:members, client, opts), do: MembershipsService.list_members(client, opts)

  defp stream_collection(:line_items, client), do: GradeService.stream_line_items(client)
  defp stream_collection(:results, client), do: GradeService.stream_results(client)
  defp stream_collection(:members, client), do: MembershipsService.stream_members(client)

  defp collection_identifier(:line_items, item), do: item.id
  defp collection_identifier(_collection, item), do: item.user_id
end
