defmodule Ltix.Integration.TransportSecurityTest do
  use ExUnit.Case, async: false

  alias Ltix.Errors.Unknown
  alias Ltix.Errors.Unknown.RedirectNotAllowed
  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.GradeService
  alias Ltix.GradeService.LineItem
  alias Ltix.GradeService.Score
  alias Ltix.JWT.KeySet
  alias Ltix.LaunchClaims.AgsEndpoint
  alias Ltix.LaunchClaims.MembershipsEndpoint
  alias Ltix.LaunchContext
  alias Ltix.MembershipsService
  alias Ltix.OAuth.AccessToken
  alias Ltix.OAuth.Client
  alias Ltix.OAuth.ClientCredentials
  alias Ltix.Test.StorageAdapter

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

    %{client: client, score: score, registration: platform.registration, platform: platform}
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

  test "unsafe service redirects are rejected even with trusted application and caller options",
       %{
         client: client,
         score: score
       } do
    previous = Application.get_env(:ltix, :req_options)
    Application.put_env(:ltix, :req_options, redirect: true, redirect_trusted: true)

    on_exit(fn ->
      if previous == nil,
        do: Application.delete_env(:ltix, :req_options),
        else: Application.put_env(:ltix, :req_options, previous)
    end)

    owner = self()

    client = %{
      client
      | req_options: Keyword.merge(client.req_options, redirect: true, redirect_trusted: true)
    }

    for status <- [301, 302, 303, 307, 308],
        destination <- [
          "http://127.0.0.1/redirected",
          "https://other.example.com/redirected",
          "https://grades.example.com:8443/redirected",
          "https://secret@grades.example.com/redirected"
        ] do
      Req.Test.stub(GradeService, fn conn ->
        case conn.request_path do
          "/lineitems/1/scores" ->
            conn
            |> Plug.Conn.put_resp_header("location", destination)
            |> Plug.Conn.send_resp(status, "secret-response-body")

          _ ->
            send(
              owner,
              {:redirect_reached, conn.scheme, conn.host, conn.port,
               Plug.Conn.get_req_header(conn, "authorization")}
            )

            Plug.Conn.send_resp(conn, 204, "")
        end
      end)

      assert {:error,
              %RedirectNotAllowed{
                status: ^status,
                url: "https://grades.example.com/lineitems/1/scores"
              } = error} = GradeService.post_score(client, score)

      expected_location = String.replace(destination, "secret@", "")
      assert error.location == expected_location
      assert Exception.message(error) =~ "HTTP #{status}"
      assert Exception.message(error) =~ "grades.example.com/lineitems/1/scores"
      assert Exception.message(error) =~ expected_location
      assert Exception.message(error) =~ "same HTTPS origin"
      refute Exception.message(error) =~ "secret"
      refute_receive {:redirect_reached, _, _, _, _}, 0
    end
  end

  test "pagination, OAuth assertions, and platform keys reject redirects before following them",
       %{
         client: client,
         registration: registration
       } do
    owner = self()

    for service <- [GradeService, MembershipsService, ClientCredentials, KeySet] do
      Req.Test.stub(service, fn conn ->
        if conn.host == "other.example.com" do
          send(owner, {:redirect_reached, service})
          Req.Test.json(conn, [])
        else
          conn
          |> Plug.Conn.put_resp_header("location", "https://other.example.com/redirected")
          |> Plug.Conn.send_resp(307, "")
        end
      end)
    end

    assert {:error, %RedirectNotAllowed{status: 307}} = GradeService.list_line_items(client)

    assert {:error, %RedirectNotAllowed{status: 307}} = MembershipsService.get_members(client)

    assert {:error, %RedirectNotAllowed{status: 307}} = MembershipsService.stream_members(client)

    assert {:error, %RedirectNotAllowed{status: 307}} =
             ClientCredentials.request_token(registration, [],
               req_options: [plug: {Req.Test, :ltix}, redirect: true]
             )

    assert {:error, %RedirectNotAllowed{status: 307} = error} =
             KeySet.get_key(registration, "kid",
               req_options: [plug: {Req.Test, :ltix}, redirect: true]
             )

    assert Exception.message(error) =~ "same HTTPS origin"
    refute_receive {:redirect_reached, _}
  end

  test "redirect diagnostics omit credentials and handle missing or invalid targets", %{
    client: client,
    score: score
  } do
    owner = self()

    for {location, expected_location} <- [
          {nil, nil},
          {"", nil},
          {"https://invalid.example.com:invalid/path?secret", nil},
          {"https://user:secret@other.example.com/final?token=secret#secret",
           "https://other.example.com/final"},
          {"https://grades.example.com:8443/final?token=secret#secret",
           "https://grades.example.com:8443/final"},
          {"https:///final?token=secret", "https:///final"},
          {"https://grades.example.com:70000/final?token=secret",
           "https://grades.example.com:70000/final"},
          {"//grades.example.com:invalid/final?token=secret", nil},
          {"https://[not-an-ip]/final?token=secret", nil},
          {"https://[::1/final?token=secret", nil}
        ] do
      Req.Test.stub(GradeService, fn conn ->
        send(owner, {:malformed_request, conn.host, conn.request_path})
        conn = if location, do: Plug.Conn.put_resp_header(conn, "location", location), else: conn
        Plug.Conn.send_resp(conn, 302, "secret-response-body")
      end)

      assert {:error,
              %RedirectNotAllowed{
                status: 302,
                url: "https://grades.example.com/lineitems/1/scores",
                location: ^expected_location
              } = error} =
               GradeService.post_score(client, score,
                 line_item: "https://grades.example.com/lineitems/1?token=secret#secret"
               )

      assert Exception.message(error) =~ "HTTP 302"
      assert Exception.message(error) =~ "same HTTPS origin"
      refute Exception.message(error) =~ "secret"
      refute inspect(error) =~ "secret"
      assert_receive {:malformed_request, "grades.example.com", "/lineitems/1/scores"}
      refute_receive {:malformed_request, _, _}, 0
    end
  end

  test "AGS follows a same-origin 307 redirect", %{
    client: client,
    score: score
  } do
    Req.Test.expect(GradeService, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/lineitems/1/scores"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body)["userId"] == "student"

      conn
      |> Plug.Conn.put_resp_header("location", "../final?redirect=secret")
      |> Plug.Conn.send_resp(307, "")
    end)

    Req.Test.expect(GradeService, fn conn ->
      assert conn.request_path == "/lineitems/final"
      assert conn.query_string == "redirect=secret"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer secret-bearer-token"]
      Plug.Conn.send_resp(conn, 204, "")
    end)

    assert :ok = GradeService.post_score(client, score)
    Req.Test.verify!(GradeService)
  end

  test "OAuth follows a same-origin 307 redirect", %{
    registration: registration
  } do
    status = 307

    Req.Test.expect(ClientCredentials, fn conn ->
      assert conn.method == "POST"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      form = URI.decode_query(body)
      assert form["grant_type"] == "client_credentials"
      assert byte_size(Map.fetch!(form, "client_assertion")) > 0

      conn
      |> Plug.Conn.put_resp_header("location", "/final-token")
      |> Plug.Conn.send_resp(status, "")
    end)

    Req.Test.expect(ClientCredentials, fn conn ->
      assert conn.request_path == "/final-token"
      assert conn.host == URI.parse(registration.token_endpoint).host

      Req.Test.json(conn, %{
        "access_token" => "redirected-token",
        "token_type" => "Bearer",
        "expires_in" => 3600
      })
    end)

    assert {:ok, %AccessToken{access_token: "redirected-token"}} =
             ClientCredentials.request_token(registration, [],
               req_options: [plug: {Req.Test, :ltix}]
             )

    Req.Test.verify!(ClientCredentials)
  end

  for status <- [303, 307] do
    test "AGS mutations follow #{status} with retrieval only for 303", %{client: client} do
      status = unquote(status)

      for method <- [:put, :delete] do
        owner = self()

        item = %LineItem{
          id: "https://grades.example.com/lineitems/1",
          label: "Updated quiz",
          score_maximum: 100
        }

        Req.Test.expect(GradeService, fn conn ->
          assert conn.method == String.upcase(to_string(method))
          assert conn.request_path == "/lineitems/1"
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(owner, {:mutation_body, body})

          if method == :put do
            assert Jason.decode!(body)["label"] == "Updated quiz"
          else
            assert body == ""
          end

          conn
          |> Plug.Conn.put_resp_header(
            "location",
            "HTTPS://GRADES.EXAMPLE.COM/final?redirect=secret"
          )
          |> Plug.Conn.send_resp(status, "")
        end)

        Req.Test.expect(GradeService, fn conn ->
          assert_receive {:mutation_body, original_body}
          assert conn.scheme == :https
          assert conn.host == "grades.example.com"
          assert conn.port == 443
          assert conn.request_path == "/final"
          assert conn.query_string == "redirect=secret"
          assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer secret-bearer-token"]
          {:ok, body, conn} = Plug.Conn.read_body(conn)

          if status == 303 do
            assert conn.method == "GET"
            assert body == ""
            assert Plug.Conn.get_req_header(conn, "content-type") == []
            assert Plug.Conn.get_req_header(conn, "content-length") == []
          else
            assert conn.method == String.upcase(to_string(method))
            assert body == original_body
          end

          send(owner, {:followed_mutation, conn.method, body})

          conn
          |> Plug.Conn.put_resp_header("location", "//GRADES.EXAMPLE.COM:443/retrieved")
          |> Plug.Conn.send_resp(307, "")
        end)

        Req.Test.expect(GradeService, fn conn ->
          assert_receive {:followed_mutation, followed_method, followed_body}
          assert conn.method == followed_method
          assert conn.request_path == "/retrieved"
          assert conn.query_string == ""
          assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer secret-bearer-token"]
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert body == followed_body

          Req.Test.json(conn, %{
            "id" => item.id,
            "label" => "Retrieved quiz",
            "scoreMaximum" => 100
          })
        end)

        case method do
          :put ->
            assert {:ok, %LineItem{label: "Retrieved quiz"}} =
                     GradeService.update_line_item(client, item)

          :delete ->
            assert :ok = GradeService.delete_line_item(client, item, force: true)
        end

        Req.Test.verify!(GradeService)
      end
    end
  end

  test "safe asynchronous redirects cancel the old body and reach the final endpoint", %{
    client: client,
    score: score
  } do
    owner = self()

    score = %{
      score
      | timestamp: ~U[2024-01-02 03:04:05.678Z],
        score_given: 87.5,
        score_maximum: 100,
        comment: "Async score"
    }

    Req.Test.expect(GradeService, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(body) == %{
               "userId" => "student",
               "timestamp" => "2024-01-02T03:04:05.678000Z",
               "activityProgress" => "Completed",
               "gradingProgress" => "FullyGraded",
               "scoreGiven" => 87.5,
               "scoreMaximum" => 100,
               "comment" => "Async score"
             }

      send(owner, {:asynchronous_score_body, body})
      send(owner, {:asynchronous_request, conn.host, conn.request_path})

      conn
      |> Plug.Conn.put_resp_header("location", "/final?secret-target")
      |> Plug.Conn.send_resp(307, "secret-response-body")
    end)

    Req.Test.expect(GradeService, fn conn ->
      assert conn.host == "grades.example.com"
      assert conn.request_path == "/final"
      assert conn.query_string == "secret-target"
      assert conn.method == "POST"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer secret-bearer-token"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert_receive {:asynchronous_score_body, original_body}
      assert body == original_body
      send(owner, {:asynchronous_request, conn.host, conn.request_path})
      Plug.Conn.send_resp(conn, 204, "")
    end)

    client = %{client | req_options: Keyword.put(client.req_options, :into, :self)}

    assert :ok = GradeService.post_score(client, score)
    assert_receive {:asynchronous_request, "grades.example.com", "/lineitems/1/scores"}
    assert_receive {:asynchronous_request, "grades.example.com", "/final"}
    refute_receive {_, {:data, "secret-response-body"}}, 0
    Req.Test.verify!(GradeService)
  end

  test "unsafe asynchronous redirects stop without orphaning the old response", %{
    client: client,
    score: score
  } do
    owner = self()

    Req.Test.stub(GradeService, fn conn ->
      send(owner, {:asynchronous_request, conn.host, conn.request_path})

      conn
      |> Plug.Conn.put_resp_header(
        "location",
        "https://user:secret-user@unsafe.example.com/steal?secret-target"
      )
      |> Plug.Conn.send_resp(307, "secret-response-body")
    end)

    client = %{client | req_options: Keyword.put(client.req_options, :into, :self)}

    assert {:error, %RedirectNotAllowed{status: 307} = error} =
             GradeService.post_score(client, score)

    refute inspect(error) =~ "secret"
    assert_receive {:asynchronous_request, "grades.example.com", "/lineitems/1/scores"}
    refute_receive _, 0
  end

  test "asynchronous redirect loops stop at the configured limit without leaking old bodies", %{
    client: client,
    score: score
  } do
    owner = self()

    Req.Test.stub(GradeService, fn conn ->
      send(owner, {:asynchronous_request, conn.host, conn.request_path})

      conn
      |> Plug.Conn.put_resp_header("location", "/loop?secret-target")
      |> Plug.Conn.send_resp(307, "secret-response-body")
    end)

    client = %{
      client
      | req_options: Keyword.merge(client.req_options, into: :self, max_redirects: 2)
    }

    assert {:error, error} = GradeService.post_score(client, score)
    refute inspect(error) =~ "secret"
    assert_receive {:asynchronous_request, "grades.example.com", "/lineitems/1/scores"}
    assert_receive {:asynchronous_request, "grades.example.com", "/loop"}
    assert_receive {:asynchronous_request, "grades.example.com", "/loop"}
    refute_receive _, 0
  end

  test "redirected AGS and JWKS server failures retain their error contracts", %{
    client: client,
    registration: registration
  } do
    Req.Test.expect(GradeService, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "/unavailable")
      |> Plug.Conn.send_resp(302, "")
    end)

    Req.Test.expect(GradeService, fn conn ->
      assert conn.request_path == "/unavailable"
      Plug.Conn.send_resp(conn, 500, "Service unavailable")
    end)

    assert {:error, %TransportError{status: 500, body: "Service unavailable"}} =
             GradeService.get_line_item(client)

    Req.Test.verify!(GradeService)

    Req.Test.expect(KeySet, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "/unavailable")
      |> Plug.Conn.send_resp(302, "")
    end)

    Req.Test.expect(KeySet, fn conn ->
      assert conn.request_path == "/unavailable"
      Plug.Conn.send_resp(conn, 500, "Service unavailable")
    end)

    assert {:error, %Unknown.Unknown{error: "JWKS fetch returned HTTP 500"}} =
             KeySet.get_key(registration, "missing",
               req_options: [plug: {Req.Test, :ltix}, retry: false]
             )

    Req.Test.verify!(KeySet)
  end

  test "relative redirects resolve against the parameterized URL without reapplying filters", %{
    client: client
  } do
    for {target, path, query} <- [
          {"/final?new=2", "/final", "new=2"},
          {"../final", "/final", ""},
          {"//GRADES.EXAMPLE.COM:443/final", "/final", ""},
          {"HTTPS://GRADES.EXAMPLE.COM:443/final", "/final", ""},
          {"?new=2", "/lineitems/1", "new=2"},
          {"#fragment", "/lineitems/1", "filter=secret"}
        ] do
      Req.Test.expect(GradeService, fn conn ->
        assert conn.query_string == "filter=secret"

        conn
        |> Plug.Conn.put_resp_header("location", target)
        |> Plug.Conn.send_resp(302, "")
      end)

      Req.Test.expect(GradeService, fn conn ->
        assert conn.scheme == :https
        assert conn.host == "grades.example.com"
        assert conn.port == 443
        assert conn.request_path == path
        assert conn.query_string == query
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer secret-bearer-token"]

        Req.Test.json(conn, %{
          "id" => "https://grades.example.com/final",
          "label" => "Redirected quiz",
          "scoreMaximum" => 100
        })
      end)

      filtered_client = %{
        client
        | req_options: Keyword.put(client.req_options, :params, filter: "secret")
      }

      assert {:ok, %LineItem{label: "Redirected quiz"}} =
               GradeService.get_line_item(filtered_client)

      Req.Test.verify!(GradeService)
    end
  end

  test "every redirect hop is guarded before OAuth assertion delivery", %{
    registration: registration
  } do
    owner = self()

    Req.Test.stub(ClientCredentials, fn conn ->
      send(owner, {:oauth_request, conn.host, conn.request_path})
      assert conn.host != "unsafe.example.com"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      form = URI.decode_query(body)
      assert byte_size(Map.fetch!(form, "client_assertion")) > 0

      destination =
        if conn.request_path == "/safe-token",
          do: "https://user:secret@unsafe.example.com/steal?token=secret",
          else: "/safe-token"

      conn
      |> Plug.Conn.put_resp_header("location", destination)
      |> Plug.Conn.send_resp(307, "")
    end)

    assert {:error, %RedirectNotAllowed{url: url, location: location} = error} =
             ClientCredentials.request_token(registration, [],
               req_options: [plug: {Req.Test, :ltix}, redirect_trusted: true]
             )

    assert url == "https://platform.example.com/safe-token"
    assert location == "https://unsafe.example.com/steal"
    refute inspect(error) =~ "secret"
    assert_receive {:oauth_request, "platform.example.com", "/token"}
    assert_receive {:oauth_request, "platform.example.com", "/safe-token"}
    refute_receive {:oauth_request, _, _}, 0
  end

  test "redirect loops stop after the configured bounded number of requests", %{
    client: client,
    score: score
  } do
    owner = self()

    Req.Test.stub(GradeService, fn conn ->
      send(owner, {:loop_request, conn.request_path})

      conn
      |> Plug.Conn.put_resp_header("location", "/loop")
      |> Plug.Conn.send_resp(307, "")
    end)

    client = %{client | req_options: Keyword.put(client.req_options, :max_redirects, 2)}
    assert {:error, error} = GradeService.post_score(client, score)
    assert Exception.message(error) =~ "too many redirects"
    assert_receive {:loop_request, "/lineitems/1/scores"}
    assert_receive {:loop_request, "/loop"}
    assert_receive {:loop_request, "/loop"}
    refute_receive {:loop_request, _}, 0
  end

  test "redirect logs and diagnostics never expose query secrets or target credentials", %{
    client: client,
    score: score
  } do
    owner = self()

    Req.Test.expect(GradeService, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "/final?redirect=secret-target")
      |> Plug.Conn.send_resp(307, "")
    end)

    Req.Test.expect(GradeService, fn conn ->
      assert conn.query_string == "redirect=secret-target"

      conn
      |> Plug.Conn.put_resp_header(
        "location",
        "https://user:secret-user@other.example.com/steal?secret-query"
      )
      |> Plug.Conn.send_resp(307, "")
    end)

    client = %{
      client
      | req_options: Keyword.put(client.req_options, :redirect_log_level, :warning)
    }

    logs =
      ExUnit.CaptureLog.capture_log(fn ->
        result =
          GradeService.post_score(client, score,
            line_item: "https://grades.example.com/lineitems/1?source=secret-source"
          )

        send(owner, {:logged_result, result})
      end)

    assert_receive {:logged_result, {:error, %RedirectNotAllowed{} = error}}
    refute logs =~ "secret"
    refute inspect(error) =~ "secret"
    Req.Test.verify!(GradeService)
  end

  test "JWKS redirects permit a complete callback launch", %{platform: platform} do
    {:ok, pid} =
      StorageAdapter.start_link(
        registrations: [platform.registration],
        deployments: [platform.deployment]
      )

    StorageAdapter.set_pid(pid)
    owner = self()

    Req.Test.expect(KeySet, fn conn ->
      send(owner, {:keys_request, conn.request_path})

      conn
      |> Plug.Conn.put_resp_header("location", "/keys/current")
      |> Plug.Conn.send_resp(302, "")
    end)

    Req.Test.expect(KeySet, fn conn ->
      assert conn.host == "platform.example.com"
      assert conn.request_path == "/keys/current"
      assert conn.method == "GET"
      assert Plug.Conn.get_req_header(conn, "authorization") == []
      Req.Test.json(conn, platform.jwks)
    end)

    assert {:ok, login} =
             Ltix.handle_login(
               Ltix.Test.login_params(platform),
               "https://tool.example.com/launch",
               storage_adapter: StorageAdapter
             )

    params =
      Ltix.Test.launch_params(platform,
        nonce: Ltix.Test.extract_nonce(login.redirect_uri),
        state: login.state
      )

    assert {:ok, %LaunchContext{claims: %{subject: "user-12345"}}} =
             Ltix.handle_callback(params, login.state,
               storage_adapter: StorageAdapter,
               req_options: [plug: {Req.Test, :ltix}]
             )

    initial_path = URI.parse(platform.registration.jwks_uri).path
    assert_receive {:keys_request, ^initial_path}
    Req.Test.verify!(KeySet)
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

  test "rejects explicitly disabled certificate verification before sending credentials", %{
    client: client,
    score: score,
    registration: registration
  } do
    owner = self()

    for service <- [GradeService, ClientCredentials] do
      Req.Test.stub(service, fn conn ->
        send(owner, {:reached, service})
        Plug.Conn.send_resp(conn, 204, "")
      end)
    end

    for tls_options <- [
          [connect_options: [transport_opts: [verify: :verify_none]]],
          [finch: [conn_opts: [transport_opts: [verify: :verify_none]]]]
        ] do
      request_options = Keyword.merge(client.req_options, tls_options)
      client = %{client | req_options: request_options}
      assert {:error, %TransportError{} = error} = GradeService.post_score(client, score)
      assert Exception.message(error) =~ "certificate verification"

      assert {:error, %TransportError{}} =
               ClientCredentials.request_token(registration, [], req_options: request_options)

      refute_receive {:reached, _}, 0
    end
  end

  test "custom certificate authorities remain usable with strict verification", %{
    client: client,
    score: score
  } do
    configuration = certificate_configuration()

    certificate_file =
      Path.join(
        System.tmp_dir!(),
        "ltix-certificates-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}.pem"
      )

    certificates = Enum.map(configuration[:cacerts], &{:Certificate, &1, :not_encrypted})
    File.write!(certificate_file, :public_key.pem_encode(certificates))
    on_exit(fn -> File.rm!(certificate_file) end)

    for tls_options <- [
          [connect_options: [transport_opts: [cacerts: configuration[:cacerts]]]],
          [
            finch: [
              conn_opts: [transport_opts: [verify: :verify_peer, cacertfile: certificate_file]]
            ]
          ]
        ] do
      {url, server} = start_https_endpoint(configuration)
      client = %{client | req_options: Keyword.put(tls_options, :retry, false)}
      assert :ok = GradeService.post_score(client, score, line_item: url)
      assert {:ok, request} = Task.await(server)
      assert request =~ "POST /lineitems/1/scores HTTP/1.1"
      assert request =~ "authorization: Bearer secret-bearer-token"
    end
  end

  test "default HTTP configuration rejects an untrusted server before sending credentials", %{
    client: client,
    score: score
  } do
    {url, server} = start_https_endpoint(certificate_configuration())
    client = %{client | req_options: [retry: false]}
    assert {:error, error} = GradeService.post_score(client, score, line_item: url)
    assert Exception.message(error) =~ "Unknown CA"
    assert {:error, _handshake_error} = Task.await(server)
  end

  defp certificate_configuration do
    :public_key.pkix_test_data(%{
      root: [key: {:rsa, 2048, 65_537}, digest: :sha256],
      intermediates: [],
      peer: [
        key: {:rsa, 2048, 65_537},
        digest: :sha256,
        extensions: [{:Extension, {2, 5, 29, 17}, false, [{:iPAddress, <<127, 0, 0, 1>>}]}]
      ]
    })
  end

  defp start_https_endpoint(configuration) do
    opts = Keyword.merge(configuration, ip: {127, 0, 0, 1}, active: false, mode: :binary)
    {:ok, listener} = :ssl.listen(0, opts)
    on_exit(fn -> :ssl.close(listener) end)
    {:ok, {_address, port}} = :ssl.sockname(listener)

    server =
      Task.async(fn ->
        with {:ok, socket} <- :ssl.transport_accept(listener, 5000),
             {:ok, socket} <- :ssl.handshake(socket, 5000),
             {:ok, request} <- :ssl.recv(socket, 0, 5000) do
          :ok =
            :ssl.send(
              socket,
              "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            )

          :ssl.close(socket)
          {:ok, request}
        end
      end)

    {"https://127.0.0.1:#{port}/lineitems/1", server}
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
