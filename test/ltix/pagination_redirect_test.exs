defmodule Ltix.PaginationRedirectTest do
  use ExUnit.Case, async: true

  alias Ltix.Pagination

  @headers [{"authorization", "Bearer pagination-token"}]

  test "first-page redirects use current queries and later links use the final response URL" do
    owner = self()

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/initial"
      assert conn.query_string == "filter=secret"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer pagination-token"]

      conn
      |> Plug.Conn.put_resp_header("location", "/moved/pages/current?step=1")
      |> Plug.Conn.send_resp(302, "")
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/moved/pages/current"
      assert conn.query_string == "step=1"
      assert conn.method == "GET"

      conn
      |> Plug.Conn.put_resp_header("location", "?step=2")
      |> Plug.Conn.send_resp(307, "")
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.query_string == "step=2"
      send(owner, :first_page)

      conn
      |> Plug.Conn.put_resp_header("link", "<next?page=3>; rel=next")
      |> Req.Test.json(%{"page" => 2})
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      send(owner, :next_page)
      assert conn.request_path == "/moved/pages/next"
      assert conn.query_string == "page=3"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer pagination-token"]
      Req.Test.json(conn, %{"page" => 3})
    end)

    assert {:ok, pages} =
             Pagination.stream("https://platform.example.com/initial", @headers,
               params: %{"filter" => "secret"},
               req_options: req_options()
             )

    assert_receive :first_page
    refute_receive :next_page, 0
    assert Enum.take(pages, 1) == [%{"page" => 2}]
    refute_receive :next_page, 0
    assert Enum.to_list(pages) == [%{"page" => 2}, %{"page" => 3}]
    assert_receive :next_page
    Req.Test.verify!(__MODULE__)
  end

  defp req_options do
    [plug: {Req.Test, __MODULE__}, retry: false, redirect_trusted: true]
  end
end
