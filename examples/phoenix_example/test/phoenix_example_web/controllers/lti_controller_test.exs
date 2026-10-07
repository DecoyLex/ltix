defmodule PhoenixExampleWeb.LtiControllerTest do
  use PhoenixExampleWeb.ConnCase, async: true

  alias Ltix.GradeService.LineItem
  alias Ltix.GradeService.Result
  alias Ltix.LaunchClaims.AGSEndpoint
  alias Ltix.LaunchClaims.MembershipsEndpoint
  alias Ltix.LaunchClaims.Role
  alias Ltix.MembershipsService.Member
  alias Phoenix.Flash
  alias PhoenixExample.LtiStorage

  @issuer "https://lti-ri.imsglobal.org"
  @context_url "https://lti-ri.imsglobal.org/platforms/6092/contexts/1"
  @line_items_url "#{@context_url}/line_items"
  @line_item_url "#{@context_url}/line_items/1"
  @return_url "https://lti-ri.imsglobal.org/platforms/6092/deep_links"

  @line_item_scope "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem"
  @result_scope "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly"
  @score_scope "https://purl.imsglobal.org/spec/lti-ags/scope/score"
  @memberships_scope "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"

  setup do
    {:ok, registration} = LtiStorage.get_registration(@issuer, "test", [])

    %{
      platform:
        Ltix.Test.setup_platform!(
          registration: registration,
          deployment_id: "test-deployment",
          tool_jwk: LtiStorage.tool_jwk()
        )
    }
  end

  describe "login" do
    for method <- [:get, :post] do
      test "redirects a #{method} to the platform's authorization endpoint", %{
        conn: conn,
        platform: platform
      } do
        conn =
          dispatch(
            conn,
            @endpoint,
            unquote(method),
            ~p"/lti/login",
            Ltix.Test.login_params(platform, login_hint: "user-7")
          )

        redirect = URI.parse(redirected_to(conn, 302))
        query = URI.decode_query(redirect.query)

        assert URI.to_string(%{redirect | query: nil}) ==
                 "https://lti-ri.imsglobal.org/platforms/6092/authorizations/new"

        assert query["client_id"] == "test"
        assert query["login_hint"] == "user-7"
        assert query["redirect_uri"] == url(~p"/lti/launch")
        state = get_session(conn, :lti_state)
        assert byte_size(state) > 0
        assert query["state"] == state
      end
    end

    test "rejects an unknown platform", %{conn: conn} do
      params = %{
        "iss" => "https://unknown.example.com",
        "login_hint" => "user-7",
        "target_link_uri" => url(~p"/lti/launch")
      }

      conn = post(conn, ~p"/lti/login", params)

      assert text_response(conn, 400) =~
               "Login initiation failed: Registration not found for issuer https://unknown.example.com"
    end
  end

  describe "resource link launch" do
    test "shows the user, context, and resource link", %{conn: conn, platform: platform} do
      conn =
        launch(conn, platform,
          name: "Jane Doe",
          email: "jane@example.com",
          context: %{id: "course-1", label: "CS101", title: "Intro to Computer Science"},
          resource_link: %{id: "link-1", title: "Week 1 Quiz"}
        )

      html = html_response(conn, 200)
      assert html =~ "LTI Launch Successful"
      assert html =~ "Jane Doe"
      assert html =~ "jane@example.com"
      assert html =~ "Intro to Computer Science"
      assert html =~ "Week 1 Quiz"
      refute html =~ "Advantage Services"
    end

    test "links to the services the platform offers", %{conn: conn, platform: platform} do
      conn =
        launch(conn, platform,
          ags_endpoint: AGSEndpoint.new!(line_items: @line_items_url, scopes: [@score_scope]),
          memberships_endpoint: MembershipsEndpoint.new!("#{@context_url}/memberships")
        )

      html = html_response(conn, 200)
      assert html =~ ~s(href="/lti/roster")
      assert html =~ ~s(href="/lti/grades")
    end

    test "rejects a launch whose state does not match the login", %{
      conn: conn,
      platform: platform
    } do
      conn = post(conn, ~p"/lti/login", Ltix.Test.login_params(platform))
      nonce = Ltix.Test.extract_nonce(redirected_to(conn, 302))

      conn =
        conn
        |> recycle()
        |> post(~p"/lti/launch", Ltix.Test.launch_params(platform, nonce: nonce, state: "forged"))

      assert text_response(conn, 401) =~ "Launch validation failed: CSRF state mismatch"
    end
  end

  describe "roster" do
    test "lists the course members", %{conn: conn, platform: platform} do
      conn =
        launch(conn, platform,
          memberships_endpoint: MembershipsEndpoint.new!("#{@context_url}/memberships")
        )

      Ltix.Test.stub_token_response(scopes: [@memberships_scope])

      Ltix.Test.stub_list_members(
        [
          %Member{
            user_id: "student-1",
            name: "Ada Lovelace",
            email: "ada@example.com",
            roles: [Role.from_atom(:learner)]
          },
          %Member{
            user_id: "teacher-1",
            name: "Grace Hopper",
            roles: [Role.from_atom(:instructor)]
          }
        ],
        context: %{id: "course-1", label: "CS101"}
      )

      html = conn |> recycle() |> get(~p"/lti/roster") |> html_response(200)

      assert html =~ "2 members"
      assert html =~ "CS101"
      assert html =~ "Ada Lovelace"
      assert html =~ "ada@example.com"
      assert html =~ "Grace Hopper"
    end

    test "shows an error without a launch", %{conn: conn} do
      html = conn |> get(~p"/lti/roster") |> html_response(200)

      assert html =~ "No active launch session"
    end
  end

  describe "grades" do
    setup %{conn: conn, platform: platform} do
      conn =
        launch(conn, platform,
          ags_endpoint:
            AGSEndpoint.new!(
              line_items: @line_items_url,
              line_item: @line_item_url,
              scopes: [@line_item_scope, @result_scope, @score_scope]
            )
        )

      Ltix.Test.stub_token_response(scopes: [@line_item_scope, @result_scope, @score_scope])

      %{conn: recycle(conn)}
    end

    test "lists the line items", %{conn: conn} do
      Ltix.Test.stub_list_line_items([
        %LineItem{id: @line_item_url, label: "Week 1 Quiz", score_maximum: 10, tag: "quiz"},
        %LineItem{id: "#{@line_items_url}/2", label: "Final Essay", score_maximum: 100}
      ])

      html = conn |> get(~p"/lti/grades") |> html_response(200)

      assert html =~ "Week 1 Quiz"
      assert html =~ "Final Essay"
      assert html =~ "Create Line Item"
      assert html =~ "Post score to coupled line item"
    end

    test "shows why the line items could not be listed", %{conn: conn} do
      Ltix.Test.stub_token_response(scopes: [@score_scope])

      html = conn |> get(~p"/lti/grades") |> html_response(200)

      assert html =~ "Client is not authorized for scope"
      refute html =~ "No line items found"
    end

    test "shows the score form for the chosen line item", %{conn: conn} do
      Ltix.Test.stub_list_line_items([])

      html = conn |> get(~p"/lti/grades?#{[score_for: @line_item_url]}") |> html_response(200)

      assert html =~ "Posting to: <code>#{@line_item_url}</code>"
      assert html =~ ~s(name="user_id" value="user-12345")
    end

    test "creates a line item", %{conn: conn} do
      Ltix.Test.stub_create_line_item(%LineItem{
        id: "#{@line_items_url}/3",
        label: "Midterm",
        score_maximum: 50
      })

      conn =
        post(conn, ~p"/lti/grades/line_items", %{"label" => "Midterm", "score_maximum" => "50"})

      assert redirected_to(conn) == ~p"/lti/grades"
      assert Flash.get(conn.assigns.flash, :info) == ~s(Line item "Midterm" created.)
    end

    test "rejects a score maximum that is not a number", %{conn: conn} do
      conn =
        post(conn, ~p"/lti/grades/line_items", %{"label" => "Midterm", "score_maximum" => "lots"})

      assert redirected_to(conn) == ~p"/lti/grades"
      assert Flash.get(conn.assigns.flash, :error) == "Invalid score maximum."
    end

    test "lists the results of a line item", %{conn: conn} do
      Ltix.Test.stub_list_results(
        [
          %Result{
            user_id: "student-1",
            result_score: 8.5,
            result_maximum: 10,
            comment: "Nice work"
          },
          %Result{user_id: "student-2", result_score: 6, result_maximum: 10}
        ],
        line_item: @line_item_url
      )

      html =
        conn |> get(~p"/lti/grades/results?#{[line_item: @line_item_url]}") |> html_response(200)

      assert html =~ "student-1"
      assert html =~ "8.5"
      assert html =~ "Nice work"
      assert html =~ "student-2"
    end

    test "posts a score", %{conn: conn} do
      Ltix.Test.stub_post_score(line_item: @line_item_url)

      conn =
        post(conn, ~p"/lti/grades/score", score_params(comment: "Well done"))

      assert redirected_to(conn) == ~p"/lti/grades"
      assert Flash.get(conn.assigns.flash, :info) == "Score posted for user student-1."
    end

    test "rejects a score that is not a number", %{conn: conn} do
      conn = post(conn, ~p"/lti/grades/score", score_params(score_given: "eight"))

      assert redirected_to(conn) == ~p"/lti/grades"
      assert Flash.get(conn.assigns.flash, :error) =~ ~s(field :score_given is invalid)
    end

    test "rejects a blank user ID", %{conn: conn} do
      conn = post(conn, ~p"/lti/grades/score", score_params(user_id: ""))

      assert redirected_to(conn) == ~p"/lti/grades"
      assert Flash.get(conn.assigns.flash, :error) =~ ~s(field :user_id is required)
    end
  end

  defp score_params(overrides) do
    Map.merge(
      %{
        "line_item" => @line_item_url,
        "user_id" => "student-1",
        "score_given" => "8",
        "score_maximum" => "10",
        "activity_progress" => "completed",
        "grading_progress" => "fully_graded"
      },
      Map.new(overrides, fn {key, value} -> {Atom.to_string(key), value} end)
    )
  end

  describe "deep linking" do
    setup %{conn: conn, platform: platform} do
      conn =
        launch(conn, platform,
          message_type: :deep_linking,
          deep_linking_settings: %{
            deep_link_return_url: @return_url,
            accept_types: ["ltiResourceLink"],
            accept_presentation_document_targets: ["iframe", "window"],
            title: "Suggested Quiz"
          }
        )

      %{conn: conn}
    end

    test "shows the platform's constraints", %{conn: conn} do
      html = html_response(conn, 200)

      assert html =~ "Deep Linking — Select Content"
      assert html =~ "ltiResourceLink"
      assert html =~ "iframe, window"
      assert html =~ ~s(name="title" value="Suggested Quiz")
    end

    test "returns the chosen resource link to the platform", %{conn: conn, platform: platform} do
      conn =
        conn
        |> recycle()
        |> post(~p"/lti/deep_link", %{
          "title" => "Week 2 Quiz",
          "url" => "https://localhost:4000/quiz/2"
        })

      claims = deep_link_response_claims(conn, platform)

      assert [
               %{
                 "type" => "ltiResourceLink",
                 "title" => "Week 2 Quiz",
                 "url" => "https://localhost:4000/quiz/2"
               }
             ] = claims["https://purl.imsglobal.org/spec/lti-dl/claim/content_items"]
    end

    test "returns a resource link without a title when the title is blank", %{
      conn: conn,
      platform: platform
    } do
      conn =
        conn
        |> recycle()
        |> post(~p"/lti/deep_link", %{"title" => "", "url" => "https://localhost:4000/quiz/2"})

      claims = deep_link_response_claims(conn, platform)

      assert [%{"type" => "ltiResourceLink", "url" => "https://localhost:4000/quiz/2"} = item] =
               claims["https://purl.imsglobal.org/spec/lti-dl/claim/content_items"]

      refute Map.has_key?(item, "title")
    end

    test "returns no content when canceled", %{conn: conn, platform: platform} do
      conn = conn |> recycle() |> post(~p"/lti/deep_link", %{})

      claims = deep_link_response_claims(conn, platform)

      assert claims["https://purl.imsglobal.org/spec/lti-dl/claim/content_items"] == []
    end
  end

  defp launch(conn, platform, opts) do
    conn = post(conn, ~p"/lti/login", Ltix.Test.login_params(platform))
    nonce = Ltix.Test.extract_nonce(redirected_to(conn, 302))
    state = get_session(conn, :lti_state)
    params = Ltix.Test.launch_params(platform, [nonce: nonce, state: state] ++ opts)

    conn
    |> recycle()
    |> post(~p"/lti/launch", params)
  end

  defp deep_link_response_claims(conn, platform) do
    form =
      conn
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("#deep-link-form")

    assert LazyHTML.attribute(form, "action") == [@return_url]

    [jwt] =
      form
      |> LazyHTML.query(~s(input[name="JWT"]))
      |> LazyHTML.attribute("value")

    {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, jwt)
    claims
  end
end
