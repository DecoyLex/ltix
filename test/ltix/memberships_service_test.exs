defmodule Ltix.MembershipsServiceTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.MalformedResponse
  alias Ltix.Errors.Invalid.RosterTooLarge
  alias Ltix.Errors.Invalid.ScopeMismatch
  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.Errors.Security.AccessTokenExpired
  alias Ltix.LaunchClaims.MembershipsEndpoint
  alias Ltix.LaunchClaims.Role
  alias Ltix.MembershipsService
  alias Ltix.MembershipsService.MembershipContainer
  alias Ltix.OAuth.Client

  @nrps_scope "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"
  @nrps_media_type "application/vnd.ims.lti-nrps.v2.membershipcontainer+json"

  @memberships_url "https://platform.example.com/memberships"

  setup do
    platform = Ltix.Test.setup_platform!()

    %{platform: platform}
  end

  defp req_options, do: [plug: {Req.Test, __MODULE__}, retry: false]

  defp stub_token_response do
    Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
      Req.Test.json(conn, %{
        "access_token" => "test-nrps-token",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => @nrps_scope
      })
    end)
  end

  defp stub_memberships_response(body, opts \\ []) do
    next_url = Keyword.get(opts, :next_url)

    Req.Test.stub(__MODULE__, fn conn ->
      conn =
        Plug.Conn.put_resp_content_type(conn, @nrps_media_type)

      conn =
        if next_url do
          Plug.Conn.put_resp_header(conn, "link", "<#{next_url}>; rel=\"next\"")
        else
          conn
        end

      Req.Test.json(conn, body)
    end)
  end

  defp build_membership_response(members, opts \\ []) do
    context_id = Keyword.get(opts, :context_id, "course-123")

    %{
      "id" => "https://platform.example.com/memberships",
      "context" => %{
        "id" => context_id,
        "label" => "CS101",
        "title" => "Intro to CS"
      },
      "members" => members
    }
  end

  defp build_member(user_id, roles, opts \\ []) do
    member = %{
      "user_id" => user_id,
      "roles" => roles
    }

    member
    |> maybe_put("status", Keyword.get(opts, :status))
    |> maybe_put("name", Keyword.get(opts, :name))
    |> maybe_put("email", Keyword.get(opts, :email))
    |> maybe_put("message", Keyword.get(opts, :message))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp build_client(platform, opts \\ []) do
    endpoint =
      Keyword.get(
        opts,
        :endpoint,
        MembershipsEndpoint.new(@memberships_url)
      )

    scopes =
      Keyword.get(opts, :scopes, [@nrps_scope])

    expires_at =
      Keyword.get(opts, :expires_at, DateTime.add(DateTime.utc_now(), 3600))

    %Client{
      access_token: "test-nrps-token",
      expires_at: expires_at,
      scopes: MapSet.new(scopes),
      registration: platform.registration,
      req_options: req_options(),
      endpoints: %{MembershipsService => endpoint}
    }
  end

  @learner_uri "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"
  @instructor_uri "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"

  # --- authenticate/2 ---

  describe "authenticate/2 from LaunchContext" do
    test "acquires token with correct scope", ctx do
      stub_token_response()

      context =
        Ltix.Test.build_launch_context(ctx.platform,
          memberships_endpoint: @memberships_url
        )

      assert {:ok, %Client{} = client} =
               MembershipsService.authenticate(context,
                 req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
               )

      assert MapSet.member?(client.scopes, @nrps_scope)
      assert %MembershipsEndpoint{} = client.endpoints[MembershipsService]
    end

    test "errors when no NRPS claim in launch", ctx do
      context = Ltix.Test.build_launch_context(ctx.platform)

      assert {:error, %ServiceNotAvailable{}} =
               MembershipsService.authenticate(context)
    end

    test "validates service_versions includes 2.0", ctx do
      endpoint = %MembershipsEndpoint{
        context_memberships_url: @memberships_url,
        service_versions: ["1.0"]
      }

      context =
        Ltix.Test.build_launch_context(ctx.platform,
          memberships_endpoint: endpoint
        )

      assert {:error, %ServiceNotAvailable{}} =
               MembershipsService.authenticate(context)
    end

    test "accepts nil service_versions (allows any)", ctx do
      stub_token_response()

      endpoint = %MembershipsEndpoint{
        context_memberships_url: @memberships_url,
        service_versions: nil
      }

      context =
        Ltix.Test.build_launch_context(ctx.platform,
          memberships_endpoint: endpoint
        )

      assert {:ok, %Client{}} =
               MembershipsService.authenticate(context,
                 req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
               )
    end
  end

  describe "authenticate/2 from Registration" do
    test "acquires token with endpoint option", ctx do
      stub_token_response()

      assert {:ok, %Client{} = client} =
               MembershipsService.authenticate(ctx.platform.registration,
                 endpoint: MembershipsEndpoint.new(@memberships_url),
                 req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
               )

      assert MapSet.member?(client.scopes, @nrps_scope)
    end

    test "errors without endpoint option", ctx do
      assert_raise Zoi.ParseError, fn ->
        MembershipsService.authenticate(ctx.platform.registration, [])
      end
    end
  end

  # --- get_members/2 ---

  describe "get_members/2" do
    test "returns complete MembershipContainer", ctx do
      members = [
        build_member("user-1", [@learner_uri], name: "Alice"),
        build_member("user-2", [@instructor_uri], name: "Bob")
      ]

      body = build_membership_response(members)
      stub_memberships_response(body)

      client = build_client(ctx.platform)

      assert {:ok, %MembershipContainer{} = roster} =
               MembershipsService.get_members(client)

      assert roster.context.id == "course-123"
      assert length(roster.members) == 2

      alice = Enum.find(roster.members, &(&1.user_id == "user-1"))
      assert alice.name == "Alice"
      assert Role.learner?(alice.roles)
    end

    test "follows all rel=next links across pages", ctx do
      counter = :counters.new(1, [:atomics])

      Req.Test.stub(__MODULE__, fn conn ->
        page = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)

        {body, next_url} =
          case page do
            0 ->
              {build_membership_response([build_member("user-1", [@learner_uri])]),
               "https://platform.example.com/memberships?p=2"}

            _ ->
              {build_membership_response([build_member("user-2", [@instructor_uri])]), nil}
          end

        conn = Plug.Conn.put_resp_content_type(conn, @nrps_media_type)

        conn =
          if next_url do
            Plug.Conn.put_resp_header(conn, "link", "<#{next_url}>; rel=\"next\"")
          else
            conn
          end

        Req.Test.json(conn, body)
      end)

      client = build_client(ctx.platform)

      assert {:ok, %MembershipContainer{} = roster} =
               MembershipsService.get_members(client)

      assert length(roster.members) == 2
      user_ids = Enum.map(roster.members, & &1.user_id)
      assert "user-1" in user_ids
      assert "user-2" in user_ids
    end

    test "returns RosterTooLarge when max_members exceeded", ctx do
      members =
        for i <- 1..5 do
          build_member("user-#{i}", [@learner_uri])
        end

      stub_memberships_response(build_membership_response(members))

      client = build_client(ctx.platform)

      assert {:error, %RosterTooLarge{max: 3}} =
               MembershipsService.get_members(client, max_members: 3)
    end

    test "max_members :infinity disables limit", ctx do
      members =
        for i <- 1..5 do
          build_member("user-#{i}", [@learner_uri])
        end

      stub_memberships_response(build_membership_response(members))

      client = build_client(ctx.platform)

      assert {:ok, %MembershipContainer{} = roster} =
               MembershipsService.get_members(client, max_members: :infinity)

      assert length(roster.members) == 5
    end

    test "returns ScopeMismatch when client lacks NRPS scope", ctx do
      stub_memberships_response(build_membership_response([]))

      client = build_client(ctx.platform, scopes: ["other:scope"])

      assert {:error, %ScopeMismatch{}} = MembershipsService.get_members(client)
    end

    test "returns AccessTokenExpired when token is expired", ctx do
      stub_memberships_response(build_membership_response([]))

      client =
        build_client(ctx.platform, expires_at: DateTime.add(DateTime.utc_now(), -120))

      assert {:error, %AccessTokenExpired{}} = MembershipsService.get_members(client)
    end

    test "sends correct Accept header", ctx do
      Req.Test.stub(__MODULE__, fn conn ->
        [accept] = Plug.Conn.get_req_header(conn, "accept")
        assert accept == @nrps_media_type

        conn
        |> Plug.Conn.put_resp_content_type(@nrps_media_type)
        |> Req.Test.json(build_membership_response([]))
      end)

      client = build_client(ctx.platform)
      assert {:ok, _} = MembershipsService.get_members(client)
    end

    test "sends correct Authorization header", ctx do
      Req.Test.stub(__MODULE__, fn conn ->
        [auth] = Plug.Conn.get_req_header(conn, "authorization")
        assert auth == "Bearer test-nrps-token"

        conn
        |> Plug.Conn.put_resp_content_type(@nrps_media_type)
        |> Req.Test.json(build_membership_response([]))
      end)

      client = build_client(ctx.platform)
      assert {:ok, _} = MembershipsService.get_members(client)
    end

    test "HTTP error returns error tuple", ctx do
      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 403, "Forbidden")
      end)

      client = build_client(ctx.platform)

      assert {:error, _} = MembershipsService.get_members(client)
    end
  end

  # --- Query parameters ---

  describe "query parameters" do
    test "role filter with atom", ctx do
      Req.Test.stub(__MODULE__, fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["role"] == @learner_uri

        conn
        |> Plug.Conn.put_resp_content_type(@nrps_media_type)
        |> Req.Test.json(build_membership_response([]))
      end)

      client = build_client(ctx.platform)
      assert {:ok, _} = MembershipsService.get_members(client, role: :learner)
    end

    test "role filter with URI string", ctx do
      Req.Test.stub(__MODULE__, fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["role"] == @instructor_uri

        conn
        |> Plug.Conn.put_resp_content_type(@nrps_media_type)
        |> Req.Test.json(build_membership_response([]))
      end)

      client = build_client(ctx.platform)
      assert {:ok, _} = MembershipsService.get_members(client, role: @instructor_uri)
    end

    test "role filter with short name string", ctx do
      Req.Test.stub(__MODULE__, fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["role"] == "Learner"

        conn
        |> Plug.Conn.put_resp_content_type(@nrps_media_type)
        |> Req.Test.json(build_membership_response([]))
      end)

      client = build_client(ctx.platform)
      assert {:ok, _} = MembershipsService.get_members(client, role: "Learner")
    end

    test "per_page passed as limit query parameter", ctx do
      Req.Test.stub(__MODULE__, fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["limit"] == "25"

        conn
        |> Plug.Conn.put_resp_content_type(@nrps_media_type)
        |> Req.Test.json(build_membership_response([]))
      end)

      client = build_client(ctx.platform)
      assert {:ok, _} = MembershipsService.get_members(client, per_page: 25)
    end

    test "role filter with %Role{} struct", ctx do
      Req.Test.stub(__MODULE__, fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["role"] == @instructor_uri

        conn
        |> Plug.Conn.put_resp_content_type(@nrps_media_type)
        |> Req.Test.json(build_membership_response([]))
      end)

      client = build_client(ctx.platform)
      role = %Role{type: :context, name: :instructor, sub_role: nil}
      assert {:ok, _} = MembershipsService.get_members(client, role: role)
    end

    test "resource_link_id appended as rlid parameter", ctx do
      Req.Test.stub(__MODULE__, fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["rlid"] == "resource-link-001"

        conn
        |> Plug.Conn.put_resp_content_type(@nrps_media_type)
        |> Req.Test.json(build_membership_response([]))
      end)

      client = build_client(ctx.platform)

      assert {:ok, _} =
               MembershipsService.get_members(client, resource_link_id: "resource-link-001")
    end
  end

  # --- Content-Type validation ---

  describe "content-type validation" do
    test "accepts correct NRPS media type", ctx do
      stub_memberships_response(build_membership_response([]))

      client = build_client(ctx.platform)
      assert {:ok, _} = MembershipsService.get_members(client)
    end

    test "accepts media type with parameters", ctx do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type(@nrps_media_type <> "; charset=utf-8")
        |> Req.Test.json(build_membership_response([]))
      end)

      client = build_client(ctx.platform)
      assert {:ok, _} = MembershipsService.get_members(client)
    end

    test "robustly handles wrong but compatible content type", ctx do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Req.Test.json(build_membership_response([]))
      end)

      client = build_client(ctx.platform)

      assert {:ok, %MembershipContainer{}} =
               MembershipsService.get_members(client)
    end

    test "rejects wrong content type", ctx do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Req.Test.text("This class's students are Alice, Bob, Carol, Dave, Eve")
      end)

      client = build_client(ctx.platform)

      assert {:error, %MalformedResponse{}} =
               MembershipsService.get_members(client)
    end
  end

  # --- stream_members/2 ---

  describe "stream_members/2" do
    test "returns lazy stream", ctx do
      members = [build_member("user-1", [@learner_uri])]
      stub_memberships_response(build_membership_response(members))

      client = build_client(ctx.platform)

      assert {:ok, stream} = MembershipsService.stream_members(client)
      result = Enum.to_list(stream)
      assert length(result) == 1
      assert hd(result).user_id == "user-1"
    end

    test "lazily follows pagination", ctx do
      counter = :counters.new(1, [:atomics])
      fetch_count = :counters.new(1, [:atomics])

      Req.Test.stub(__MODULE__, fn conn ->
        :counters.add(fetch_count, 1, 1)
        page = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)

        {body, next_url} =
          case page do
            0 ->
              {build_membership_response([build_member("user-1", [@learner_uri])]),
               "https://platform.example.com/memberships?p=2"}

            _ ->
              {build_membership_response([build_member("user-2", [@instructor_uri])]), nil}
          end

        conn = Plug.Conn.put_resp_content_type(conn, @nrps_media_type)

        conn =
          if next_url do
            Plug.Conn.put_resp_header(conn, "link", "<#{next_url}>; rel=\"next\"")
          else
            conn
          end

        Req.Test.json(conn, body)
      end)

      client = build_client(ctx.platform)

      assert {:ok, stream} = MembershipsService.stream_members(client)

      # First page fetched eagerly
      assert :counters.get(fetch_count, 1) == 1

      # Consuming stream fetches second page
      all = Enum.to_list(stream)
      assert length(all) == 2
      assert :counters.get(fetch_count, 1) == 2
    end

    test "returns error on first page failure", ctx do
      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 401, "Unauthorized")
      end)

      client = build_client(ctx.platform)
      assert {:error, _} = MembershipsService.stream_members(client)
    end
  end

  # --- Resource link membership ---

  describe "resource link membership" do
    test "includes message section per member", ctx do
      lti_msg = %{
        "https://purl.imsglobal.org/spec/lti/claim/message_type" => "LtiResourceLinkRequest",
        "https://purl.imsglobal.org/spec/lti/claim/version" => "1.3.0",
        "https://purl.imsglobal.org/spec/lti/claim/custom" => %{
          "grade" => "85"
        }
      }

      members = [
        build_member("user-1", [@learner_uri], message: [lti_msg])
      ]

      stub_memberships_response(build_membership_response(members))

      client = build_client(ctx.platform)

      assert {:ok, %MembershipContainer{} = roster} =
               MembershipsService.get_members(client, resource_link_id: "resource-link-001")

      assert [member] = roster.members
      assert [msg] = member.message
      assert msg.custom == %{"grade" => "85"}
    end
  end

  # --- AdvantageService callbacks ---

  describe "AdvantageService callbacks" do
    test "endpoint_from_claims extracts memberships endpoint" do
      claims = %Ltix.LaunchClaims{
        memberships_endpoint: MembershipsEndpoint.new(@memberships_url)
      }

      assert {:ok, %MembershipsEndpoint{}} =
               MembershipsService.endpoint_from_claims(claims)
    end

    test "endpoint_from_claims returns :error when no endpoint" do
      claims = %Ltix.LaunchClaims{}
      assert :error == MembershipsService.endpoint_from_claims(claims)
    end

    test "validate_endpoint accepts MembershipsEndpoint" do
      assert :ok ==
               MembershipsService.validate_endpoint(MembershipsEndpoint.new(@memberships_url))
    end

    test "validate_endpoint rejects other values" do
      assert {:error, %Ltix.Errors.Invalid.InvalidEndpoint{}} =
               MembershipsService.validate_endpoint(:not_an_endpoint)
    end

    test "scopes returns NRPS scope" do
      assert [@nrps_scope] ==
               MembershipsService.scopes(MembershipsEndpoint.new(@memberships_url))
    end
  end
end
