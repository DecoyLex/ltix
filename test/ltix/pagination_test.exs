defmodule Ltix.PaginationTest do
  use ExUnit.Case, async: true

  alias Ltix.Pagination

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

  describe "stream/3" do
    test "single page with no next link" do
      stub_pages([{%{"items" => [1, 2, 3]}, nil}])

      assert {:ok, stream} =
               Pagination.stream(
                 "https://example.com/api",
                 [{"accept", "application/json"}],
                 req_options: req_options()
               )

      assert Enum.to_list(stream) == [%{"items" => [1, 2, 3]}]
    end

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
        Plug.Conn.send_resp(conn, 401, "Unauthorized")
      end)

      assert {:error, %Ltix.Errors.Unknown.TransportError{status: 401}} =
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

    test "terminates when last page has no next link" do
      stub_pages([
        {%{"items" => [1, 2]}, "https://example.com/api?p=2"},
        {%{"items" => []}, nil}
      ])

      assert {:ok, stream} =
               Pagination.stream(
                 "https://example.com/api",
                 [{"accept", "application/json"}],
                 req_options: req_options()
               )

      assert Enum.to_list(stream) == [
               %{"items" => [1, 2]},
               %{"items" => []}
             ]
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

    test "stream is lazy — does not fetch page 2 until consumed" do
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

      # Take first body — should not trigger page 2 fetch
      assert Enum.take(stream, 1) == [%{"items" => [1, 2]}]
      assert :counters.get(fetch_count, 1) == 1

      # Take all — now page 2 is fetched
      assert Enum.to_list(stream) == [%{"items" => [1, 2]}, %{"items" => [3]}]
    end
  end
end
