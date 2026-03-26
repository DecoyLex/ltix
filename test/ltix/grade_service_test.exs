defmodule Ltix.GradeServiceTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.CoupledLineItem
  alias Ltix.Errors.Invalid.InvalidEndpoint
  alias Ltix.Errors.Invalid.ScopeMismatch
  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.Errors.Security.AccessTokenExpired
  alias Ltix.GradeService
  alias Ltix.GradeService.LineItem
  alias Ltix.GradeService.Result
  alias Ltix.GradeService.Score
  alias Ltix.LaunchClaims
  alias Ltix.LaunchClaims.AgsEndpoint
  alias Ltix.OAuth.Client

  @scope_lineitem "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem"
  @scope_lineitem_readonly "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem.readonly"
  @scope_result_readonly "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly"
  @scope_score "https://purl.imsglobal.org/spec/lti-ags/scope/score"

  @all_scopes [@scope_lineitem, @scope_result_readonly, @scope_score]

  @lineitems_url "https://platform.example.com/context/2923/lineitems"
  @lineitem_url "https://platform.example.com/context/2923/lineitems/1/lineitem"

  @lineitem_media_type "application/vnd.ims.lis.v2.lineitem+json"
  @lineitem_container_media_type "application/vnd.ims.lis.v2.lineitemcontainer+json"
  @result_container_media_type "application/vnd.ims.lis.v2.resultcontainer+json"
  @score_media_type "application/vnd.ims.lis.v1.score+json"

  setup do
    platform = Ltix.Test.setup_platform!()
    %{platform: platform}
  end

  defp req_options, do: [plug: {Req.Test, Ltix.GradeService}, retry: false]

  defp stub_token_response(scopes \\ @all_scopes) do
    Ltix.Test.stub_token_response(
      scopes: scopes,
      access_token: "test-ags-token"
    )
  end

  defp build_client(platform, opts \\ []) do
    endpoint =
      Keyword.get(opts, :endpoint, %AgsEndpoint{
        lineitems: @lineitems_url,
        lineitem: @lineitem_url,
        scope: @all_scopes
      })

    scopes = Keyword.get(opts, :scopes, @all_scopes)
    expires_at = Keyword.get(opts, :expires_at, DateTime.add(DateTime.utc_now(), 3600))

    %Client{
      access_token: "test-ags-token",
      expires_at: expires_at,
      scopes: MapSet.new(scopes),
      registration: platform.registration,
      req_options: req_options(),
      endpoints: %{GradeService => endpoint}
    }
  end

  defp build_line_item_json(opts \\ []) do
    %{
      "id" => Keyword.get(opts, :id, "#{@lineitems_url}/1/lineitem"),
      "label" => Keyword.get(opts, :label, "Chapter 5 Test"),
      "scoreMaximum" => Keyword.get(opts, :score_maximum, 100)
    }
  end

  defp build_result_json(user_id, opts) do
    result = %{"userId" => user_id}

    result
    |> maybe_put("resultScore", Keyword.get(opts, :result_score))
    |> maybe_put("resultMaximum", Keyword.get(opts, :result_maximum))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # --- AdvantageService callbacks ---

  describe "AdvantageService callbacks" do
    test "endpoint_from_claims extracts AGS endpoint" do
      claims = %LaunchClaims{
        ags_endpoint: %AgsEndpoint{
          lineitems: @lineitems_url,
          scope: @all_scopes
        }
      }

      assert {:ok, %AgsEndpoint{}} = GradeService.endpoint_from_claims(claims)
    end

    test "endpoint_from_claims returns :error when no endpoint" do
      claims = %LaunchClaims{}
      assert :error == GradeService.endpoint_from_claims(claims)
    end

    test "validate_endpoint accepts AgsEndpoint" do
      assert :ok == GradeService.validate_endpoint(%AgsEndpoint{})
    end

    test "validate_endpoint rejects other values" do
      assert {:error, %InvalidEndpoint{}} =
               GradeService.validate_endpoint(:not_an_endpoint)
    end

    test "scopes returns scope array from endpoint" do
      endpoint = %AgsEndpoint{scope: @all_scopes}
      assert @all_scopes == GradeService.scopes(endpoint)
    end

    test "scopes returns empty list when scope is nil" do
      endpoint = %AgsEndpoint{scope: nil}
      assert [] == GradeService.scopes(endpoint)
    end
  end

  # --- authenticate/2 ---

  describe "authenticate/2 from LaunchContext" do
    test "acquires token with AGS scopes from claim", ctx do
      stub_token_response()

      context =
        Ltix.Test.build_launch_context(ctx.platform,
          ags_endpoint: %AgsEndpoint{
            lineitems: @lineitems_url,
            lineitem: @lineitem_url,
            scope: @all_scopes
          }
        )

      assert {:ok, %Client{} = client} =
               GradeService.authenticate(context,
                 req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
               )

      assert %AgsEndpoint{} = client.endpoints[GradeService]
    end

    test "errors when no AGS claim in launch", ctx do
      context = Ltix.Test.build_launch_context(ctx.platform)

      assert {:error, %ServiceNotAvailable{}} =
               GradeService.authenticate(context)
    end
  end

  describe "authenticate/2 from Registration" do
    test "acquires token with endpoint option", ctx do
      stub_token_response()

      endpoint = %AgsEndpoint{
        lineitems: @lineitems_url,
        scope: @all_scopes
      }

      assert {:ok, %Client{} = client} =
               GradeService.authenticate(ctx.platform.registration,
                 endpoint: endpoint,
                 req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
               )

      assert %AgsEndpoint{} = client.endpoints[GradeService]
    end

    test "errors without endpoint option", ctx do
      assert_raise Zoi.ParseError, fn ->
        GradeService.authenticate(ctx.platform.registration, [])
      end
    end

    test "accepts a custom Registerable struct", _ctx do
      stub_token_response()

      custom_registration = %CustomRegistration{
        id: "reg-001",
        tenant_id: "tenant-1",
        platform_issuer: "https://custom-lms.example.com",
        oauth_client_id: "custom-tool-client",
        oidc_auth_url: "https://custom-lms.example.com/auth",
        platform_jwks_url: "https://custom-lms.example.com/.well-known/jwks.json",
        platform_token_url: "https://custom-lms.example.com/token",
        signing_key: Ltix.JWK.generate()
      }

      endpoint = %AgsEndpoint{
        lineitems: @lineitems_url,
        scope: @all_scopes
      }

      assert {:ok, %Client{} = client} =
               GradeService.authenticate(custom_registration,
                 endpoint: endpoint,
                 req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
               )

      assert client.registration.issuer == "https://custom-lms.example.com"
      assert client.registration.client_id == "custom-tool-client"
    end
  end

  # --- list_line_items/2 ---

  describe "list_line_items/2" do
    test "fetches all line items from container", ctx do
      items = [
        build_line_item_json(id: "#{@lineitems_url}/1", label: "Quiz 1"),
        build_line_item_json(id: "#{@lineitems_url}/2", label: "Quiz 2")
      ]

      Req.Test.stub(Ltix.GradeService, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type(@lineitem_container_media_type)
        |> Req.Test.json(items)
      end)

      client = build_client(ctx.platform)

      assert {:ok, [%LineItem{}, %LineItem{}]} = GradeService.list_line_items(client)
    end

    test "sends correct Accept header", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        [accept] = Plug.Conn.get_req_header(conn, "accept")
        assert accept == @lineitem_container_media_type

        conn
        |> Plug.Conn.put_resp_content_type(@lineitem_container_media_type)
        |> Req.Test.json([])
      end)

      client = build_client(ctx.platform)
      assert {:ok, []} = GradeService.list_line_items(client)
    end

    test "passes filter query parameters", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["resource_link_id"] == "rl-123"
        assert params["resource_id"] == "res-456"
        assert params["tag"] == "grade"

        conn
        |> Plug.Conn.put_resp_content_type(@lineitem_container_media_type)
        |> Req.Test.json([])
      end)

      client = build_client(ctx.platform)

      assert {:ok, []} =
               GradeService.list_line_items(client,
                 resource_link_id: "rl-123",
                 resource_id: "res-456",
                 tag: "grade"
               )
    end

    test "follows rel=next pagination", ctx do
      counter = :counters.new(1, [:atomics])

      Req.Test.stub(Ltix.GradeService, fn conn ->
        page = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)

        {body, next_url} =
          case page do
            0 ->
              {[build_line_item_json(id: "#{@lineitems_url}/1", label: "Quiz 1")],
               "#{@lineitems_url}?p=2"}

            _ ->
              {[build_line_item_json(id: "#{@lineitems_url}/2", label: "Quiz 2")], nil}
          end

        conn = Plug.Conn.put_resp_content_type(conn, @lineitem_container_media_type)

        conn =
          if next_url do
            Plug.Conn.put_resp_header(conn, "link", "<#{next_url}>; rel=\"next\"")
          else
            conn
          end

        Req.Test.json(conn, body)
      end)

      client = build_client(ctx.platform)

      assert {:ok, items} = GradeService.list_line_items(client)
      assert length(items) == 2
    end

    test "returns error when lineitems URL not available", ctx do
      endpoint = %AgsEndpoint{lineitems: nil, lineitem: @lineitem_url, scope: @all_scopes}
      client = build_client(ctx.platform, endpoint: endpoint)

      assert {:error, %ServiceNotAvailable{}} = GradeService.list_line_items(client)
    end

    test "returns ScopeMismatch when client lacks lineitem scope", ctx do
      client = build_client(ctx.platform, scopes: [@scope_score])

      assert {:error, %ScopeMismatch{}} = GradeService.list_line_items(client)
    end

    test "returns AccessTokenExpired when token is expired", ctx do
      client =
        build_client(ctx.platform, expires_at: DateTime.add(DateTime.utc_now(), -120))

      assert {:error, %AccessTokenExpired{}} = GradeService.list_line_items(client)
    end
  end

  # --- get_line_item/2 ---

  describe "get_line_item/2" do
    test "fetches line item from explicit URL", ctx do
      item_json = build_line_item_json()

      Req.Test.stub(Ltix.GradeService, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type(@lineitem_media_type)
        |> Req.Test.json(item_json)
      end)

      client = build_client(ctx.platform)

      assert {:ok, %LineItem{label: "Chapter 5 Test"}} =
               GradeService.get_line_item(client, line_item: @lineitem_url)
    end

    test "uses endpoint lineitem URL when no option given", ctx do
      item_json = build_line_item_json()

      Req.Test.stub(Ltix.GradeService, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type(@lineitem_media_type)
        |> Req.Test.json(item_json)
      end)

      client = build_client(ctx.platform)

      assert {:ok, %LineItem{}} = GradeService.get_line_item(client)
    end

    test "returns error when no URL available", ctx do
      endpoint = %AgsEndpoint{lineitems: @lineitems_url, lineitem: nil, scope: @all_scopes}
      client = build_client(ctx.platform, endpoint: endpoint)

      assert {:error, %ServiceNotAvailable{}} = GradeService.get_line_item(client)
    end

    test "returns ScopeMismatch without lineitem scope", ctx do
      client = build_client(ctx.platform, scopes: [@scope_score])

      assert {:error, %ScopeMismatch{}} = GradeService.get_line_item(client)
    end
  end

  # --- create_line_item/2 ---

  describe "create_line_item/2" do
    test "creates line item and returns parsed response", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        json = Ltix.AppConfig.json_library!().decode!(body)
        assert json["label"] == "Quiz 1"
        assert json["scoreMaximum"] == 100

        response = Map.put(json, "id", "#{@lineitems_url}/new")

        conn
        |> Plug.Conn.put_resp_content_type(@lineitem_media_type)
        |> Plug.Conn.send_resp(201, Ltix.AppConfig.json_library!().encode!(response))
      end)

      client = build_client(ctx.platform)

      assert {:ok, %LineItem{} = item} =
               GradeService.create_line_item(client, label: "Quiz 1", score_maximum: 100)

      assert item.id == "#{@lineitems_url}/new"
      assert item.label == "Quiz 1"
    end

    test "sends correct Content-Type", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        [content_type] = Plug.Conn.get_req_header(conn, "content-type")
        assert content_type =~ @lineitem_media_type

        response = build_line_item_json()

        conn
        |> Plug.Conn.put_resp_content_type(@lineitem_media_type)
        |> Plug.Conn.send_resp(201, Ltix.AppConfig.json_library!().encode!(response))
      end)

      client = build_client(ctx.platform)
      assert {:ok, _} = GradeService.create_line_item(client, label: "Quiz 1", score_maximum: 100)
    end

    test "returns error when lineitems URL not available", ctx do
      endpoint = %AgsEndpoint{lineitems: nil, lineitem: @lineitem_url, scope: @all_scopes}
      client = build_client(ctx.platform, endpoint: endpoint)

      assert {:error, %ServiceNotAvailable{}} =
               GradeService.create_line_item(client, label: "Quiz 1", score_maximum: 100)
    end

    test "returns ScopeMismatch with only lineitem.readonly", ctx do
      client = build_client(ctx.platform, scopes: [@scope_lineitem_readonly])

      assert {:error, %ScopeMismatch{}} =
               GradeService.create_line_item(client, label: "Quiz 1", score_maximum: 100)
    end

    test "returns validation error when label missing", ctx do
      client = build_client(ctx.platform)

      assert {:error, _} = GradeService.create_line_item(client, score_maximum: 100)
    end

    test "returns validation error when score_maximum missing", ctx do
      client = build_client(ctx.platform)

      assert {:error, _} = GradeService.create_line_item(client, label: "Quiz 1")
    end
  end

  # --- update_line_item/2 ---

  describe "update_line_item/2" do
    test "PUTs full line item to its id URL", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert conn.method == "PUT"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        json = Ltix.AppConfig.json_library!().decode!(body)
        assert json["label"] == "Updated Quiz"
        assert json["id"] == "#{@lineitems_url}/1/lineitem"

        conn
        |> Plug.Conn.put_resp_content_type(@lineitem_media_type)
        |> Req.Test.json(json)
      end)

      client = build_client(ctx.platform)

      item = %LineItem{
        id: "#{@lineitems_url}/1/lineitem",
        label: "Updated Quiz",
        score_maximum: 100
      }

      assert {:ok, %LineItem{label: "Updated Quiz"}} =
               GradeService.update_line_item(client, item)
    end

    test "returns error when line item has no id", ctx do
      client = build_client(ctx.platform)
      item = %LineItem{label: "Quiz 1", score_maximum: 100}

      assert {:error, _} = GradeService.update_line_item(client, item)
    end

    test "returns ScopeMismatch without lineitem scope", ctx do
      client = build_client(ctx.platform, scopes: [@scope_lineitem_readonly])

      item = %LineItem{id: @lineitem_url, label: "Quiz 1", score_maximum: 100}

      assert {:error, %ScopeMismatch{}} = GradeService.update_line_item(client, item)
    end
  end

  # --- delete_line_item/3 ---

  describe "delete_line_item/3" do
    test "deletes line item by struct", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert conn.method == "DELETE"
        Plug.Conn.send_resp(conn, 204, "")
      end)

      client = build_client(ctx.platform)
      item = %LineItem{id: "#{@lineitems_url}/99/lineitem"}

      assert :ok = GradeService.delete_line_item(client, item)
    end

    test "deletes line item by URL string", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert conn.method == "DELETE"
        Plug.Conn.send_resp(conn, 204, "")
      end)

      client = build_client(ctx.platform)

      assert :ok = GradeService.delete_line_item(client, "#{@lineitems_url}/99/lineitem")
    end

    test "returns CoupledLineItem when URL matches endpoint lineitem", ctx do
      client = build_client(ctx.platform)

      assert {:error, %CoupledLineItem{}} =
               GradeService.delete_line_item(client, @lineitem_url)
    end

    test "succeeds with force: true when URL matches endpoint lineitem", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert conn.method == "DELETE"
        Plug.Conn.send_resp(conn, 204, "")
      end)

      client = build_client(ctx.platform)

      assert :ok = GradeService.delete_line_item(client, @lineitem_url, force: true)
    end

    test "no guard when endpoint has no lineitem URL", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        Plug.Conn.send_resp(conn, 204, "")
      end)

      endpoint = %AgsEndpoint{lineitems: @lineitems_url, lineitem: nil, scope: @all_scopes}
      client = build_client(ctx.platform, endpoint: endpoint)

      assert :ok = GradeService.delete_line_item(client, "#{@lineitems_url}/99/lineitem")
    end

    test "returns ScopeMismatch without lineitem scope", ctx do
      client = build_client(ctx.platform, scopes: [@scope_lineitem_readonly])

      assert {:error, %ScopeMismatch{}} =
               GradeService.delete_line_item(client, "#{@lineitems_url}/99/lineitem")
    end
  end

  # --- post_score/3 ---

  describe "post_score/3" do
    setup do
      {:ok, score} =
        Score.new(
          user_id: "user-123",
          score_given: 85,
          score_maximum: 100,
          activity_progress: :completed,
          grading_progress: :fully_graded
        )

      %{score: score}
    end

    test "posts to {lineitem}/scores using endpoint lineitem", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path =~ "/scores"

        Plug.Conn.send_resp(conn, 200, "")
      end)

      client = build_client(ctx.platform)

      assert :ok = GradeService.post_score(client, ctx.score)
    end

    test "posts to explicit line item URL", ctx do
      explicit_url = "#{@lineitems_url}/42/lineitem"

      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert conn.request_path =~ "/42/lineitem/scores"
        Plug.Conn.send_resp(conn, 200, "")
      end)

      client = build_client(ctx.platform)
      item = %LineItem{id: explicit_url}

      assert :ok = GradeService.post_score(client, ctx.score, line_item: item)
    end

    test "sends correct Content-Type", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        [content_type] = Plug.Conn.get_req_header(conn, "content-type")
        assert content_type =~ @score_media_type

        Plug.Conn.send_resp(conn, 200, "")
      end)

      client = build_client(ctx.platform)

      assert :ok = GradeService.post_score(client, ctx.score)
    end

    test "returns :ok on HTTP 204", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        Plug.Conn.send_resp(conn, 204, "")
      end)

      client = build_client(ctx.platform)

      assert :ok = GradeService.post_score(client, ctx.score)
    end

    test "returns ScopeMismatch without score scope", ctx do
      client = build_client(ctx.platform, scopes: [@scope_lineitem])

      assert {:error, %ScopeMismatch{}} = GradeService.post_score(client, ctx.score)
    end

    test "returns error when no line item URL available", ctx do
      endpoint = %AgsEndpoint{lineitems: @lineitems_url, lineitem: nil, scope: @all_scopes}
      client = build_client(ctx.platform, endpoint: endpoint)

      assert {:error, %ServiceNotAvailable{}} = GradeService.post_score(client, ctx.score)
    end
  end

  # --- get_results/2 ---

  describe "get_results/2" do
    test "fetches results from {lineitem}/results using endpoint lineitem", ctx do
      results = [
        build_result_json("user-1", result_score: 0.83, result_maximum: 1),
        build_result_json("user-2", result_score: 0.95, result_maximum: 1)
      ]

      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert conn.request_path =~ "/results"

        conn
        |> Plug.Conn.put_resp_content_type(@result_container_media_type)
        |> Req.Test.json(results)
      end)

      client = build_client(ctx.platform)

      assert {:ok, [%Result{}, %Result{}]} = GradeService.get_results(client)
    end

    test "fetches results for explicit line item", ctx do
      explicit_url = "#{@lineitems_url}/42/lineitem"

      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert conn.request_path =~ "/42/lineitem/results"

        conn
        |> Plug.Conn.put_resp_content_type(@result_container_media_type)
        |> Req.Test.json([])
      end)

      client = build_client(ctx.platform)

      assert {:ok, _results} =
               GradeService.get_results(client, line_item: explicit_url)
    end

    test "filters by user_id query parameter", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["user_id"] == "user-123"

        conn
        |> Plug.Conn.put_resp_content_type(@result_container_media_type)
        |> Req.Test.json([build_result_json("user-123", result_score: 0.9)])
      end)

      client = build_client(ctx.platform)

      assert {:ok, _results} =
               GradeService.get_results(client, user_id: "user-123")
    end

    test "follows rel=next pagination", ctx do
      counter = :counters.new(1, [:atomics])

      Req.Test.stub(Ltix.GradeService, fn conn ->
        page = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)

        {body, next_url} =
          case page do
            0 ->
              {[build_result_json("user-1", result_score: 0.8)], "#{@lineitem_url}/results?p=2"}

            _ ->
              {[build_result_json("user-2", result_score: 0.9)], nil}
          end

        conn = Plug.Conn.put_resp_content_type(conn, @result_container_media_type)

        conn =
          if next_url do
            Plug.Conn.put_resp_header(conn, "link", "<#{next_url}>; rel=\"next\"")
          else
            conn
          end

        Req.Test.json(conn, body)
      end)

      client = build_client(ctx.platform)

      assert {:ok, results} = GradeService.get_results(client)
      assert length(results) == 2
    end

    test "sends correct Accept header", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        [accept] = Plug.Conn.get_req_header(conn, "accept")
        assert accept == @result_container_media_type

        conn
        |> Plug.Conn.put_resp_content_type(@result_container_media_type)
        |> Req.Test.json([])
      end)

      client = build_client(ctx.platform)
      assert {:ok, _} = GradeService.get_results(client)
    end

    test "returns ScopeMismatch without result.readonly scope", ctx do
      client = build_client(ctx.platform, scopes: [@scope_lineitem])

      assert {:error, %ScopeMismatch{}} = GradeService.get_results(client)
    end

    test "returns error when no line item URL available", ctx do
      endpoint = %AgsEndpoint{lineitems: @lineitems_url, lineitem: nil, scope: @all_scopes}
      client = build_client(ctx.platform, endpoint: endpoint)

      assert {:error, %ServiceNotAvailable{}} = GradeService.get_results(client)
    end
  end
end
