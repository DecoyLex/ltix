defmodule Ltix.ServiceCollectionFailuresTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.RosterTooLarge
  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.GradeService
  alias Ltix.LaunchClaims.AgsEndpoint
  alias Ltix.LaunchClaims.MembershipsEndpoint
  alias Ltix.MembershipsService
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

    test "#{collection} preserves a transport exception on page #{page}", context do
      collection = unquote(collection)
      failed_page = unquote(page)
      client = build_client(context.registration)
      stub_pages(collection, failed_page, &Req.Test.transport_error(&1, :timeout))

      assert {:error, %Req.TransportError{reason: :timeout}} =
               fetch_collection(collection, client)

      assert_receive {:requested_page, ^failed_page}
      refute_received {:requested_page, 4}
    end
  end

  for page <- [2, 3] do
    test "lazy members raise only when HTTP failure page #{page} is consumed", context do
      failed_page = unquote(page)
      client = build_client(context.registration)

      stub_pages(:members, failed_page, fn conn ->
        Plug.Conn.send_resp(conn, 500, "unavailable")
      end)

      assert {:ok, stream} = MembershipsService.stream_members(client)
      assert_receive {:requested_page, 1}
      refute_received {:requested_page, ^failed_page}
      assert [%{user_id: "user-1"}] = Enum.take(stream, 1)
      refute_received {:requested_page, ^failed_page}
      assert_raise TransportError, fn -> Enum.to_list(stream) end
      assert_receive {:requested_page, ^failed_page}
    end

    test "lazy members preserve the transport exception on page #{page}", context do
      failed_page = unquote(page)
      client = build_client(context.registration)
      stub_pages(:members, failed_page, &Req.Test.transport_error(&1, :timeout))

      assert {:ok, stream} = MembershipsService.stream_members(client)
      assert_raise Req.TransportError, fn -> Enum.to_list(stream) end
      assert_receive {:requested_page, ^failed_page}
    end
  end

  test "roster limit stops traversal before an unnecessary failing page", context do
    client = build_client(context.registration)
    stub_pages(:members, 3, fn conn -> Plug.Conn.send_resp(conn, 500, "unavailable") end)

    assert {:error, %RosterTooLarge{count: 2, max: 1}} =
             MembershipsService.get_members(client, max_members: 1)

    assert_receive {:requested_page, 2}
    refute_received {:requested_page, 3}
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
        GradeService => %AgsEndpoint{
          lineitems: page_url(:line_items, 1),
          lineitem: "https://platform.example.com/lineitems/1",
          scope: scopes
        },
        MembershipsService => MembershipsEndpoint.new(page_url(:members, 1))
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
  defp fetch_collection(:results, client, opts), do: GradeService.get_results(client, opts)
  defp fetch_collection(:members, client, opts), do: MembershipsService.get_members(client, opts)
end
