defmodule Ltix.Test.MembershipsServiceHelper do
  @moduledoc false

  alias Ltix.MembershipsService
  alias Ltix.MembershipsService.Endpoint, as: MembershipsServiceEndpoint
  alias Ltix.OAuth.AccessToken
  alias Ltix.OAuth.Client

  # A client for the memberships endpoint, with the plugin set of the
  # `:plugins` listing, or of the configured listing without it.
  def create_client(opts \\ []) do
    platform = Ltix.Test.setup_platform!()
    {:ok, plugins} = Ltix.PluginSet.resolve(opts[:plugins])

    %Client{
      token: %AccessToken{
        access_token: "nested-payload-token",
        token_type: "bearer",
        expires_at: DateTime.add(DateTime.utc_now(), 3600),
        granted_scopes:
          MapSet.new([
            "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"
          ])
      },
      registration: platform.registration,
      req_options: [plug: {Req.Test, MembershipsService}, retry: false],
      endpoints: %{
        MembershipsService =>
          MembershipsServiceEndpoint.new!("https://platform.example.com/members")
      },
      plugins: plugins
    }
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
