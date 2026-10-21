defmodule Ltix.MembershipsServiceTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.CollectionTooLarge
  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.Errors.Invalid.InvalidOption
  alias Ltix.Errors.Invalid.MalformedResponse
  alias Ltix.Errors.Invalid.ScopeMismatch
  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.Errors.Security.AccessTokenExpired
  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.MembershipsService
  alias Ltix.MembershipsService.Endpoint, as: MembershipsServiceEndpoint
  alias Ltix.MembershipsService.MembershipContainer
  alias Ltix.OAuth.AccessToken
  alias Ltix.OAuth.Client
  alias Ltix.Role

  @nrps_scope "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"
  @nrps_media_type "application/vnd.ims.lti-nrps.v2.membershipcontainer+json"

  @memberships_url "https://platform.example.com/memberships"

  setup do
    platform = Ltix.Test.setup_platform!()

    %{platform: platform}
  end

  defp req_options, do: [plug: {Req.Test, Ltix.MembershipsService}, retry: false]

  defp stub_token_response do
    Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = URI.decode_query(body)

      assert params["scope"] == @nrps_scope

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

    Req.Test.stub(Ltix.MembershipsService, fn conn ->
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
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp build_client(platform, opts \\ []) do
    endpoint =
      Keyword.get(
        opts,
        :endpoint,
        MembershipsServiceEndpoint.new!(@memberships_url)
      )

    scopes =
      Keyword.get(opts, :scopes, [@nrps_scope])

    expires_at =
      Keyword.get(opts, :expires_at, DateTime.add(DateTime.utc_now(), 3600))

    %Client{
      token: %AccessToken{
        access_token: "test-nrps-token",
        token_type: "bearer",
        expires_at: expires_at,
        granted_scopes: MapSet.new(scopes)
      },
      registration: platform.registration,
      req_options: req_options(),
      endpoints: %{MembershipsService => endpoint}
    }
  end

  @learner_uri "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"
  @instructor_uri "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"

  # --- authenticate/2 ---

  describe "options" do
    test "every operation raises on unknown options", ctx do
      client = build_client(ctx.platform)
      launch = Ltix.Test.build_launch(ctx.platform)
      endpoint = MembershipsServiceEndpoint.new!(@memberships_url)

      for call <- [
            fn -> MembershipsService.authenticate(launch, unknown: true) end,
            fn -> MembershipsService.authenticate!(launch, unknown: true) end,
            fn ->
              MembershipsService.authenticate(ctx.platform.registration,
                endpoint: endpoint,
                unknown: true
              )
            end,
            fn -> MembershipsService.list_members(client, unknown: true) end,
            fn -> MembershipsService.list_members!(client, unknown: true) end,
            fn -> MembershipsService.stream_members(client, unknown: true) end,
            fn -> MembershipsService.stream_members!(client, unknown: true) end
          ] do
        assert_raise InvalidOption, "Option :unknown is unknown", call
      end
    end

    test "operations raise on invalid values and options they do not accept", ctx do
      client = build_client(ctx.platform)

      assert_raise InvalidOption, ~r/Option :max_members is invalid/, fn ->
        MembershipsService.list_members(client, max_members: 0)
      end

      assert_raise InvalidOption, "Option :max_members is unknown", fn ->
        MembershipsService.stream_members(client, max_members: 10)
      end

      assert_raise InvalidOption, ~r/Option :role is invalid/, fn ->
        MembershipsService.list_members(client, role: :learner)
      end
    end
  end

  describe "authenticate/2 from Launch" do
    test "acquires token with correct scope", ctx do
      stub_token_response()

      launch =
        Ltix.Test.build_launch(ctx.platform,
          memberships_endpoint: @memberships_url
        )

      assert {:ok, %Client{} = client} =
               MembershipsService.authenticate(launch,
                 req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
               )

      assert MapSet.member?(client.token.granted_scopes, @nrps_scope)
      assert %MembershipsServiceEndpoint{} = client.endpoints[MembershipsService]
    end

    test "errors when no NRPS claim in launch", ctx do
      launch = Ltix.Test.build_launch(ctx.platform)

      assert {:error, %ServiceNotAvailable{} = error} =
               MembershipsService.authenticate(launch)

      assert Exception.message(error) =~ "The launch has no endpoint claim for this service"
    end

    test "validates service_versions includes 2.0", ctx do
      endpoint = %MembershipsServiceEndpoint{
        context_memberships_url: @memberships_url,
        service_versions: ["1.0"]
      }

      launch =
        Ltix.Test.build_launch(ctx.platform,
          memberships_endpoint: endpoint
        )

      assert {:error, %ServiceNotAvailable{} = error} =
               MembershipsService.authenticate(launch)

      assert Exception.message(error) =~ "The endpoint does not support NRPS version 2.0"
    end
  end

  describe "authenticate/2 from Registration" do
    test "acquires token with endpoint option", ctx do
      stub_token_response()

      assert {:ok, %Client{} = client} =
               MembershipsService.authenticate(ctx.platform.registration,
                 endpoint: MembershipsServiceEndpoint.new!(@memberships_url),
                 req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
               )

      assert MapSet.member?(client.token.granted_scopes, @nrps_scope)
    end

    test "accepts a token without the NRPS scope unless require_all_scopes is set, from a registration or a launch",
         ctx do
      Ltix.Test.stub_token_response(scopes: ["other:scope"])
      endpoint = MembershipsServiceEndpoint.new!(@memberships_url)
      req_options = [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
      launch = Ltix.Test.build_launch(ctx.platform, memberships_endpoint: endpoint)

      assert {:ok, client} =
               MembershipsService.authenticate(ctx.platform.registration,
                 endpoint: endpoint,
                 req_options: req_options
               )

      assert {:error, %ScopeMismatch{scopes: [@nrps_scope]}} =
               MembershipsService.list_members(client)

      assert {:error, %ScopeMismatch{scopes: [@nrps_scope]}} =
               MembershipsService.authenticate(ctx.platform.registration,
                 endpoint: endpoint,
                 req_options: req_options,
                 require_all_scopes: true
               )

      assert {:error, %ScopeMismatch{scopes: [@nrps_scope]}} =
               MembershipsService.authenticate(launch,
                 req_options: req_options,
                 require_all_scopes: true
               )
    end

    test "raises without endpoint option", ctx do
      assert_raise InvalidOption, "Option :endpoint is required", fn ->
        MembershipsService.authenticate(ctx.platform.registration, [])
      end
    end

    test "accepts a custom Registerable struct", _ctx do
      stub_token_response()

      custom_registration = CustomRegistration.new()

      assert {:ok, %Client{} = client} =
               MembershipsService.authenticate(custom_registration,
                 endpoint: MembershipsServiceEndpoint.new!(@memberships_url),
                 req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
               )

      assert client.registration == custom_registration
    end
  end

  # --- list_members/2 ---

  describe "list_members/2" do
    test "returns complete MembershipContainer", ctx do
      members = [
        build_member("user-1", [@learner_uri], name: "Alice"),
        build_member("user-2", [@instructor_uri], name: "Bob")
      ]

      body = build_membership_response(members)
      stub_memberships_response(body)

      client = build_client(ctx.platform)

      assert {:ok, %MembershipContainer{} = roster} =
               MembershipsService.list_members(client)

      assert roster.context.id == "course-123"
      assert length(roster.members) == 2

      alice = Enum.find(roster.members, &(&1.user_id == "user-1"))
      assert alice.name == "Alice"
      assert alice.roles == [@learner_uri]
      assert Role.learner?(alice.roles)
    end

    test "follows all rel=next links across pages", ctx do
      counter = :counters.new(1, [:atomics])

      Req.Test.stub(Ltix.MembershipsService, fn conn ->
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
               MembershipsService.list_members(client)

      assert length(roster.members) == 2
      user_ids = Enum.map(roster.members, & &1.user_id)
      assert "user-1" in user_ids
      assert "user-2" in user_ids
    end

    test "returns CollectionTooLarge when max_members exceeded", ctx do
      members =
        for i <- 1..5 do
          build_member("user-#{i}", [@learner_uri])
        end

      stub_memberships_response(build_membership_response(members))

      client = build_client(ctx.platform)

      assert {:error, %CollectionTooLarge{max: 3, option: :max_members}} =
               MembershipsService.list_members(client, max_members: 3)
    end

    test "max_members :infinity disables limit", ctx do
      members =
        for i <- 1..5 do
          build_member("user-#{i}", [@learner_uri])
        end

      stub_memberships_response(build_membership_response(members))

      client = build_client(ctx.platform)

      assert {:ok, %MembershipContainer{} = roster} =
               MembershipsService.list_members(client, max_members: :infinity)

      assert length(roster.members) == 5
    end

    test "returns ServiceNotAvailable for a client without a memberships endpoint", ctx do
      client = %{build_client(ctx.platform) | endpoints: %{}}

      for call <- [&MembershipsService.list_members/1, &MembershipsService.stream_members/1] do
        assert {:error, %ServiceNotAvailable{service: MembershipsService} = error} = call.(client)

        assert Exception.message(error) =~
                 "The client has no memberships service endpoint. Authenticate with one or pass the endpoint option"
      end
    end

    test "validates an endpoint override like the client's endpoint", ctx do
      client = build_client(ctx.platform)

      insecure = %MembershipsServiceEndpoint{
        context_memberships_url: "http://platform.example.com/m"
      }

      old_version = %MembershipsServiceEndpoint{
        context_memberships_url: @memberships_url,
        service_versions: ["1.0"]
      }

      for call <- [&MembershipsService.list_members/2, &MembershipsService.stream_members/2] do
        assert {:error, %InvalidField{field: :context_memberships_url}} =
                 call.(client, endpoint: insecure)

        assert {:error, %ServiceNotAvailable{}} = call.(client, endpoint: old_version)
      end
    end

    test "requests the endpoint override", ctx do
      Req.Test.stub(Ltix.MembershipsService, fn conn ->
        assert conn.request_path == "/other-memberships"

        conn
        |> Plug.Conn.put_resp_content_type(@nrps_media_type)
        |> Req.Test.json(build_membership_response([]))
      end)

      override = MembershipsServiceEndpoint.new!("https://platform.example.com/other-memberships")

      assert {:ok, %MembershipContainer{}} =
               MembershipsService.list_members(build_client(ctx.platform), endpoint: override)
    end

    test "returns AccessTokenExpired when token is expired", ctx do
      stub_memberships_response(build_membership_response([]))

      client =
        build_client(ctx.platform, expires_at: DateTime.add(DateTime.utc_now(), -120))

      assert {:error, %AccessTokenExpired{}} = MembershipsService.list_members(client)
    end

    test "sends correct Accept header", ctx do
      Req.Test.stub(Ltix.MembershipsService, fn conn ->
        [accept] = Plug.Conn.get_req_header(conn, "accept")
        assert accept == @nrps_media_type

        conn
        |> Plug.Conn.put_resp_content_type(@nrps_media_type)
        |> Req.Test.json(build_membership_response([]))
      end)

      client = build_client(ctx.platform)
      assert {:ok, _} = MembershipsService.list_members(client)
    end

    test "sends correct Authorization header", ctx do
      Req.Test.stub(Ltix.MembershipsService, fn conn ->
        [auth] = Plug.Conn.get_req_header(conn, "authorization")
        assert auth == "Bearer test-nrps-token"

        conn
        |> Plug.Conn.put_resp_content_type(@nrps_media_type)
        |> Req.Test.json(build_membership_response([]))
      end)

      client = build_client(ctx.platform)
      assert {:ok, _} = MembershipsService.list_members(client)
    end
  end

  # --- Query parameters ---

  describe "query parameters" do
    test "role filter with an Ltix.Role constant", ctx do
      Req.Test.stub(Ltix.MembershipsService, fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["role"] == @learner_uri

        conn
        |> Plug.Conn.put_resp_content_type(@nrps_media_type)
        |> Req.Test.json(build_membership_response([]))
      end)

      client = build_client(ctx.platform)
      assert {:ok, _} = MembershipsService.list_members(client, role: Role.context_learner())
    end

    test "role filter with URI string", ctx do
      Req.Test.stub(Ltix.MembershipsService, fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["role"] == @instructor_uri

        conn
        |> Plug.Conn.put_resp_content_type(@nrps_media_type)
        |> Req.Test.json(build_membership_response([]))
      end)

      client = build_client(ctx.platform)
      assert {:ok, _} = MembershipsService.list_members(client, role: @instructor_uri)
    end

    test "per_page passed as limit query parameter", ctx do
      Req.Test.stub(Ltix.MembershipsService, fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["limit"] == "25"

        conn
        |> Plug.Conn.put_resp_content_type(@nrps_media_type)
        |> Req.Test.json(build_membership_response([]))
      end)

      client = build_client(ctx.platform)
      assert {:ok, _} = MembershipsService.list_members(client, per_page: 25)
    end

    test "resource_link_id appended as rlid parameter", ctx do
      Req.Test.stub(Ltix.MembershipsService, fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["rlid"] == "resource-link-001"

        conn
        |> Plug.Conn.put_resp_content_type(@nrps_media_type)
        |> Req.Test.json(build_membership_response([]))
      end)

      client = build_client(ctx.platform)

      assert {:ok, _} =
               MembershipsService.list_members(client, resource_link_id: "resource-link-001")
    end
  end

  # --- Content-Type validation ---

  describe "content-type validation" do
    test "rejects wrong content type", ctx do
      Req.Test.stub(Ltix.MembershipsService, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Req.Test.text("This class's students are Alice, Bob, Carol, Dave, Eve")
      end)

      client = build_client(ctx.platform)

      assert {:error, %MalformedResponse{}} =
               MembershipsService.list_members(client)
    end
  end

  # --- stream_members/2 ---

  describe "stream_members/2" do
    test "lazily follows relative membership links", ctx do
      fetch_count = :counters.new(1, [:atomics])

      Req.Test.expect(Ltix.MembershipsService, fn conn ->
        :counters.add(fetch_count, 1, 1)

        conn
        |> Plug.Conn.put_resp_content_type(@nrps_media_type)
        |> Plug.Conn.put_resp_header("link", "</memberships?p=2>; rel=NEXT")
        |> Req.Test.json(build_membership_response([build_member("user-1", [@learner_uri])]))
      end)

      Req.Test.expect(Ltix.MembershipsService, fn conn ->
        :counters.add(fetch_count, 1, 1)
        assert conn.request_path == "/memberships"
        assert conn.query_string == "p=2"

        conn
        |> Plug.Conn.put_resp_content_type(@nrps_media_type)
        |> Req.Test.json(build_membership_response([build_member("user-2", [@instructor_uri])]))
      end)

      client = build_client(ctx.platform)

      assert {:ok, stream} = MembershipsService.stream_members(client)
      assert :counters.get(fetch_count, 1) == 1
      assert Enum.map(stream, & &1.user_id) == ["user-1", "user-2"]
      assert :counters.get(fetch_count, 1) == 2
      Req.Test.verify!(Ltix.MembershipsService)
    end

    test "returns error on first page failure", ctx do
      Req.Test.stub(Ltix.MembershipsService, &Plug.Conn.send_resp(&1, 500, "Unavailable"))

      client = build_client(ctx.platform)

      assert {:error, %TransportError{status: 500, url: @memberships_url}} =
               MembershipsService.stream_members(client)
    end
  end

  # --- AdvantageService callbacks ---

  describe "AdvantageService callbacks" do
    test "validate_endpoint rejects an endpoint without a valid URL" do
      missing = %MembershipsServiceEndpoint{
        context_memberships_url: nil,
        service_versions: ["2.0"]
      }

      insecure = %{missing | context_memberships_url: "http://platform.example.com/memberships"}

      assert {:error, %ServiceNotAvailable{} = error} =
               MembershipsService.validate_endpoint(missing)

      assert Exception.message(error) =~ "The endpoint has no context memberships URL"

      assert {:error,
              %InvalidField{struct: MembershipsServiceEndpoint, field: :context_memberships_url}} =
               MembershipsService.validate_endpoint(insecure)
    end

    test "validate_endpoint rejects other values" do
      assert {:error, %Ltix.Errors.Invalid.InvalidEndpoint{}} =
               MembershipsService.validate_endpoint(:not_an_endpoint)
    end
  end
end
