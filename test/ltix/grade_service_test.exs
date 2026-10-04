defmodule Ltix.GradeServiceTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.CoupledLineItem
  alias Ltix.Errors.Invalid.InvalidEndpoint
  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.Errors.Invalid.InvalidOption
  alias Ltix.Errors.Invalid.MissingLineItemId
  alias Ltix.Errors.Invalid.ScopeMismatch
  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.Errors.Security.AccessTokenExpired
  alias Ltix.GradeService
  alias Ltix.GradeService.LineItem
  alias Ltix.GradeService.Result
  alias Ltix.GradeService.Score
  alias Ltix.LaunchClaims
  alias Ltix.LaunchClaims.AGSEndpoint
  alias Ltix.OAuth.Client

  @scope_lineitem "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem"
  @scope_lineitem_readonly "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem.readonly"
  @scope_result_readonly "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly"
  @scope_score "https://purl.imsglobal.org/spec/lti-ags/scope/score"

  @all_scopes [@scope_lineitem, @scope_result_readonly, @scope_score]

  @line_items_url "https://platform.example.com/context/2923/lineitems"
  @line_item_url "https://platform.example.com/context/2923/lineitems/1/lineitem"

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
      Keyword.get(opts, :endpoint, %AGSEndpoint{
        line_items: @line_items_url,
        line_item: @line_item_url,
        scopes: @all_scopes
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
      "id" => Keyword.get(opts, :id, "#{@line_items_url}/1/lineitem"),
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

  describe "options" do
    test "every operation raises on unknown options", ctx do
      client = build_client(ctx.platform)
      context = Ltix.Test.build_launch_context(ctx.platform)

      {:ok, score} =
        Score.new(user_id: "u1", activity_progress: :completed, grading_progress: :fully_graded)

      for call <- [
            fn -> GradeService.authenticate(context, unknown: true) end,
            fn -> GradeService.authenticate!(context, unknown: true) end,
            fn ->
              GradeService.authenticate(ctx.platform.registration,
                endpoint: %AGSEndpoint{},
                unknown: true
              )
            end,
            fn -> GradeService.list_line_items(client, unknown: true) end,
            fn -> GradeService.get_line_item(client, unknown: true) end,
            fn ->
              GradeService.create_line_item(client,
                label: "Quiz",
                score_maximum: 1,
                unknown: true
              )
            end,
            fn ->
              GradeService.delete_line_item(client,
                line_item: @line_items_url <> "/9",
                unknown: true
              )
            end,
            fn -> GradeService.post_score(client, score, unknown: true) end,
            fn -> GradeService.list_results(client, unknown: true) end
          ] do
        assert_raise InvalidOption, "Option :unknown is unknown", call
      end
    end

    test "operations raise on invalid option values", ctx do
      client = build_client(ctx.platform)

      assert_raise InvalidOption, ~r/Option :line_item is invalid/, fn ->
        GradeService.list_results(client, line_item: 1)
      end
    end
  end

  # --- AdvantageService callbacks ---

  describe "AdvantageService callbacks" do
    test "endpoint_from_claims extracts AGS endpoint" do
      claims = %LaunchClaims{
        ags_endpoint: %AGSEndpoint{
          line_items: @line_items_url,
          scopes: @all_scopes
        }
      }

      assert {:ok, %AGSEndpoint{}} = GradeService.endpoint_from_claims(claims)
    end

    test "endpoint_from_claims returns :error when no endpoint" do
      claims = %LaunchClaims{}
      assert :error == GradeService.endpoint_from_claims(claims)
    end

    test "validate_endpoint accepts AGSEndpoint" do
      assert :ok == GradeService.validate_endpoint(%AGSEndpoint{})
    end

    test "validate_endpoint rejects other values" do
      assert {:error, %InvalidEndpoint{}} =
               GradeService.validate_endpoint(:not_an_endpoint)
    end

    test "scopes returns scope array from endpoint" do
      endpoint = %AGSEndpoint{scopes: @all_scopes}
      assert @all_scopes == GradeService.scopes(endpoint)
    end

    test "scopes returns empty list when scope is nil" do
      endpoint = %AGSEndpoint{scopes: nil}
      assert [] == GradeService.scopes(endpoint)
    end
  end

  # --- authenticate/2 ---

  describe "authenticate/2 from LaunchContext" do
    test "acquires token with AGS scopes from claim", ctx do
      stub_token_response()

      context =
        Ltix.Test.build_launch_context(ctx.platform,
          ags_endpoint: %AGSEndpoint{
            line_items: @line_items_url,
            line_item: @line_item_url,
            scopes: @all_scopes
          }
        )

      assert {:ok, %Client{} = client} =
               GradeService.authenticate(context,
                 req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
               )

      assert %AGSEndpoint{} = client.endpoints[GradeService]
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

      endpoint = %AGSEndpoint{
        line_items: @line_items_url,
        scopes: @all_scopes
      }

      assert {:ok, %Client{} = client} =
               GradeService.authenticate(ctx.platform.registration,
                 endpoint: endpoint,
                 req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
               )

      assert %AGSEndpoint{} = client.endpoints[GradeService]
    end

    test "raises without endpoint option", ctx do
      assert_raise InvalidOption, "Option :endpoint is required", fn ->
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

      endpoint = %AGSEndpoint{
        line_items: @line_items_url,
        scopes: @all_scopes
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
        build_line_item_json(id: "#{@line_items_url}/1", label: "Quiz 1"),
        build_line_item_json(id: "#{@line_items_url}/2", label: "Quiz 2")
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

    test "follows relative next links without reapplying line item filters", ctx do
      Req.Test.expect(Ltix.GradeService, fn conn ->
        assert Plug.Conn.fetch_query_params(conn).query_params == %{"tag" => "quiz"}

        conn
        |> Plug.Conn.put_resp_content_type(@lineitem_container_media_type)
        |> Plug.Conn.put_resp_header("link", "<?cursor=2>; rel=next")
        |> Req.Test.json([build_line_item_json(id: "#{@line_items_url}/1", label: "Quiz 1")])
      end)

      Req.Test.expect(Ltix.GradeService, fn conn ->
        assert conn.request_path == "/context/2923/lineitems"
        assert conn.query_string == "cursor=2"

        conn
        |> Plug.Conn.put_resp_content_type(@lineitem_container_media_type)
        |> Req.Test.json([build_line_item_json(id: "#{@line_items_url}/2", label: "Quiz 2")])
      end)

      client = build_client(ctx.platform)

      assert {:ok, [%LineItem{label: "Quiz 1"}, %LineItem{label: "Quiz 2"}]} =
               GradeService.list_line_items(client, tag: "quiz")

      Req.Test.verify!(Ltix.GradeService)
    end

    test "returns error when line_items URL not available", ctx do
      endpoint = %AGSEndpoint{line_items: nil, line_item: @line_item_url, scopes: @all_scopes}
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
               GradeService.get_line_item(client, line_item: @line_item_url)
    end

    test "returns error when no URL available", ctx do
      endpoint = %AGSEndpoint{line_items: @line_items_url, line_item: nil, scopes: @all_scopes}
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

        response = Map.put(json, "id", "#{@line_items_url}/new")

        conn
        |> Plug.Conn.put_resp_content_type(@lineitem_media_type)
        |> Plug.Conn.send_resp(201, Ltix.AppConfig.json_library!().encode!(response))
      end)

      client = build_client(ctx.platform)

      assert {:ok, %LineItem{} = item} =
               GradeService.create_line_item(client, label: "Quiz 1", score_maximum: 100)

      assert item.id == "#{@line_items_url}/new"
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

    test "returns error when line_items URL not available", ctx do
      endpoint = %AGSEndpoint{line_items: nil, line_item: @line_item_url, scopes: @all_scopes}
      client = build_client(ctx.platform, endpoint: endpoint)

      assert {:error, %ServiceNotAvailable{}} =
               GradeService.create_line_item(client, label: "Quiz 1", score_maximum: 100)
    end

    test "returns ScopeMismatch with only lineitem.readonly", ctx do
      client = build_client(ctx.platform, scopes: [@scope_lineitem_readonly])

      assert {:error, %ScopeMismatch{}} =
               GradeService.create_line_item(client, label: "Quiz 1", score_maximum: 100)
    end

    test "sends date times as ISO 8601 and parses them back", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        json = Ltix.AppConfig.json_library!().decode!(body)
        assert json["startDateTime"] == "2024-01-15T10:30:00Z"
        assert json["endDateTime"] == "2024-02-15T10:30:00Z"

        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(Map.put(json, "id", "#{@line_items_url}/new"))
      end)

      assert {:ok, %LineItem{start_date_time: ~U[2024-01-15 10:30:00Z]}} =
               GradeService.create_line_item(build_client(ctx.platform),
                 label: "Quiz",
                 score_maximum: 10,
                 start_date_time: ~U[2024-01-15 10:30:00Z],
                 end_date_time: ~U[2024-02-15 10:30:00Z]
               )
    end

    test "raises when a date time is not a DateTime", ctx do
      assert_raise InvalidOption, ~r/Option :start_date_time is invalid/, fn ->
        GradeService.create_line_item(build_client(ctx.platform),
          label: "Quiz",
          score_maximum: 10,
          start_date_time: "2024-01-15T10:30:00Z"
        )
      end
    end

    test "returns InvalidField without sending an invalid line item field", ctx do
      Req.Test.stub(Ltix.GradeService, fn _conn -> flunk("sent an invalid line item") end)
      client = build_client(ctx.platform)

      assert {:error, %InvalidField{struct: LineItem, field: :label}} =
               GradeService.create_line_item(client, label: " ", score_maximum: 100)

      assert {:error, %InvalidField{struct: LineItem, field: :score_maximum}} =
               GradeService.create_line_item(client, label: "Quiz 1", score_maximum: 0)
    end

    test "raises when score_maximum is not a number", ctx do
      assert_raise InvalidOption, ~r/Option :score_maximum is invalid/, fn ->
        GradeService.create_line_item(build_client(ctx.platform),
          label: "Quiz 1",
          score_maximum: "100"
        )
      end
    end

    test "raises when label is missing", ctx do
      client = build_client(ctx.platform)

      assert_raise InvalidOption, "Option :label is required", fn ->
        GradeService.create_line_item(client, score_maximum: 100)
      end
    end

    test "raises when score_maximum is missing", ctx do
      client = build_client(ctx.platform)

      assert_raise InvalidOption, "Option :score_maximum is required", fn ->
        GradeService.create_line_item(client, label: "Quiz 1")
      end
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
        assert json["id"] == "#{@line_items_url}/1/lineitem"

        conn
        |> Plug.Conn.put_resp_content_type(@lineitem_media_type)
        |> Req.Test.json(json)
      end)

      client = build_client(ctx.platform)

      item = %LineItem{
        id: "#{@line_items_url}/1/lineitem",
        label: "Updated Quiz",
        score_maximum: 100
      }

      assert {:ok, %LineItem{label: "Updated Quiz"}} =
               GradeService.update_line_item(client, item)
    end

    test "returns InvalidField without sending an invalid line item", ctx do
      Req.Test.stub(Ltix.GradeService, fn _conn -> flunk("sent an invalid line item") end)
      item = %LineItem{id: @line_item_url, label: " ", score_maximum: 100}

      assert {:error, %InvalidField{field: :label}} =
               GradeService.update_line_item(build_client(ctx.platform), item)
    end

    test "returns ScopeMismatch without lineitem scope", ctx do
      client = build_client(ctx.platform, scopes: [@scope_lineitem_readonly])

      item = %LineItem{id: @line_item_url, label: "Quiz 1", score_maximum: 100}

      assert {:error, %ScopeMismatch{}} = GradeService.update_line_item(client, item)
    end
  end

  # --- delete_line_item/2 ---

  describe "delete_line_item/2" do
    test "deletes line item by struct", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert {conn.method, conn.request_path} ==
                 {"DELETE", "/context/2923/lineitems/99/lineitem"}

        Plug.Conn.send_resp(conn, 204, "")
      end)

      client = build_client(ctx.platform)
      item = %LineItem{id: "#{@line_items_url}/99/lineitem"}

      assert :ok = GradeService.delete_line_item(client, line_item: item)
    end

    test "deletes line item by URL string", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert {conn.method, conn.request_path} ==
                 {"DELETE", "/context/2923/lineitems/99/lineitem"}

        Plug.Conn.send_resp(conn, 204, "")
      end)

      client = build_client(ctx.platform)

      assert :ok =
               GradeService.delete_line_item(client, line_item: "#{@line_items_url}/99/lineitem")
    end

    test "returns CoupledLineItem when URL matches endpoint line_item", ctx do
      client = build_client(ctx.platform)

      assert {:error, %CoupledLineItem{}} =
               GradeService.delete_line_item(client, line_item: @line_item_url)
    end

    test "defaults to the coupled line item", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert {conn.method, conn.request_path} ==
                 {"DELETE", "/context/2923/lineitems/1/lineitem"}

        Plug.Conn.send_resp(conn, 204, "")
      end)

      client = build_client(ctx.platform)

      assert {:error, %CoupledLineItem{}} = GradeService.delete_line_item(client)
      assert :ok = GradeService.delete_line_item(client, force: true)
    end

    test "no guard when endpoint has no line_item URL", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        Plug.Conn.send_resp(conn, 204, "")
      end)

      endpoint = %AGSEndpoint{line_items: @line_items_url, line_item: nil, scopes: @all_scopes}
      client = build_client(ctx.platform, endpoint: endpoint)

      assert :ok =
               GradeService.delete_line_item(client, line_item: "#{@line_items_url}/99/lineitem")
    end

    test "returns ScopeMismatch without lineitem scope", ctx do
      client = build_client(ctx.platform, scopes: [@scope_lineitem_readonly])

      assert {:error, %ScopeMismatch{}} =
               GradeService.delete_line_item(client, line_item: "#{@line_items_url}/99/lineitem")
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

    test "posts to {line_item}/scores using endpoint line_item", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path =~ "/scores"

        Plug.Conn.send_resp(conn, 200, "")
      end)

      client = build_client(ctx.platform)

      assert :ok = GradeService.post_score(client, ctx.score)
    end

    test "posts to explicit line item URL", ctx do
      explicit_url = "#{@line_items_url}/42/lineitem"

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

    test "posts timestamps at every caller precision without losing the instant", ctx do
      client = build_client(ctx.platform)

      {microsecond, precision, fraction} = {123_000, 3, "123000"}

      for {utc_offset, standard_offset, expected_time} <- [
            {0, 0, "2024-01-15T10:30:00"},
            {19_800, 0, "2024-01-15T05:00:00"}
          ] do
        timestamp = %{
          ~U[2024-01-15 10:30:00Z]
          | microsecond: {microsecond, precision},
            utc_offset: utc_offset,
            std_offset: standard_offset
        }

        Req.Test.stub(Ltix.GradeService, fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          json = Ltix.AppConfig.json_library!().decode!(body)

          {:ok, posted_timestamp, _offset} = DateTime.from_iso8601(json["timestamp"])
          assert DateTime.compare(posted_timestamp, timestamp) == :eq
          assert json["timestamp"] == "#{expected_time}.#{fraction}Z"

          Plug.Conn.send_resp(conn, 204, "")
        end)

        assert {:ok, score} =
                 Score.new(
                   user_id: "user-123",
                   activity_progress: :completed,
                   grading_progress: :fully_graded,
                   timestamp: timestamp
                 )

        assert :ok = GradeService.post_score(client, score)
      end
    end

    test "posts validated submission timestamps unchanged with time zones and fractions", ctx do
      client = build_client(ctx.platform)

      for {submission, expected} <- [
            {%{started_at: "2024-01-15T09:00:00.1+05:30"},
             %{"startedAt" => "2024-01-15T09:00:00.1+05:30"}},
            {%{submitted_at: "2024-01-15T10:00:00.123456789-04:00"},
             %{"submittedAt" => "2024-01-15T10:00:00.123456789-04:00"}},
            {%{
               started_at: "2024-01-15T09:00:00.123+02:00",
               submitted_at: "2024-01-15T07:00:00.123000Z"
             },
             %{
               "startedAt" => "2024-01-15T09:00:00.123+02:00",
               "submittedAt" => "2024-01-15T07:00:00.123000Z"
             }}
          ] do
        Req.Test.stub(Ltix.GradeService, fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          json = Ltix.AppConfig.json_library!().decode!(body)

          assert json["submission"] == expected
          Plug.Conn.send_resp(conn, 204, "")
        end)

        assert {:ok, score} =
                 Score.new(
                   user_id: "user-123",
                   activity_progress: :completed,
                   grading_progress: :fully_graded,
                   submission: submission
                 )

        assert :ok = GradeService.post_score(client, score)
      end
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
      endpoint = %AGSEndpoint{line_items: @line_items_url, line_item: nil, scopes: @all_scopes}
      client = build_client(ctx.platform, endpoint: endpoint)

      assert {:error, %ServiceNotAvailable{}} = GradeService.post_score(client, ctx.score)
    end
  end

  # --- list_results/2 ---

  describe "list_results/2" do
    test "fetches results for explicit line item", ctx do
      explicit_url = "#{@line_items_url}/42/lineitem"

      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert conn.request_path =~ "/42/lineitem/results"

        conn
        |> Plug.Conn.put_resp_content_type(@result_container_media_type)
        |> Req.Test.json([])
      end)

      client = build_client(ctx.platform)

      assert {:ok, _results} =
               GradeService.list_results(client, line_item: explicit_url)
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
               GradeService.list_results(client, user_id: "user-123")
    end

    test "follows relative result links with multiple relation types", ctx do
      Req.Test.expect(Ltix.GradeService, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type(@result_container_media_type)
        |> Plug.Conn.put_resp_header("link", "<results?cursor=2>; rel=\"prev NEXT\"")
        |> Req.Test.json([build_result_json("user-1", result_score: 0.8)])
      end)

      Req.Test.expect(Ltix.GradeService, fn conn ->
        assert conn.request_path == "/context/2923/lineitems/1/lineitem/results"
        assert conn.query_string == "cursor=2"

        conn
        |> Plug.Conn.put_resp_content_type(@result_container_media_type)
        |> Req.Test.json([build_result_json("user-2", result_score: 0.9)])
      end)

      client = build_client(ctx.platform)

      assert {:ok, [%Result{user_id: "user-1"}, %Result{user_id: "user-2"}]} =
               GradeService.list_results(client)

      Req.Test.verify!(Ltix.GradeService)
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
      assert {:ok, _} = GradeService.list_results(client)
    end

    test "returns error when no line item URL available", ctx do
      endpoint = %AGSEndpoint{line_items: @line_items_url, line_item: nil, scopes: @all_scopes}
      client = build_client(ctx.platform, endpoint: endpoint)

      assert {:error, %ServiceNotAvailable{}} = GradeService.list_results(client)
    end
  end

  describe "line items without an id" do
    test "every operation returns MissingLineItemId", ctx do
      Req.Test.stub(Ltix.GradeService, fn _conn ->
        flunk("sent a request for a line item without an id")
      end)

      client = build_client(ctx.platform)
      item = %LineItem{label: "Quiz", score_maximum: 10}

      {:ok, score} =
        Score.new(user_id: "u1", activity_progress: :completed, grading_progress: :fully_graded)

      assert {:error, %MissingLineItemId{}} = GradeService.get_line_item(client, line_item: item)
      assert {:error, %MissingLineItemId{}} = GradeService.update_line_item(client, item)

      assert {:error, %MissingLineItemId{}} =
               GradeService.delete_line_item(client, line_item: item)

      assert {:error, %MissingLineItemId{}} =
               GradeService.post_score(client, score, line_item: item)

      assert {:error, %MissingLineItemId{}} = GradeService.list_results(client, line_item: item)
    end
  end
end
