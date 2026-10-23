defmodule Ltix.GradeServiceTest do
  use ExUnit.Case, async: true

  import GradeServiceFixtures

  alias Ltix.Errors.Invalid.CollectionTooLarge
  alias Ltix.Errors.Invalid.CoupledLineItem
  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.Errors.Invalid.InvalidOption
  alias Ltix.Errors.Invalid.MalformedResponse
  alias Ltix.Errors.Invalid.MissingLineItemId
  alias Ltix.Errors.Invalid.ScopeMismatch
  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.Errors.Security.AccessDenied
  alias Ltix.Errors.Security.AccessTokenExpired
  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.GradeService
  alias Ltix.GradeService.Endpoint, as: GradeServiceEndpoint
  alias Ltix.GradeService.LineItem
  alias Ltix.GradeService.Result
  alias Ltix.GradeService.Score
  alias Ltix.MembershipsService.Endpoint, as: MembershipsServiceEndpoint
  alias Ltix.OAuth.Client

  @scope_lineitem "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem"
  @scope_lineitem_readonly "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem.readonly"
  @scope_score "https://purl.imsglobal.org/spec/lti-ags/scope/score"
  @nrps_scope "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"

  @all_scopes GradeServiceFixtures.scopes()

  @line_items_url GradeServiceFixtures.line_items_url()
  @line_item_url GradeServiceFixtures.line_item_url()

  @lineitem_media_type "application/vnd.ims.lis.v2.lineitem+json"
  @lineitem_container_media_type "application/vnd.ims.lis.v2.lineitemcontainer+json"
  @result_container_media_type "application/vnd.ims.lis.v2.resultcontainer+json"
  @score_media_type "application/vnd.ims.lis.v1.score+json"

  setup do
    platform = Ltix.Test.setup_platform!()
    %{platform: platform}
  end

  defp stub_token_response(scopes \\ @all_scopes) do
    Ltix.Test.stub_token_response(
      scopes: scopes,
      access_token: "test-ags-token"
    )
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

  def forward_telemetry([_, _, operation, suffix], _measurements, metadata, owner) do
    if self() == owner, do: send(owner, {:telemetry, operation, suffix, metadata})
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  describe "options" do
    test "every operation raises on unknown options", ctx do
      client = create_client()
      launch = Ltix.Test.build_launch(ctx.platform)

      {:ok, score} =
        Score.new(user_id: "u1", activity_progress: :completed, grading_progress: :fully_graded)

      for call <- [
            fn -> GradeService.authenticate(launch, unknown: true) end,
            fn -> GradeService.authenticate!(launch, unknown: true) end,
            fn ->
              GradeService.authenticate(ctx.platform.registration,
                endpoint: %GradeServiceEndpoint{},
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
              GradeService.create_line_item(client, %LineItem{label: "Quiz", score_maximum: 1},
                unknown: true
              )
            end,
            fn ->
              GradeService.update_line_item(
                client,
                %LineItem{id: @line_item_url, label: "Quiz", score_maximum: 1},
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

    test "operations raise on invalid option values" do
      client = create_client()

      assert_raise InvalidOption, ~r/Option :line_item is invalid/, fn ->
        GradeService.list_results(client, line_item: 1)
      end
    end
  end

  # --- authenticate/2 ---

  describe "authenticate/2 from Launch" do
    test "requests the scopes of the claim's scope array", ctx do
      owner = self()

      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(owner, {:scope, URI.decode_query(body)["scope"]})
        Req.Test.json(conn, %{"access_token" => "test-ags-token", "token_type" => "Bearer"})
      end)

      launch =
        Ltix.Test.build_launch(ctx.platform,
          ags_endpoint: %GradeServiceEndpoint{
            line_items: @line_items_url,
            line_item: @line_item_url,
            scopes: @all_scopes
          }
        )

      assert {:ok, %Client{} = client} =
               GradeService.authenticate(launch,
                 req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
               )

      assert %GradeServiceEndpoint{} = Client.get_endpoint(client, GradeService)
      assert_received {:scope, scope}
      assert String.split(scope) == @all_scopes
    end

    test "rejects a launch claim without scopes", ctx do
      launch =
        Ltix.Test.build_launch(ctx.platform,
          claims: %{
            "https://purl.imsglobal.org/spec/lti-ags/claim/endpoint" => %{
              "lineitem" => @line_item_url
            }
          }
        )

      assert {:error,
              %InvalidField{struct: GradeServiceEndpoint, field: :scopes, reason: :required}} =
               GradeService.authenticate(launch)
    end

    test "errors when no AGS claim in launch", ctx do
      launch = Ltix.Test.build_launch(ctx.platform)

      assert {:error, %ServiceNotAvailable{} = error} =
               GradeService.authenticate(launch)

      assert Exception.message(error) =~ "The launch has no endpoint claim for this service"
    end
  end

  describe "authenticate/2 from Registration" do
    test "acquires token with endpoint option", ctx do
      stub_token_response()

      endpoint = %GradeServiceEndpoint{
        line_items: @line_items_url,
        scopes: @all_scopes
      }

      assert {:ok, %Client{} = client} =
               GradeService.authenticate(ctx.platform.registration,
                 endpoint: endpoint,
                 req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
               )

      assert %GradeServiceEndpoint{} = Client.get_endpoint(client, GradeService)
    end

    test "rejects an endpoint without scopes", ctx do
      endpoint = %GradeServiceEndpoint{line_items: @line_items_url}

      assert {:error,
              %InvalidField{struct: GradeServiceEndpoint, field: :scopes, reason: :required}} =
               GradeService.authenticate(ctx.platform.registration, endpoint: endpoint)
    end

    test "rejects an endpoint with an invalid URL", ctx do
      endpoint = %GradeServiceEndpoint{
        line_items: "http://platform.example.com",
        scopes: @all_scopes
      }

      assert {:error, %InvalidField{struct: GradeServiceEndpoint, field: :line_items}} =
               GradeService.authenticate(ctx.platform.registration, endpoint: endpoint)
    end

    test "accepts a partial scope grant unless require_all_scopes is set, from a registration or a launch",
         ctx do
      stub_token_response([@scope_score])

      endpoint =
        GradeServiceEndpoint.new!(
          line_item: @line_item_url,
          scopes: [@scope_lineitem, @scope_score]
        )

      req_options = [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
      launch = Ltix.Test.build_launch(ctx.platform, ags_endpoint: endpoint)

      assert {:ok, %Client{}} =
               GradeService.authenticate(ctx.platform.registration,
                 endpoint: endpoint,
                 req_options: req_options
               )

      for launch_or_registration <- [launch, ctx.platform.registration] do
        opts = if launch_or_registration == launch, do: [], else: [endpoint: endpoint]

        assert {:error, %ScopeMismatch{scopes: [@scope_lineitem]}} =
                 GradeService.authenticate(
                   launch_or_registration,
                   opts ++ [req_options: req_options, require_all_scopes: true]
                 )
      end
    end

    test "raises without endpoint option", ctx do
      assert_raise InvalidOption, "Option :endpoint is required", fn ->
        GradeService.authenticate(ctx.platform.registration, [])
      end
    end
  end

  # --- list_line_items/2 ---

  describe "list_line_items/2" do
    test "sends correct Accept header" do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        [accept] = Plug.Conn.get_req_header(conn, "accept")
        assert accept == @lineitem_container_media_type

        conn
        |> Plug.Conn.put_resp_content_type(@lineitem_container_media_type)
        |> Req.Test.json([])
      end)

      client = create_client()
      assert {:ok, []} = GradeService.list_line_items(client)
    end

    test "passes filter query parameters" do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["resource_link_id"] == "rl-123"
        assert params["resource_id"] == "res-456"
        assert params["tag"] == "grade"

        conn
        |> Plug.Conn.put_resp_content_type(@lineitem_container_media_type)
        |> Req.Test.json([])
      end)

      client = create_client()

      assert {:ok, []} =
               GradeService.list_line_items(client,
                 resource_link_id: "rl-123",
                 resource_id: "res-456",
                 tag: "grade"
               )
    end

    test "follows relative next links without reapplying line item filters" do
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

      client = create_client()

      assert {:ok, [%LineItem{label: "Quiz 1"}, %LineItem{label: "Quiz 2"}]} =
               GradeService.list_line_items(client, tag: "quiz")

      Req.Test.verify!(Ltix.GradeService)
    end

    test "omits line item fields the platform sends with the wrong type" do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type(@lineitem_container_media_type)
        |> Req.Test.json([
          %{
            "id" => 5,
            "label" => 7,
            "scoreMaximum" => "x",
            "resourceLinkId" => ["link"],
            "resourceId" => %{},
            "tag" => false,
            "startDateTime" => "2018-03-06T20:05:02",
            "endDateTime" => 42,
            "gradesReleased" => "yes"
          }
        ])
      end)

      client = create_client()

      assert {:ok,
              [
                %LineItem{
                  id: nil,
                  label: nil,
                  score_maximum: nil,
                  resource_link_id: nil,
                  resource_id: nil,
                  tag: nil,
                  start_date_time: nil,
                  end_date_time: nil,
                  grades_released: nil,
                  extensions: %{}
                }
              ]} = GradeService.list_line_items(client)
    end

    test "returns error when line_items URL not available" do
      endpoint = %GradeServiceEndpoint{
        line_items: nil,
        line_item: @line_item_url,
        scopes: @all_scopes
      }

      client = create_client(endpoint: endpoint)

      assert {:error, %ServiceNotAvailable{} = error} = GradeService.list_line_items(client)
      assert Exception.message(error) =~ "has no line items URL"
    end

    test "returns ScopeMismatch when client lacks lineitem scope" do
      client = create_client(scopes: [@scope_score])

      assert {:error, %ScopeMismatch{scopes: [@scope_lineitem, @scope_lineitem_readonly]}} =
               GradeService.list_line_items(client)
    end

    test "returns AccessTokenExpired when token is expired" do
      client =
        create_client(expires_at: DateTime.add(DateTime.utc_now(), -120))

      assert {:error, %AccessTokenExpired{}} = GradeService.list_line_items(client)
    end
  end

  # --- get_line_item/2 ---

  describe "get_line_item/2" do
    test "sends a GET without a body" do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert conn.method == "GET"
        assert Plug.Conn.get_req_header(conn, "content-type") == []
        assert {:ok, "", conn} = Plug.Conn.read_body(conn)
        Req.Test.json(conn, build_line_item_json())
      end)

      assert {:ok, %LineItem{}} = GradeService.get_line_item(create_client())
    end

    test "returns error when no URL available" do
      endpoint = %GradeServiceEndpoint{
        line_items: @line_items_url,
        line_item: nil,
        scopes: @all_scopes
      }

      client = create_client(endpoint: endpoint)

      assert {:error, %ServiceNotAvailable{} = error} = GradeService.get_line_item(client)
      assert Exception.message(error) =~ "has no coupled line item URL"
    end
  end

  # --- create_line_item/3 ---

  describe "create_line_item/3" do
    test "creates line item and returns parsed response" do
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

      client = create_client()

      assert {:ok, %LineItem{} = item} =
               GradeService.create_line_item(client, label: "Quiz 1", score_maximum: 100)

      assert item.id == "#{@line_items_url}/new"
      assert item.label == "Quiz 1"
    end

    test "creates a line item given as a struct, with options" do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert conn.request_path == "/other/lineitems"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        json = Ltix.AppConfig.json_library!().decode!(body)
        assert json == %{"label" => "Quiz 1", "scoreMaximum" => 100, "tag" => "quiz"}

        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(Map.put(json, "id", "https://platform.example.com/other/lineitems/1"))
      end)

      endpoint = %GradeServiceEndpoint{
        line_items: "https://platform.example.com/other/lineitems",
        scopes: @all_scopes
      }

      item = %LineItem{label: "Quiz 1", score_maximum: 100, tag: "quiz"}

      assert {:ok, %LineItem{id: "https://platform.example.com/other/lineitems/1"}} =
               GradeService.create_line_item(create_client(), item, endpoint: endpoint)

      assert {:ok, %LineItem{}} =
               GradeService.create_line_item(
                 create_client(),
                 [label: "Quiz 1", score_maximum: 100, tag: "quiz"],
                 endpoint: endpoint
               )
    end

    test "raises on extensions" do
      assert_raise InvalidOption, "Option :extensions is unknown", fn ->
        GradeService.create_line_item(create_client(),
          label: "Quiz 1",
          score_maximum: 100,
          extensions: %{"https://example.com/extra" => "data"}
        )
      end
    end

    test "sends correct Content-Type" do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        [content_type] = Plug.Conn.get_req_header(conn, "content-type")
        assert content_type =~ @lineitem_media_type

        response = build_line_item_json()

        conn
        |> Plug.Conn.put_resp_content_type(@lineitem_media_type)
        |> Plug.Conn.send_resp(201, Ltix.AppConfig.json_library!().encode!(response))
      end)

      client = create_client()
      assert {:ok, _} = GradeService.create_line_item(client, label: "Quiz 1", score_maximum: 100)
    end

    test "returns error when line_items URL not available" do
      endpoint = %GradeServiceEndpoint{
        line_items: nil,
        line_item: @line_item_url,
        scopes: @all_scopes
      }

      client = create_client(endpoint: endpoint)

      assert {:error, %ServiceNotAvailable{} = error} =
               GradeService.create_line_item(client, label: "Quiz 1", score_maximum: 100)

      assert Exception.message(error) =~ "has no line items URL"
    end

    test "returns ScopeMismatch with only lineitem.readonly" do
      client = create_client(scopes: [@scope_lineitem_readonly])

      assert {:error, %ScopeMismatch{}} =
               GradeService.create_line_item(client, label: "Quiz 1", score_maximum: 100)
    end

    test "sends date times as ISO 8601 and parses them back" do
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
               GradeService.create_line_item(create_client(),
                 label: "Quiz",
                 score_maximum: 10,
                 start_date_time: ~U[2024-01-15 10:30:00Z],
                 end_date_time: ~U[2024-02-15 10:30:00Z]
               )
    end

    test "raises when a date time is not a DateTime" do
      assert_raise InvalidOption, ~r/Option :start_date_time is invalid/, fn ->
        GradeService.create_line_item(create_client(),
          label: "Quiz",
          score_maximum: 10,
          start_date_time: "2024-01-15T10:30:00Z"
        )
      end
    end

    test "returns InvalidField without sending an invalid line item field" do
      Req.Test.stub(Ltix.GradeService, fn _conn -> flunk("sent an invalid line item") end)
      client = create_client()

      assert {:error, %InvalidField{struct: LineItem, field: :label}} =
               GradeService.create_line_item(client, label: " ", score_maximum: 100)

      assert {:error, %InvalidField{struct: LineItem, field: :score_maximum}} =
               GradeService.create_line_item(client, label: "Quiz 1", score_maximum: 0)
    end

    test "raises when score_maximum is not a number" do
      assert_raise InvalidOption, ~r/Option :score_maximum is invalid/, fn ->
        GradeService.create_line_item(create_client(),
          label: "Quiz 1",
          score_maximum: "100"
        )
      end
    end

    test "raises when label is missing" do
      client = create_client()

      assert_raise InvalidOption, "Option :label is required", fn ->
        GradeService.create_line_item(client, score_maximum: 100)
      end
    end

    test "raises when score_maximum is missing" do
      client = create_client()

      assert_raise InvalidOption, "Option :score_maximum is required", fn ->
        GradeService.create_line_item(client, label: "Quiz 1")
      end
    end
  end

  # --- update_line_item/3 ---

  describe "update_line_item/3" do
    test "PUTs full line item to its id URL" do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert {conn.method, conn.request_path} == {"PUT", "/context/2923/lineitems/1/lineitem"}

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        json = Ltix.AppConfig.json_library!().decode!(body)
        assert json["label"] == "Updated Quiz"
        assert json["id"] == "#{@line_items_url}/1/lineitem"

        conn
        |> Plug.Conn.put_resp_content_type(@lineitem_media_type)
        |> Req.Test.json(json)
      end)

      client = create_client()

      item = %LineItem{
        id: "#{@line_items_url}/1/lineitem",
        label: "Updated Quiz",
        score_maximum: 100
      }

      assert {:ok, %LineItem{label: "Updated Quiz"}} =
               GradeService.update_line_item(client, item)
    end

    test "returns InvalidField without sending an invalid line item" do
      Req.Test.stub(Ltix.GradeService, fn _conn -> flunk("sent an invalid line item") end)
      item = %LineItem{id: @line_item_url, label: " ", score_maximum: 100}

      assert {:error, %InvalidField{field: :label}} =
               GradeService.update_line_item(create_client(), item)
    end

    test "returns ScopeMismatch without lineitem scope" do
      client = create_client(scopes: [@scope_lineitem_readonly])

      item = %LineItem{id: @line_item_url, label: "Quiz 1", score_maximum: 100}

      assert {:error, %ScopeMismatch{}} = GradeService.update_line_item(client, item)
    end
  end

  # --- delete_line_item/2 ---

  describe "delete_line_item/2" do
    test "deletes line item by struct" do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert {conn.method, conn.request_path} ==
                 {"DELETE", "/context/2923/lineitems/99/lineitem"}

        Plug.Conn.send_resp(conn, 204, "")
      end)

      client = create_client()
      item = %LineItem{id: "#{@line_items_url}/99/lineitem"}

      assert :ok = GradeService.delete_line_item(client, line_item: item)
    end

    test "deletes line item by URL string" do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert {conn.method, conn.request_path} ==
                 {"DELETE", "/context/2923/lineitems/99/lineitem"}

        Plug.Conn.send_resp(conn, 204, "")
      end)

      client = create_client()

      assert :ok =
               GradeService.delete_line_item(client, line_item: "#{@line_items_url}/99/lineitem")
    end

    test "returns CoupledLineItem when URL matches endpoint line_item" do
      client = create_client()

      assert {:error, %CoupledLineItem{}} =
               GradeService.delete_line_item(client, line_item: @line_item_url)
    end

    test "defaults to the coupled line item" do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert {conn.method, conn.request_path} ==
                 {"DELETE", "/context/2923/lineitems/1/lineitem"}

        Plug.Conn.send_resp(conn, 204, "")
      end)

      client = create_client()

      assert {:error, %CoupledLineItem{}} = GradeService.delete_line_item(client)
      assert :ok = GradeService.delete_line_item(client, force: true)
    end

    test "returns ScopeMismatch without lineitem scope" do
      client = create_client(scopes: [@scope_lineitem_readonly])

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

      client = create_client()

      assert :ok = GradeService.post_score(client, ctx.score)
    end

    test "returns InvalidField without sending a score built with invalid fields", ctx do
      Req.Test.stub(Ltix.GradeService, fn _conn -> flunk("sent an invalid score") end)
      client = create_client()

      score = %{ctx.score | activity_progress: "Completed"}
      assert {:error, %InvalidField{struct: Score}} = GradeService.post_score(client, score)
    end

    test "posts to explicit line item URL", ctx do
      explicit_url = "#{@line_items_url}/42/lineitem"

      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert conn.request_path =~ "/42/lineitem/scores"
        Plug.Conn.send_resp(conn, 200, "")
      end)

      client = create_client()
      item = %LineItem{id: explicit_url}

      assert :ok = GradeService.post_score(client, ctx.score, line_item: item)
    end

    test "sends correct Content-Type", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        [content_type] = Plug.Conn.get_req_header(conn, "content-type")
        assert content_type =~ @score_media_type

        Plug.Conn.send_resp(conn, 200, "")
      end)

      client = create_client()

      assert :ok = GradeService.post_score(client, ctx.score)
    end

    test "posts timestamps at every caller precision without losing the instant" do
      client = create_client()

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

    test "posts submission times as UTC ISO 8601 with microseconds" do
      client = create_client()

      for {submission, expected} <- [
            {[started_at: ~U[2024-01-15 09:00:00.1Z]],
             %{"startedAt" => "2024-01-15T09:00:00.100000Z"}},
            {%{submitted_at: ~U[2024-01-15 10:00:00Z]},
             %{"submittedAt" => "2024-01-15T10:00:00.000000Z"}},
            {%{
               started_at: ~U[2024-01-15 07:00:00.123Z],
               submitted_at: ~U[2024-01-15 07:00:00.123456Z]
             },
             %{
               "startedAt" => "2024-01-15T07:00:00.123000Z",
               "submittedAt" => "2024-01-15T07:00:00.123456Z"
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

    test "returns error when no line item URL available", ctx do
      endpoint = %GradeServiceEndpoint{
        line_items: @line_items_url,
        line_item: nil,
        scopes: @all_scopes
      }

      client = create_client(endpoint: endpoint)

      assert {:error, %ServiceNotAvailable{} = error} = GradeService.post_score(client, ctx.score)
      assert Exception.message(error) =~ "has no coupled line item URL"
    end
  end

  # --- list_results/2 ---

  describe "list_results/2" do
    test "fetches results for explicit line item" do
      explicit_url = "#{@line_items_url}/42/lineitem"

      Req.Test.stub(Ltix.GradeService, fn conn ->
        assert conn.request_path =~ "/42/lineitem/results"

        conn
        |> Plug.Conn.put_resp_content_type(@result_container_media_type)
        |> Req.Test.json([])
      end)

      client = create_client()

      assert {:ok, _results} =
               GradeService.list_results(client, line_item: explicit_url)
    end

    test "filters by user_id query parameter" do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["user_id"] == "user-123"

        conn
        |> Plug.Conn.put_resp_content_type(@result_container_media_type)
        |> Req.Test.json([build_result_json("user-123", result_score: 0.9)])
      end)

      client = create_client()

      assert {:ok, _results} =
               GradeService.list_results(client, user_id: "user-123")
    end

    test "omits result fields the platform sends with the wrong type" do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type(@result_container_media_type)
        |> Req.Test.json([
          %{
            "id" => 5,
            "scoreOf" => [],
            "userId" => 1,
            "resultScore" => "abc",
            "resultMaximum" => true,
            "scoringUserId" => 2,
            "comment" => %{}
          }
        ])
      end)

      client = create_client()

      assert {:ok,
              [
                %Result{
                  id: nil,
                  score_of: nil,
                  user_id: nil,
                  result_score: nil,
                  result_maximum: nil,
                  scoring_user_id: nil,
                  comment: nil,
                  extensions: %{}
                }
              ]} = GradeService.list_results(client)
    end

    test "follows relative result links with multiple relation types" do
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

      client = create_client()

      assert {:ok, [%Result{user_id: "user-1"}, %Result{user_id: "user-2"}]} =
               GradeService.list_results(client)

      Req.Test.verify!(Ltix.GradeService)
    end

    test "sends correct Accept header" do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        [accept] = Plug.Conn.get_req_header(conn, "accept")
        assert accept == @result_container_media_type

        conn
        |> Plug.Conn.put_resp_content_type(@result_container_media_type)
        |> Req.Test.json([])
      end)

      client = create_client()
      assert {:ok, _} = GradeService.list_results(client)
    end

    test "returns error when no line item URL available" do
      endpoint = %GradeServiceEndpoint{
        line_items: @line_items_url,
        line_item: nil,
        scopes: @all_scopes
      }

      client = create_client(endpoint: endpoint)

      assert {:error, %ServiceNotAvailable{} = error} = GradeService.list_results(client)
      assert Exception.message(error) =~ "has no coupled line item URL"
    end
  end

  # --- bang variants ---

  describe "bang variants" do
    setup do
      {:ok, score} =
        Score.new(user_id: "u1", activity_progress: :completed, grading_progress: :fully_graded)

      item_json = build_line_item_json(id: "#{@line_items_url}/7")

      Req.Test.stub(Ltix.GradeService, fn conn ->
        case {conn.method, conn.request_path} do
          {"DELETE", "/context/2923/lineitems/7"} ->
            Plug.Conn.send_resp(conn, 204, "")

          {"POST", "/context/2923/lineitems/1/lineitem/scores"} ->
            Plug.Conn.send_resp(conn, 204, "")

          {"GET", "/context/2923/lineitems"} ->
            Req.Test.json(conn, [item_json])

          {"GET", "/context/2923/lineitems/1/lineitem/results"} ->
            Req.Test.json(conn, [build_result_json("u1", [])])

          {"GET", "/context/2923/lineitems/1/lineitem"} ->
            Req.Test.json(conn, item_json)

          {"POST", "/context/2923/lineitems"} ->
            Req.Test.json(conn, item_json)

          {"PUT", "/context/2923/lineitems/7"} ->
            Req.Test.json(conn, item_json)

          _ ->
            Plug.Conn.send_resp(conn, 404, "")
        end
      end)

      item = %LineItem{id: "#{@line_items_url}/7", label: "Quiz", score_maximum: 10}
      %{client: create_client(), score: score, item: item}
    end

    test "return the unwrapped value on success", ctx do
      assert [%LineItem{}] = GradeService.list_line_items!(ctx.client)
      assert %LineItem{} = GradeService.get_line_item!(ctx.client)

      assert %LineItem{} =
               GradeService.create_line_item!(ctx.client, label: "Quiz", score_maximum: 10)

      assert %LineItem{} = GradeService.update_line_item!(ctx.client, ctx.item)
      assert :ok = GradeService.delete_line_item!(ctx.client, line_item: ctx.item)
      assert :ok = GradeService.post_score!(ctx.client, ctx.score)
      assert [%Result{user_id: "u1"}] = GradeService.list_results!(ctx.client)
    end

    test "raise the error on failure", ctx do
      client = create_client(scopes: [])

      for call <- [
            fn -> GradeService.list_line_items!(client) end,
            fn -> GradeService.get_line_item!(client) end,
            fn -> GradeService.create_line_item!(client, label: "Quiz", score_maximum: 10) end,
            fn -> GradeService.update_line_item!(client, ctx.item) end,
            fn -> GradeService.delete_line_item!(client, line_item: ctx.item) end,
            fn -> GradeService.post_score!(client, ctx.score) end,
            fn -> GradeService.list_results!(client) end
          ] do
        assert_raise ScopeMismatch, call
      end
    end
  end

  describe "malformed line item responses" do
    test "return MalformedResponse" do
      client = create_client()
      item = %LineItem{id: "#{@line_items_url}/9", label: "Quiz", score_maximum: 10}

      Req.Test.stub(Ltix.GradeService, &Req.Test.json(&1, [1]))

      for result <- [
            GradeService.get_line_item(client),
            GradeService.create_line_item(client, label: "Quiz", score_maximum: 10),
            GradeService.update_line_item(client, item)
          ] do
        assert {:error, %MalformedResponse{service: GradeService}} = result
      end
    end
  end

  describe "access denied" do
    test "every request operation returns AccessDenied for HTTP 401 and 403" do
      {:ok, score} =
        Score.new(user_id: "u1", activity_progress: :completed, grading_progress: :fully_graded)

      client = create_client()
      item = %LineItem{id: "#{@line_items_url}/9", label: "Quiz", score_maximum: 10}

      for status <- [401, 403] do
        Req.Test.stub(Ltix.GradeService, &Plug.Conn.send_resp(&1, status, "denied"))

        for result <- [
              GradeService.get_line_item(client),
              GradeService.create_line_item(client, label: "Quiz", score_maximum: 10),
              GradeService.update_line_item(client, item),
              GradeService.delete_line_item(client, line_item: item),
              GradeService.post_score(client, score),
              GradeService.list_line_items(client),
              GradeService.list_results(client),
              GradeService.stream_line_items(client),
              GradeService.stream_results(client)
            ] do
          assert {:error, %AccessDenied{status: ^status, body: "denied"}} = result
        end
      end
    end
  end

  describe "unreachable platform" do
    test "every request operation returns TransportError with the requested URL" do
      {:ok, score} =
        Score.new(user_id: "u1", activity_progress: :completed, grading_progress: :fully_graded)

      client = create_client()
      item = %LineItem{id: "#{@line_items_url}/9", label: "Quiz", score_maximum: 10}
      Req.Test.stub(Ltix.GradeService, &Req.Test.transport_error(&1, :econnrefused))

      for {result, url} <- [
            {GradeService.get_line_item(client), @line_item_url},
            {GradeService.create_line_item(client, label: "Quiz", score_maximum: 10),
             @line_items_url},
            {GradeService.update_line_item(client, item), item.id},
            {GradeService.delete_line_item(client, line_item: item), item.id},
            {GradeService.post_score(client, score), "#{@line_item_url}/scores"},
            {GradeService.list_line_items(client), @line_items_url},
            {GradeService.list_results(client), "#{@line_item_url}/results"}
          ] do
        assert {:error, %TransportError{status: nil, url: ^url}} = result
      end
    end
  end

  describe "platform responses the tool can't use" do
    setup do
      {:ok, score} =
        Score.new(user_id: "u1", activity_progress: :completed, grading_progress: :fully_graded)

      %{client: create_client(), score: score}
    end

    test "invalid JSON in a successful response returns MalformedResponse", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type(@lineitem_container_media_type)
        |> Plug.Conn.send_resp(200, "{not json")
      end)

      for result <- [
            GradeService.list_line_items(ctx.client),
            GradeService.get_line_item(ctx.client)
          ] do
        assert {:error, %MalformedResponse{}} = result
      end
    end

    test "an error status keeps its status, raw body, and headers", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.put_resp_header("retry-after", "120")
        |> Plug.Conn.send_resp(503, "<html>maintenance</html>")
      end)

      for result <- [
            GradeService.post_score(ctx.client, ctx.score),
            GradeService.list_line_items(ctx.client)
          ] do
        assert {:error,
                %TransportError{status: 503, body: "<html>maintenance</html>", headers: headers}} =
                 result

        assert headers["retry-after"] == ["120"]
      end
    end
  end

  describe "line items without an id" do
    test "every operation returns MissingLineItemId" do
      Req.Test.stub(Ltix.GradeService, fn _conn ->
        flunk("sent a request for a line item without an id")
      end)

      client = create_client()
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
      assert {:error, %MissingLineItemId{}} = GradeService.stream_results(client, line_item: item)
    end
  end

  # --- endpoint override ---

  describe "endpoint option" do
    setup do
      owner = self()

      Req.Test.stub(Ltix.GradeService, fn conn ->
        send(owner, {:request, conn.method, conn.request_path})

        case conn.method do
          "DELETE" ->
            Plug.Conn.send_resp(conn, 204, "")

          "POST" when conn.request_path == "/other/lineitems/5/scores" ->
            Plug.Conn.send_resp(conn, 204, "")

          "GET" when conn.request_path in ["/other/lineitems", "/other/lineitems/5/results"] ->
            Req.Test.json(conn, [])

          _ ->
            Req.Test.json(conn, build_line_item_json())
        end
      end)

      {:ok, score} =
        Score.new(user_id: "u1", activity_progress: :completed, grading_progress: :fully_graded)

      endpoint = %GradeServiceEndpoint{
        line_items: "https://platform.example.com/other/lineitems",
        line_item: "https://platform.example.com/other/lineitems/5",
        scopes: @all_scopes
      }

      %{client: create_client(), endpoint: endpoint, score: score}
    end

    test "every operation uses the given endpoint", ctx do
      %{client: client, endpoint: endpoint} = ctx

      assert {:ok, []} = GradeService.list_line_items(client, endpoint: endpoint)
      assert_received {:request, "GET", "/other/lineitems"}

      assert {:ok, _} =
               GradeService.create_line_item(client,
                 endpoint: endpoint,
                 label: "Quiz",
                 score_maximum: 10
               )

      assert_received {:request, "POST", "/other/lineitems"}

      assert {:ok, _} = GradeService.get_line_item(client, endpoint: endpoint)
      assert_received {:request, "GET", "/other/lineitems/5"}

      assert :ok = GradeService.post_score(client, ctx.score, endpoint: endpoint)
      assert_received {:request, "POST", "/other/lineitems/5/scores"}

      assert {:ok, []} = GradeService.list_results(client, endpoint: endpoint)
      assert_received {:request, "GET", "/other/lineitems/5/results"}

      assert {:error, %CoupledLineItem{}} =
               GradeService.delete_line_item(client, endpoint: endpoint)

      assert :ok =
               GradeService.delete_line_item(client,
                 endpoint: endpoint,
                 line_item: @line_item_url
               )

      assert_received {:request, "DELETE", "/context/2923/lineitems/1/lineitem"}
    end

    test "works with a client that has no grade service endpoint", ctx do
      client = %{ctx.client | endpoints: %{}}

      assert {:ok, []} = GradeService.list_line_items(client, endpoint: ctx.endpoint)
      assert {:error, %ServiceNotAvailable{} = error} = GradeService.list_line_items(client)
      assert Exception.message(error) =~ "has no grade service endpoint"
    end
  end

  describe "a client authenticated for another service" do
    test "gets ScopeMismatch from every operation" do
      {:ok, score} =
        Score.new(user_id: "u1", activity_progress: :completed, grading_progress: :fully_graded)

      client = %{
        create_client(scopes: [@nrps_scope])
        | endpoints: %{
            Ltix.MembershipsService => %MembershipsServiceEndpoint{
              context_memberships_url: @line_items_url
            }
          }
      }

      item = %LineItem{id: @line_item_url, label: "Quiz", score_maximum: 10}

      assert {:error, %ScopeMismatch{}} = GradeService.list_line_items(client)

      assert {:error, %ScopeMismatch{}} =
               GradeService.create_line_item(client, label: "Quiz", score_maximum: 10)

      assert {:error, %ScopeMismatch{}} = GradeService.get_line_item(client)
      assert {:error, %ScopeMismatch{}} = GradeService.update_line_item(client, item)
      assert {:error, %ScopeMismatch{}} = GradeService.delete_line_item(client)

      assert {:error, %ScopeMismatch{scopes: [@scope_score]}} =
               GradeService.post_score(client, score)

      assert {:error, %ScopeMismatch{}} = GradeService.list_results(client)
    end
  end

  # --- telemetry ---

  describe "telemetry" do
    setup do
      owner = self()
      handler_id = "grade-service-test-#{System.unique_integer([:positive])}"

      events =
        for operation <- [
              :list_line_items,
              :get_line_item,
              :create_line_item,
              :update_line_item,
              :delete_line_item,
              :post_score,
              :list_results,
              :stream_line_items,
              :stream_results
            ],
            suffix <- [:start, :stop, :exception] do
          [:ltix, :grade_service, operation, suffix]
        end

      :telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.forward_telemetry/4,
        owner
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, score} =
        Score.new(user_id: "u1", activity_progress: :completed, grading_progress: :fully_graded)

      %{score: score}
    end

    test "reports the URL each operation requests", ctx do
      Req.Test.stub(Ltix.GradeService, fn conn ->
        case conn.method do
          method
          when method in ["DELETE", "POST"] and conn.request_path != "/context/2923/lineitems" ->
            Plug.Conn.send_resp(conn, 204, "")

          "GET"
          when conn.request_path in [
                 "/context/2923/lineitems",
                 "/context/2923/lineitems/1/lineitem/results"
               ] ->
            Req.Test.json(conn, [])

          _ ->
            Req.Test.json(conn, build_line_item_json())
        end
      end)

      client = create_client()
      item = %LineItem{id: "#{@line_items_url}/9", label: "Quiz", score_maximum: 10}

      GradeService.list_line_items(client)
      GradeService.create_line_item(client, label: "Quiz", score_maximum: 10)
      GradeService.get_line_item(client)
      GradeService.update_line_item(client, item)
      GradeService.delete_line_item(client, line_item: item)
      GradeService.post_score(client, ctx.score)
      GradeService.list_results(client)
      GradeService.stream_line_items(client)
      GradeService.stream_results(client)

      for {operation, url} <- [
            list_line_items: @line_items_url,
            create_line_item: @line_items_url,
            get_line_item: @line_item_url,
            update_line_item: item.id,
            delete_line_item: item.id,
            post_score: @line_item_url <> "/scores",
            list_results: @line_item_url <> "/results",
            stream_line_items: @line_items_url,
            stream_results: @line_item_url <> "/results"
          ] do
        assert_received {:telemetry, ^operation, :start, %{endpoint: ^url}}
        assert_received {:telemetry, ^operation, :stop, %{endpoint: ^url}}
      end
    end

    test "reports no URL when the client has no grade service endpoint" do
      client = %{create_client() | endpoints: %{}}

      assert {:error, %ServiceNotAvailable{}} = GradeService.list_line_items(client)
      assert_received {:telemetry, :list_line_items, :stop, %{endpoint: nil}}
    end

    test "a crash inside an operation emits an exception event", ctx do
      Req.Test.stub(Ltix.GradeService, fn _conn -> raise "platform plug crashed" end)

      assert_raise RuntimeError, fn ->
        GradeService.post_score(create_client(), ctx.score)
      end

      assert_received {:telemetry, :post_score, :exception,
                       %{endpoint: @line_item_url <> "/scores"}}
    end
  end

  # --- streams and limits ---

  describe "stream_line_items/2 and stream_results/2" do
    setup do
      owner = self()

      Req.Test.stub(Ltix.GradeService, fn conn ->
        page = Plug.Conn.fetch_query_params(conn).query_params["page"] || "1"
        send(owner, {:requested, conn.request_path, page, conn.query_string})

        body =
          if String.ends_with?(conn.request_path, "/results"),
            do: [build_result_json("user-#{page}", [])],
            else: [build_line_item_json(id: "#{@line_items_url}/#{page}")]

        if page == "1" do
          conn
          |> Plug.Conn.put_resp_header(
            "link",
            "<https://platform.example.com#{conn.request_path}?page=2>; rel=next"
          )
          |> Req.Test.json(body)
        else
          Req.Test.json(conn, body)
        end
      end)

      %{client: create_client()}
    end

    test "stream line items lazily with filters on the first page", ctx do
      assert {:ok, stream} = GradeService.stream_line_items(ctx.client, tag: "quiz")
      assert_received {:requested, "/context/2923/lineitems", "1", "tag=quiz"}
      refute_received {:requested, _, "2", _}

      assert [%LineItem{id: "#{@line_items_url}/1"}, %LineItem{id: "#{@line_items_url}/2"}] =
               Enum.to_list(stream)

      assert_received {:requested, "/context/2923/lineitems", "2", "page=2"}
    end

    test "stream results for the given line item", ctx do
      item = %LineItem{id: "#{@line_items_url}/4/lineitem"}

      assert {:ok, stream} =
               GradeService.stream_results(ctx.client, line_item: item, user_id: "user-1")

      assert_received {:requested, "/context/2923/lineitems/4/lineitem/results", "1",
                       "user_id=user-1"}

      assert [%Result{user_id: "user-1"}, %Result{user_id: "user-2"}] = Enum.to_list(stream)
    end

    test "return errors before streaming" do
      client = create_client(scopes: [@scope_score])

      assert {:error, %ScopeMismatch{}} = GradeService.stream_line_items(client)
      assert {:error, %ScopeMismatch{}} = GradeService.stream_results(client)
      assert_raise ScopeMismatch, fn -> GradeService.stream_line_items!(client) end
      assert_raise ScopeMismatch, fn -> GradeService.stream_results!(client) end
    end

    test "bang variants return the stream", ctx do
      assert [%LineItem{} | _] = Enum.to_list(GradeService.stream_line_items!(ctx.client))

      assert [%Result{user_id: "user-1"}, %Result{user_id: "user-2"}] =
               Enum.to_list(GradeService.stream_results!(ctx.client))
    end

    test "stream options reject the eager limits", ctx do
      assert_raise InvalidOption, "Option :max_line_items is unknown", fn ->
        GradeService.stream_line_items(ctx.client, max_line_items: 1)
      end

      assert_raise InvalidOption, "Option :max_results is unknown", fn ->
        GradeService.stream_results(ctx.client, max_results: 1)
      end
    end

    test "list functions stop at their limits", ctx do
      assert {:error, %CollectionTooLarge{max: 1, option: :max_line_items}} =
               GradeService.list_line_items(ctx.client, max_line_items: 1)

      assert {:error, %CollectionTooLarge{max: 1, option: :max_results}} =
               GradeService.list_results(ctx.client, max_results: 1)

      assert {:ok, [_, _]} = GradeService.list_line_items(ctx.client, max_line_items: 2)

      assert {:ok, [%Result{user_id: "user-1"}, %Result{user_id: "user-2"}]} =
               GradeService.list_results(ctx.client, max_results: :infinity)
    end

    test "a limit must be an integer or :infinity", ctx do
      assert_raise InvalidOption, ~r/Option :max_results is invalid/, fn ->
        GradeService.list_results(ctx.client, max_results: :none)
      end
    end
  end
end
