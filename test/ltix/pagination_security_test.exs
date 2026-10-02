defmodule Ltix.PaginationSecurityTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.Pagination

  defp req_options do
    [plug: {Req.Test, __MODULE__}, retry: false]
  end

  test "rejects a next page at a different effective port before requesting it" do
    owner = self()

    Req.Test.stub(__MODULE__, fn conn ->
      send(owner, {:requested, conn.request_path, conn.port})

      conn
      |> Plug.Conn.put_resp_header("link", "<https://platform.example.com:8443/p2>; rel=\"next\"")
      |> Req.Test.json(%{"page" => 1})
    end)

    assert_raise TransportError, ~r/origin mismatch/, fn ->
      Pagination.stream("https://platform.example.com/p1", [{"authorization", "Bearer token"}],
        req_options: req_options()
      )
    end

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
          "https://platform.example.com:invalid/p2"
        ] do
      Req.Test.stub(__MODULE__, fn conn ->
        send(owner, {:requested, conn.request_path})

        conn
        |> Plug.Conn.put_resp_header("link", "<#{next_url}>; rel=\"next\"")
        |> Req.Test.json(%{"page" => 1})
      end)

      error =
        assert_raise TransportError, fn ->
          Pagination.stream(
            "https://platform.example.com/p1",
            [{"authorization", "Bearer token"}],
            req_options: req_options()
          )
        end

      refute Exception.message(error) =~ "secret"
      assert_receive {:requested, "/p1"}
      refute_receive {:requested, "/p2"}, 0
    end
  end

  describe "SSRF via Link header" do
    # An evil platform returns a Link header pointing to an internal service.
    # The library should refuse to follow non-HTTPS URLs.
    test "rejects non-HTTPS URL in Link header" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_header(
          "link",
          "<http://169.254.169.254/latest/meta-data/>; rel=\"next\""
        )
        |> Req.Test.json(%{"members" => [%{"user_id" => "1"}]})
      end)

      assert_raise TransportError, ~r/HTTPS/, fn ->
        Pagination.stream(
          "https://platform.example.com/members",
          [{"accept", "application/json"}],
          req_options: req_options()
        )
      end
    end

    # An evil platform returns a Link header pointing to a different host.
    # The library should refuse to follow cross-origin URLs.
    test "rejects cross-origin URL in Link header" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_header(
          "link",
          "<https://evil.com/steal?token=yes>; rel=\"next\""
        )
        |> Req.Test.json(%{"members" => [%{"user_id" => "1"}]})
      end)

      assert_raise TransportError, ~r/origin mismatch/, fn ->
        Pagination.stream(
          "https://platform.example.com/members",
          [{"accept", "application/json"}],
          req_options: req_options()
        )
      end
    end
  end
end
