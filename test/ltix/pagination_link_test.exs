defmodule Ltix.PaginationLinkTest do
  use ExUnit.Case, async: true

  alias Ltix.Pagination

  defp req_options, do: [plug: {Req.Test, __MODULE__}, retry: false]

  test "traverses token and quoted relations with parameter and URI delimiters" do
    pages = [
      {"/pages/1", "<https://example.com/pages/2>; rel=next"},
      {"/pages/2", "<https://example.com/pages/3>; ReL = \"prev NeXt\""},
      {"/pages/3",
       ~s(<https://example.com/pages/4,part>; title="a, b; \\"quoted\\" and \\\\ slash"; rel="n\\ext")},
      {"/pages/4,part", "<https://example.com/pages/5>; rel=next; rel=prev"},
      {"/pages/5",
       "<https://example.com/wrong>; rel=prev; rel=next, <https://example.com/pages/6>; rel=next"},
      {"/pages/6", nil}
    ]

    Enum.each(pages, fn {path, link} ->
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == path
        conn = if link, do: Plug.Conn.put_resp_header(conn, "link", link), else: conn
        Req.Test.json(conn, %{"page" => path})
      end)
    end)

    assert {:ok, stream} =
             Pagination.stream("https://example.com/pages/1", [], req_options: req_options())

    assert Enum.to_list(stream) == [
             %{"page" => "/pages/1"},
             %{"page" => "/pages/2"},
             %{"page" => "/pages/3"},
             %{"page" => "/pages/4,part"},
             %{"page" => "/pages/5"},
             %{"page" => "/pages/6"}
           ]

    Req.Test.verify!(__MODULE__)
  end

  test "traverses leading, interior, and trailing empty list elements without splitting embedded commas" do
    for link <- [
          ~s(, ,\t<https://example.com/pages/2,part>; rel=next; title="a, b"),
          ~s(<https://example.com/pages/0,part>; rel=prev; title="a, b", ,\t, <https://example.com/pages/2,part>; rel=next),
          ~s(<https://example.com/pages/2,part>; rel=next; title="a, b", ,\t,)
        ] do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/pages/1"

        conn
        |> Plug.Conn.put_resp_header("link", link)
        |> Req.Test.json(%{"page" => 1})
      end)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/pages/2,part"

        conn
        |> Plug.Conn.put_resp_header("link", ~s(, <../1,part>; rel=prev; title="a, b", ,))
        |> Req.Test.json(%{"page" => 2})
      end)

      assert {:ok, stream} =
               Pagination.stream("https://example.com/pages/1", [], req_options: req_options())

      assert Enum.to_list(stream) == [%{"page" => 1}, %{"page" => 2}]
      Req.Test.verify!(__MODULE__)
    end
  end

  test "does not mistake other parameters or quoted attribute text for next relations" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_header(
        "link",
        ~s(<https://example.com/notrel>; notrel="next", <https://example.com/title>; title="rel=\\"next\\"", <https://example.com/extension>; rel="https://example.com/next", <https://example.com/prefix>; rel="next-page", <https://example.com/duplicate>; rel=prev; rel="next")
      )
      |> Plug.Conn.put_resp_header("not-link", "<https://example.com/wrong>; rel=next")
      |> Req.Test.json(%{"page" => "only"})
    end)

    assert {:ok, stream} =
             Pagination.stream("https://example.com/pages/1", [], req_options: req_options())

    assert Enum.to_list(stream) == [%{"page" => "only"}]
    Req.Test.verify!(__MODULE__)
  end

  test "ignores the entire anchored link and follows an unanchored link" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_header(
        "link",
        "<https://example.com/wrong>; rel=next; ANCHOR=\"#other\", <https://example.com/pages/2>; title=\"anchor=other\"; rel=next"
      )
      |> Req.Test.json(%{"page" => 1})
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/pages/2"

      conn
      |> Plug.Conn.put_resp_header("link", "<https://example.com/wrong>; anchor=\"\"; rel=next")
      |> Req.Test.json(%{"page" => 2})
    end)

    assert {:ok, stream} =
             Pagination.stream("https://example.com/pages/1", [], req_options: req_options())

    assert Enum.to_list(stream) == [%{"page" => 1}, %{"page" => 2}]
    Req.Test.verify!(__MODULE__)
  end

  test "searches repeated Link field values" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn = %{
        conn
        | resp_headers: [
            {"link", "<https://example.com/pages/1>; rel=prev"},
            {"link", "<https://example.com/pages/2>; rel=next"}
          ]
      }

      Req.Test.json(conn, %{"page" => 1})
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/pages/2"
      Req.Test.json(conn, %{"page" => 2})
    end)

    assert {:ok, stream} =
             Pagination.stream("https://example.com/pages/1", [], req_options: req_options())

    assert Enum.to_list(stream) == [%{"page" => 1}, %{"page" => 2}]
    Req.Test.verify!(__MODULE__)
  end

  test "resolves every relative target against the current page URL" do
    pages = [
      {"/start/items", "", "</moved/pages/two?cursor=2>"},
      {"/moved/pages/two", "cursor=2", "<../three?cursor=3>"},
      {"/moved/three", "cursor=3", "<?cursor=4>"},
      {"/moved/three", "cursor=4", "<//example.com/final?cursor=5>"},
      {"/final", "cursor=5", "<>"},
      {"/final", "cursor=5", nil}
    ]

    Enum.each(pages, fn {path, query, target} ->
      Req.Test.expect(__MODULE__, fn conn ->
        assert {conn.request_path, conn.query_string} == {path, query}

        conn =
          if target,
            do: Plug.Conn.put_resp_header(conn, "link", target <> "; rel=next"),
            else: conn

        Req.Test.json(conn, %{"location" => path <> "?" <> query})
      end)
    end)

    assert {:ok, stream} =
             Pagination.stream("https://example.com/start/items", [], req_options: req_options())

    assert Enum.to_list(stream) == [
             %{"location" => "/start/items?"},
             %{"location" => "/moved/pages/two?cursor=2"},
             %{"location" => "/moved/three?cursor=3"},
             %{"location" => "/moved/three?cursor=4"},
             %{"location" => "/final?cursor=5"},
             %{"location" => "/final?cursor=5"}
           ]

    Req.Test.verify!(__MODULE__)
  end
end
