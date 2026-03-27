defmodule Ltix.PaginationSecurityTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.Pagination

  defp req_options do
    [plug: {Req.Test, __MODULE__}, retry: false]
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

      assert_raise TransportError, ~r/must use HTTPS/, fn ->
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

      assert_raise TransportError, ~r/host mismatch/, fn ->
        Pagination.stream(
          "https://platform.example.com/members",
          [{"accept", "application/json"}],
          req_options: req_options()
        )
      end
    end
  end
end
