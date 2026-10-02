defmodule Ltix.Integration.TransportSecurityTest do
  use ExUnit.Case, async: false

  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.GradeService
  alias Ltix.GradeService.LineItem
  alias Ltix.GradeService.Score
  alias Ltix.JWT.KeySet
  alias Ltix.LaunchClaims.AgsEndpoint
  alias Ltix.LaunchClaims.MembershipsEndpoint
  alias Ltix.MembershipsService
  alias Ltix.OAuth.Client
  alias Ltix.OAuth.ClientCredentials

  setup do
    platform = Ltix.Test.setup_platform!()

    scopes = [
      "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
      "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly",
      "https://purl.imsglobal.org/spec/lti-ags/scope/score",
      "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"
    ]

    client = %Client{
      access_token: "secret-bearer-token",
      expires_at: DateTime.add(DateTime.utc_now(), 3600),
      scopes: MapSet.new(scopes),
      registration: platform.registration,
      req_options: [plug: {Req.Test, :ltix}, retry: false],
      endpoints: %{
        GradeService => %AgsEndpoint{
          lineitems: "https://grades.example.com/lineitems",
          lineitem: "https://grades.example.com/lineitems/1",
          scope: scopes
        },
        MembershipsService => %MembershipsEndpoint{
          context_memberships_url: "https://roster.example.com/members"
        }
      }
    }

    {:ok, score} =
      Score.new(
        user_id: "student",
        activity_progress: :completed,
        grading_progress: :fully_graded
      )

    %{client: client, score: score, registration: platform.registration}
  end

  test "rejects unsafe explicit grade URLs before sending credentials", %{
    client: client,
    score: score
  } do
    owner = self()

    Req.Test.stub(GradeService, fn conn ->
      send(owner, {:reached, conn.host})

      Req.Test.json(conn, %{
        "id" => "https://grades.example.com/lineitems/1",
        "label" => "Quiz",
        "scoreMaximum" => 100
      })
    end)

    for url <- [
          "http://127.0.0.1/lineitems/1",
          "https:///lineitems/1",
          "/lineitems/1",
          "https://secret@grades.example.com/lineitems/1",
          "https://grades.example.com:70000/lineitems/1",
          "https://grades.example.com:invalid/lineitems/1",
          "https://[not-an-ip]/lineitems/1",
          "https://[::1/lineitems/1"
        ] do
      assert {:error, %TransportError{} = error} =
               GradeService.post_score(client, score, line_item: url)

      assert Exception.message(error) =~ "HTTPS"
      refute Exception.message(error) =~ "secret"
      assert {:error, %TransportError{}} = GradeService.get_line_item(client, line_item: url)
      assert {:error, %TransportError{}} = GradeService.delete_line_item(client, url, force: true)

      assert {:error, %TransportError{}} =
               GradeService.update_line_item(client, %LineItem{
                 id: url,
                 label: "Quiz",
                 score_maximum: 100
               })

      assert {:error, %TransportError{}} = GradeService.get_results(client, line_item: url)
    end

    refute_receive {:reached, _}
  end

  for {name, authority, host} <- [
        {"registered-name punctuation", "host!name.example", "host!name.example"},
        {"percent-encoded registered names", "m%C3%BCnchen.example", "m%c3%bcnchen.example"},
        {"IPv6 literals", "[2001:db8::1]", "2001:db8::1"},
        {"trailing dots", "grades.example.com.", "grades.example.com."}
      ] do
    test "accepts HTTPS endpoints with #{name}", %{client: client, score: score} do
      host = unquote(host)
      owner = self()

      Req.Test.stub(GradeService, fn conn ->
        send(
          owner,
          {:score_request, conn.host, conn.request_path,
           Plug.Conn.get_req_header(conn, "authorization")}
        )

        Plug.Conn.send_resp(conn, 204, "")
      end)

      assert :ok =
               GradeService.post_score(client, score,
                 line_item: "https://#{unquote(authority)}/lineitems/1"
               )

      assert_receive {:score_request, ^host, "/lineitems/1/scores",
                      ["Bearer secret-bearer-token"]}
    end
  end

  test "rejects insecure configured endpoints for eager and streaming calls", %{client: client} do
    owner = self()

    for service <- [GradeService, MembershipsService] do
      Req.Test.stub(service, fn conn ->
        send(owner, {:reached, conn.host})
        Req.Test.json(conn, [])
      end)
    end

    client = %{
      client
      | endpoints: %{
          GradeService => %AgsEndpoint{lineitems: "http://127.0.0.1/lineitems"},
          MembershipsService => %MembershipsEndpoint{
            context_memberships_url: "http://127.0.0.1/members"
          }
        }
    }

    assert {:error, %TransportError{}} = GradeService.list_line_items(client)

    assert {:error, %TransportError{}} =
             GradeService.create_line_item(client, label: "Quiz", score_maximum: 100)

    assert {:error, %TransportError{}} = MembershipsService.get_members(client)
    assert {:error, %TransportError{}} = MembershipsService.stream_members(client)
    refute_receive {:reached, _}
  end

  test "accepts HTTPS service hosts distinct from the issuer and token host", %{
    client: client,
    score: score
  } do
    owner = self()

    Req.Test.stub(GradeService, fn conn ->
      send(
        owner,
        {:grade_request, conn.scheme, conn.host, conn.port,
         Plug.Conn.get_req_header(conn, "authorization")}
      )

      Plug.Conn.send_resp(conn, 204, "")
    end)

    for url <- [
          "https://grades.example.com/lineitems/1",
          "HTTPS://GRADES.example.com:443/lineitems/1",
          "https://127.0.0.1:8443/lineitems/1"
        ] do
      assert :ok = GradeService.post_score(client, score, line_item: url)
    end

    assert_receive {:grade_request, :https, "grades.example.com", 443,
                    ["Bearer secret-bearer-token"]}

    assert_receive {:grade_request, :https, "grades.example.com", 443,
                    ["Bearer secret-bearer-token"]}

    assert_receive {:grade_request, :https, "127.0.0.1", 8443, ["Bearer secret-bearer-token"]}
  end

  test "rejects insecure OAuth and JWKS URLs even on directly constructed registrations", %{
    registration: registration
  } do
    owner = self()

    for service <- [ClientCredentials, KeySet] do
      Req.Test.stub(service, fn conn ->
        send(owner, {:reached, conn.host})
        Req.Test.json(conn, %{"access_token" => "token", "token_type" => "Bearer", "keys" => []})
      end)
    end

    registration = %{
      registration
      | token_endpoint: "http://127.0.0.1/token",
        jwks_uri: "http://127.0.0.1/keys"
    }

    assert {:error, %TransportError{} = error} =
             ClientCredentials.request_token(registration, [],
               req_options: [plug: {Req.Test, :ltix}]
             )

    assert Exception.message(error) =~ "HTTPS"

    assert {:error, error} =
             KeySet.get_key(registration, "kid", req_options: [plug: {Req.Test, :ltix}])

    assert Exception.message(error) =~ "HTTPS"
    refute_receive {:reached, _}
  end

  test "an insecure direct score URL never opens a loopback connection", %{
    client: client,
    score: score
  } do
    {:ok, listener} = :gen_tcp.listen(0, ip: {127, 0, 0, 1}, active: false)
    on_exit(fn -> :gen_tcp.close(listener) end)
    {:ok, port} = :inet.port(listener)
    client = %{client | req_options: [retry: false]}

    assert {:error, %TransportError{}} =
             GradeService.post_score(client, score,
               line_item: "http://127.0.0.1:#{port}/lineitems/1"
             )

    assert {:error, :timeout} = :gen_tcp.accept(listener, 100)
  end

  test "caller URL and base URL options cannot replace the service destination", %{
    client: client,
    score: score
  } do
    Req.Test.stub(GradeService, fn conn ->
      assert conn.scheme == :https
      assert conn.host == "grades.example.com"
      Plug.Conn.send_resp(conn, 204, "")
    end)

    client = %{
      client
      | req_options:
          Keyword.merge(client.req_options,
            url: "http://127.0.0.1/steal",
            base_url: "http://127.0.0.1"
          )
    }

    assert :ok = GradeService.post_score(client, score)
  end
end
