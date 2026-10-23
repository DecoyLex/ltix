defmodule MembershipsServiceFixtures do
  @moduledoc false

  alias Ltix.MembershipsService
  alias Ltix.MembershipsService.Endpoint, as: MembershipsServiceEndpoint

  # A client for the memberships endpoint, with the plugin set of the
  # `:plugins` list (defaults to no plugins).
  def create_client(opts \\ []) do
    TestClient.build(
      Ltix.Test.setup_platform!().registration,
      %{
        MembershipsService =>
          MembershipsServiceEndpoint.new!("https://platform.example.com/members")
      },
      Keyword.merge(
        [
          scopes: ["https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"],
          req_options: [plug: {Req.Test, MembershipsService}, retry: false]
        ],
        opts
      )
    )
  end

  # Stubs one page with `members`. Returns what `list_members/2` returns, and
  # the members `stream_members/2` streams or the error it raises.
  def list_and_stream(client, members, opts \\ []) do
    stub_pages(1, Map.put(container(1), "members", members))
    listed = MembershipsService.list_members(client, opts)

    streamed =
      with {:ok, stream} <- MembershipsService.stream_members(client, opts) do
        try do
          {:ok, Enum.to_list(stream)}
        rescue
          error -> {:error, error}
        end
      end

    {listed, streamed}
  end

  def stub_pages(last_page, last_body) do
    Req.Test.stub(MembershipsService, fn conn ->
      page = String.to_integer(Plug.Conn.fetch_query_params(conn).query_params["page"] || "1")

      if page == last_page do
        Req.Test.json(conn, last_body)
      else
        conn
        |> Plug.Conn.put_resp_header(
          "link",
          "<https://platform.example.com/members?page=#{page + 1}>; rel=\"next\""
        )
        |> Req.Test.json(container(page))
      end
    end)
  end

  def container(page),
    do: %{
      "id" => "https://platform.example.com/members",
      "context" => %{"id" => "course"},
      "members" => [member("user-#{page}")]
    }

  def member(user_id), do: %{"user_id" => user_id, "roles" => []}
end
