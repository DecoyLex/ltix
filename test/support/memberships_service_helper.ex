defmodule Ltix.Test.MembershipsServiceHelper do
  @moduledoc false

  alias Ltix.LaunchClaims
  alias Ltix.LaunchClaims.MembershipsEndpoint
  alias Ltix.MembershipsService
  alias Ltix.OAuth.Client

  def create_client do
    platform = Ltix.Test.setup_platform!()

    client = %Client{
      access_token: "nested-payload-token",
      expires_at: DateTime.add(DateTime.utc_now(), 3600),
      registration: platform.registration,
      scopes:
        MapSet.new(["https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"]),
      req_options: [plug: {Req.Test, MembershipsService}, retry: false],
      endpoints: %{
        MembershipsService => MembershipsEndpoint.new("https://platform.example.com/members")
      }
    }

    client
  end

  def configure_claim_parsers(parsers) do
    previous = Application.get_env(:ltix, LaunchClaims)

    ExUnit.Callbacks.on_exit(fn ->
      if previous == nil,
        do: Application.delete_env(:ltix, LaunchClaims),
        else: Application.put_env(:ltix, LaunchClaims, previous)
    end)

    Application.put_env(:ltix, LaunchClaims, Keyword.put(previous || [], :claim_parsers, parsers))
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
