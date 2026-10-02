defmodule Ltix.PaginationSecurityTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.Pagination

  test "rejects a next page at a different effective port before requesting it" do
    owner = self()

    Req.Test.stub(__MODULE__, fn conn ->
      send(owner, {:requested, conn.request_path, conn.port})

      conn
      |> Plug.Conn.put_resp_header("link", "<https://platform.example.com:8443/p2>; rel=\"next\"")
      |> Req.Test.json(%{"page" => 1})
    end)

    assert {:error, %TransportError{}} =
             Pagination.stream(
               "https://platform.example.com/p1",
               [{"authorization", "Bearer token"}],
               req_options: req_options()
             )

    assert_receive {:requested, "/p1", 443}
    refute_receive {:requested, "/p2", _}
  end

  test "accepts normalized scheme and host with equivalent effective ports" do
    owner = self()

    for {first_url, next_url, port} <- [
          {"https://platform.example.com/p1", "HTTPS://PLATFORM.EXAMPLE.COM:443/p2", 443},
          {"HTTPS://PLATFORM.EXAMPLE.COM:443/p1", "https://platform.example.com/p2", 443},
          {"https://platform.example.com:8443/p1", "https://PLATFORM.EXAMPLE.COM:8443/p2", 8443}
        ] do
      Req.Test.stub(__MODULE__, fn conn ->
        send(
          owner,
          {:requested, conn.scheme, conn.host, conn.port,
           Plug.Conn.get_req_header(conn, "authorization")}
        )

        case conn.request_path do
          "/p1" ->
            conn
            |> Plug.Conn.put_resp_header("link", "<#{next_url}>; rel=\"next\"")
            |> Req.Test.json(%{"page" => 1})

          "/p2" ->
            Req.Test.json(conn, %{"page" => 2})
        end
      end)

      assert {:ok, pages} =
               Pagination.stream(first_url, [{"authorization", "Bearer token"}],
                 req_options: req_options()
               )

      assert Enum.to_list(pages) == [%{"page" => 1}, %{"page" => 2}]
      assert_receive {:requested, :https, "platform.example.com", ^port, ["Bearer token"]}
      assert_receive {:requested, :https, "platform.example.com", ^port, ["Bearer token"]}
    end
  end

  test "rejects malformed next page URLs and user information without leaking it in errors" do
    owner = self()

    for next_url <- [
          "https://secret@platform.example.com/p2",
          "https:///p2",
          "https://platform.example.com:invalid/p2",
          "//platform.example.com:invalid/p2"
        ] do
      Req.Test.stub(__MODULE__, fn conn ->
        send(owner, {:requested, conn.request_path})

        conn
        |> Plug.Conn.put_resp_header("link", "<#{next_url}>; rel=\"next\"")
        |> Req.Test.json(%{"page" => 1})
      end)

      assert {:error, %TransportError{} = error} =
               Pagination.stream(
                 "https://platform.example.com/p1",
                 [{"authorization", "Bearer token"}],
                 req_options: req_options()
               )

      refute Exception.message(error) =~ "secret"
      assert_receive {:requested, "/p1"}
      refute_receive {:requested, "/p2"}, 0
    end
  end

  @endpoint "https://platform.example.com/members"
  @headers [{"authorization", "Bearer pagination-token"}]

  test "stream returns a first-page error tuple for a cross-origin next link" do
    invalid_url = "https://evil.com/steal?token=yes"
    stub_pages(1, invalid_url)

    assert {:error, %TransportError{}} =
             Pagination.stream(@endpoint, @headers, req_options: req_options())

    assert_receive {:requested_page, 1}
    refute_received {:requested_page, 2}
  end

  test "stream returns a first-page error tuple for a plain HTTP next link" do
    stub_pages(1, "http://platform.example.com/members?page=2")

    assert {:error, %TransportError{body: body}} =
             Pagination.stream(@endpoint, @headers, req_options: req_options())

    assert body =~ "must be an absolute HTTPS URL"
    assert_receive {:requested_page, 1}
    refute_received {:requested_page, 2}
  end

  test "result stream emits one error for a cross-origin next link" do
    rejected_page = 2
    invalid_url = "https://evil.com/steal?token=yes"
    stub_pages(rejected_page, invalid_url)

    assert {:ok, pages} =
             Pagination.stream_results(@endpoint, @headers, req_options: req_options())

    assert_receive {:requested_page, 1}
    refute_received {:requested_page, ^rejected_page}

    results = Enum.to_list(pages)

    assert [{:error, %TransportError{}}] =
             Enum.drop(results, rejected_page - 1)

    assert Enum.take(results, rejected_page - 1) ==
             Enum.map(1..(rejected_page - 1), &{:ok, [&1]})

    assert_receive {:requested_page, ^rejected_page}
  end

  defp req_options, do: [plug: {Req.Test, __MODULE__}, retry: false]

  defp stub_pages(rejected_page, invalid_url) do
    owner = self()

    Req.Test.stub(__MODULE__, fn conn ->
      page = String.to_integer(Plug.Conn.fetch_query_params(conn).query_params["page"] || "1")
      assert conn.host == "platform.example.com"
      assert page <= rejected_page
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer pagination-token"]
      send(owner, {:requested_page, page})
      next_url = if page == rejected_page, do: invalid_url, else: "#{@endpoint}?page=#{page + 1}"

      conn
      |> Plug.Conn.put_resp_header("link", "<#{next_url}>; rel=\"next\"")
      |> Req.Test.json([page])
    end)
  end
end
