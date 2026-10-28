defmodule Ltix.PaginationTest do
  use ExUnit.Case, async: true

  alias Ltix.Pagination

  doctest Ltix.Pagination

  defp req_options do
    [plug: {Req.Test, __MODULE__}, retry: false]
  end

  defp stub_pages(pages) do
    # pages is a list of {body, next_url | nil}
    counter = :counters.new(1, [:atomics])

    Req.Test.stub(__MODULE__, fn conn ->
      page_index = :counters.get(counter, 1)
      :counters.add(counter, 1, 1)

      {body, next_url} = Enum.at(pages, page_index)

      conn =
        if next_url do
          Plug.Conn.put_resp_header(conn, "link", "<#{next_url}>; rel=\"next\"")
        else
          conn
        end

      Req.Test.json(conn, body)
    end)
  end

  describe "options" do
    test "stream/3 raises on unknown options" do
      assert_raise ArgumentError, "Option :query is unknown", fn ->
        Pagination.stream("https://example.com/api", [], query: %{})
      end
    end
  end

  describe "stream/3" do
    test "follows rel=next across multiple pages" do
      stub_pages([
        {%{"items" => [1, 2]}, "https://example.com/api?p=2"},
        {%{"items" => [3, 4]}, "https://example.com/api?p=3"},
        {%{"items" => [5]}, nil}
      ])

      assert {:ok, stream} =
               Pagination.stream(
                 "https://example.com/api",
                 [{"accept", "application/json"}],
                 req_options: req_options()
               )

      assert Enum.to_list(stream) == [
               %{"items" => [1, 2]},
               %{"items" => [3, 4]},
               %{"items" => [5]}
             ]
    end

    test "returns error on first page failure" do
      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Unavailable")
      end)

      assert {:error, %Ltix.Errors.Unknown.TransportError{status: 500}} =
               Pagination.stream(
                 "https://example.com/api",
                 [{"accept", "application/json"}],
                 req_options: req_options()
               )
    end

    test "raises on subsequent page failure" do
      counter = :counters.new(1, [:atomics])

      Req.Test.stub(__MODULE__, fn conn ->
        page = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)

        case page do
          0 ->
            conn
            |> Plug.Conn.put_resp_header("link", "<https://example.com/api?p=2>; rel=\"next\"")
            |> Req.Test.json(%{"items" => [1]})

          _ ->
            Plug.Conn.send_resp(conn, 500, "Internal Server Error")
        end
      end)

      assert {:ok, stream} =
               Pagination.stream(
                 "https://example.com/api",
                 [{"accept", "application/json"}],
                 req_options: req_options()
               )

      assert_raise Ltix.Errors.Unknown.TransportError, fn -> Enum.to_list(stream) end
    end

    test "passes params only on first request" do
      requests = :ets.new(:requests, [:set, :public])

      counter = :counters.new(1, [:atomics])

      Req.Test.stub(__MODULE__, fn conn ->
        page = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)

        :ets.insert(requests, {page, conn.query_string})

        case page do
          0 ->
            conn
            |> Plug.Conn.put_resp_header("link", "<https://example.com/api?p=2>; rel=\"next\"")
            |> Req.Test.json(%{"items" => [1]})

          _ ->
            Req.Test.json(conn, %{"items" => [2]})
        end
      end)

      assert {:ok, stream} =
               Pagination.stream(
                 "https://example.com/api",
                 [{"accept", "application/json"}],
                 params: %{"limit" => "10", "role" => "Learner"},
                 req_options: req_options()
               )

      assert Enum.to_list(stream) == [%{"items" => [1]}, %{"items" => [2]}]

      [{0, first_qs}] = :ets.lookup(requests, 0)
      [{1, second_qs}] = :ets.lookup(requests, 1)

      assert first_qs =~ "limit=10"
      assert first_qs =~ "role=Learner"
      # Second page uses the next URL as-is, params from the URL itself
      assert second_qs == "p=2"
    end

    test "stream is lazy and does not fetch page 2 until consumed" do
      counter = :counters.new(1, [:atomics])
      fetch_count = :counters.new(1, [:atomics])

      Req.Test.stub(__MODULE__, fn conn ->
        :counters.add(fetch_count, 1, 1)
        page = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)

        case page do
          0 ->
            conn
            |> Plug.Conn.put_resp_header("link", "<https://example.com/api?p=2>; rel=\"next\"")
            |> Req.Test.json(%{"items" => [1, 2]})

          _ ->
            Req.Test.json(conn, %{"items" => [3]})
        end
      end)

      assert {:ok, stream} =
               Pagination.stream(
                 "https://example.com/api",
                 [{"accept", "application/json"}],
                 req_options: req_options()
               )

      # Only first page fetched so far
      assert :counters.get(fetch_count, 1) == 1

      # Take first body, which should not trigger page 2 fetch
      assert Enum.take(stream, 1) == [%{"items" => [1, 2]}]
      assert :counters.get(fetch_count, 1) == 1

      # Take all. Now page 2 is fetched
      assert Enum.to_list(stream) == [%{"items" => [1, 2]}, %{"items" => [3]}]
    end
  end

  describe "repeated pages" do
    test "returns an error for a next link to the page that returned it" do
      owner = self()

      Req.Test.stub(__MODULE__, fn conn ->
        send(owner, {:requested, conn.request_path})

        conn
        |> Plug.Conn.put_resp_header("link", "<https://example.com/api?limit=2>; rel=\"next\"")
        |> Req.Test.json(%{"members" => []})
      end)

      assert {:error, %Ltix.Errors.Unknown.TransportError{body: body}} =
               Pagination.stream_results("https://example.com/api", [],
                 params: %{"limit" => "2"},
                 req_options: req_options()
               )

      assert body =~ "already fetched"
      assert_receive {:requested, "/api"}
      refute_receive {:requested, _}
    end

    test "ends the stream with an error when next links return to an earlier page" do
      Req.Test.stub(__MODULE__, fn conn ->
        next = if conn.request_path == "/a", do: "/b", else: "/a"

        conn
        |> Plug.Conn.put_resp_header("link", "<#{next}>; rel=\"next\"")
        |> Req.Test.json(%{"page" => conn.request_path})
      end)

      assert {:ok, stream} =
               Pagination.stream_results("https://example.com/a", [], req_options: req_options())

      assert [{:ok, %{"page" => "/a"}}, {:error, %Ltix.Errors.Unknown.TransportError{}}] =
               Enum.take(stream, 5)
    end
  end
end
