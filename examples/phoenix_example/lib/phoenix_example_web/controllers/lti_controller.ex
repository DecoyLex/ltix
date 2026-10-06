defmodule PhoenixExampleWeb.LtiController do
  use PhoenixExampleWeb, :controller
  require Logger

  alias Ltix.DeepLinking
  alias Ltix.DeepLinking.ContentItem.LTIResourceLink
  alias Ltix.GradeService
  alias Ltix.GradeService.Score
  alias Ltix.MembershipsService
  alias PhoenixExample.LtiStorage

  def login(conn, params) do
    launch_url = url(conn, ~p"/lti/launch")

    case Ltix.handle_login(params, launch_url) do
      {:ok, %{redirect_uri: redirect_uri, state: state}} ->
        conn
        |> put_session(:lti_state, state)
        |> redirect(external: redirect_uri)

      {:error, reason} ->
        conn
        |> put_status(400)
        |> text("Login initiation failed: #{Exception.message(reason)}")
    end
  end

  def launch(conn, params) do
    state = get_session(conn, :lti_state)

    case Ltix.handle_callback(params, state) do
      {:ok, context} ->
        context_id = LtiStorage.store_context(context)

        conn
        |> delete_session(:lti_state)
        |> put_session(:lti_context_id, context_id)
        |> render_launch(context)

      {:error, reason} ->
        Logger.error(Exception.message(reason))

        conn
        |> put_status(401)
        |> text("Launch validation failed: #{Exception.message(reason)}")
    end
  end

  def roster(conn, _params) do
    with context_id when is_binary(context_id) <- get_session(conn, :lti_context_id),
         {:ok, context} <- LtiStorage.get_context(context_id),
         {:ok, client} <- MembershipsService.authenticate(context),
         {:ok, roster} <- MembershipsService.list_members(client) do
      render(conn, :roster, roster: roster, error: nil)
    else
      nil ->
        render(conn, :roster,
          roster: nil,
          error: "No active launch session. Please launch from your LMS first."
        )

      {:error, %{__struct__: _} = exception} ->
        Logger.error(Exception.message(exception))
        render(conn, :roster, roster: nil, error: Exception.message(exception))

      {:error, reason} ->
        render(conn, :roster, roster: nil, error: "Failed to fetch roster: #{inspect(reason)}")
    end
  end

  def echo(conn, params) do
    render(conn, :echo, params: params)
  end

  def deep_link_respond(conn, params) do
    with {:ok, context} <- fetch_context(conn),
         {:ok, items} <- build_content_items(params),
         {:ok, response} <- DeepLinking.build_response(context, items) do
      render(conn, :deep_link_response, return_url: response.return_url, jwt: response.jwt)
    else
      {:error, %{__struct__: _} = exception} ->
        conn
        |> put_status(422)
        |> text("Deep linking failed: #{Exception.message(exception)}")

      {:error, reason} ->
        conn
        |> put_status(422)
        |> text("Deep linking failed: #{inspect(reason)}")
    end
  end

  def grades(conn, params) do
    with {:ok, context} <- fetch_context(conn),
         {:ok, client} <- GradeService.authenticate(context) do
      endpoint = client.endpoints[GradeService]
      {line_items, line_items_error} = list_line_items(endpoint, client)

      render(conn, :grades,
        endpoint: endpoint,
        line_items: line_items,
        line_items_error: line_items_error,
        scopes: client.token.granted_scopes,
        score_for: params["score_for"],
        user_id: context.claims.subject,
        error: nil
      )
    else
      {:error, %{__struct__: _} = exception} ->
        Logger.error(Exception.message(exception))

        render(conn, :grades,
          endpoint: nil,
          line_items: [],
          line_items_error: nil,
          scopes: MapSet.new(),
          score_for: nil,
          user_id: nil,
          error: Exception.message(exception)
        )

      {:error, reason} ->
        render(conn, :grades,
          endpoint: nil,
          line_items: [],
          line_items_error: nil,
          scopes: MapSet.new(),
          score_for: nil,
          user_id: nil,
          error: inspect(reason)
        )
    end
  end

  def create_line_item(conn, %{"label" => label, "score_maximum" => score_max}) do
    with {:ok, context} <- fetch_context(conn),
         {:ok, client} <- GradeService.authenticate(context),
         {score_max_num, ""} <- Float.parse(score_max),
         {:ok, _item} <-
           GradeService.create_line_item(client, label: label, score_maximum: score_max_num) do
      conn
      |> put_flash(:info, "Line item \"#{label}\" created.")
      |> redirect(to: ~p"/lti/grades")
    else
      :error ->
        conn |> put_flash(:error, "Invalid score maximum.") |> redirect(to: ~p"/lti/grades")

      {:error, %{__struct__: _} = exception} ->
        conn |> put_flash(:error, Exception.message(exception)) |> redirect(to: ~p"/lti/grades")

      {:error, reason} ->
        conn |> put_flash(:error, inspect(reason)) |> redirect(to: ~p"/lti/grades")
    end
  end

  def grade_results(conn, %{"line_item" => line_item_url}) do
    with {:ok, context} <- fetch_context(conn),
         {:ok, client} <- GradeService.authenticate(context),
         {:ok, results} <- GradeService.list_results(client, line_item: line_item_url) do
      render(conn, :grade_results, results: results, line_item_url: line_item_url, error: nil)
    else
      {:error, %{__struct__: _} = exception} ->
        Logger.error(Exception.message(exception))

        render(conn, :grade_results,
          results: [],
          line_item_url: line_item_url,
          error: Exception.message(exception)
        )

      {:error, reason} ->
        render(conn, :grade_results,
          results: [],
          line_item_url: line_item_url,
          error: inspect(reason)
        )
    end
  end

  def post_score(conn, params) do
    line_item_url = params["line_item"]
    user_id = params["user_id"]

    with {:ok, context} <- fetch_context(conn),
         {:ok, client} <- GradeService.authenticate(context),
         {:ok, score} <- build_score(params),
         :ok <- GradeService.post_score(client, score, score_opts(line_item_url)) do
      conn
      |> put_flash(:info, "Score posted for user #{user_id}.")
      |> redirect(to: ~p"/lti/grades")
    else
      {:error, %{__struct__: _} = exception} ->
        conn |> put_flash(:error, Exception.message(exception)) |> redirect(to: ~p"/lti/grades")

      {:error, reason} ->
        conn |> put_flash(:error, inspect(reason)) |> redirect(to: ~p"/lti/grades")
    end
  end

  defp list_line_items(%{line_items: nil}, _client), do: {[], nil}

  defp list_line_items(_endpoint, client) do
    case GradeService.list_line_items(client) do
      {:ok, items} ->
        {items, nil}

      {:error, exception} ->
        Logger.error(Exception.message(exception))
        {[], Exception.message(exception)}
    end
  end

  defp fetch_context(conn) do
    case get_session(conn, :lti_context_id) do
      nil -> {:error, "No active launch session. Please launch from your LMS first."}
      context_id -> LtiStorage.get_context(context_id)
    end
  end

  defp build_score(params) do
    Score.new(
      user_id: non_blank(params["user_id"]),
      activity_progress: params["activity_progress"],
      grading_progress: params["grading_progress"],
      score_given: parse_optional_float(params["score_given"]),
      score_maximum: parse_optional_float(params["score_maximum"]),
      comment: non_blank(params["comment"])
    )
  end

  defp score_opts(nil), do: []
  defp score_opts(""), do: []
  defp score_opts(url), do: [line_item: url]

  defp parse_optional_float(nil), do: nil
  defp parse_optional_float(""), do: nil

  defp parse_optional_float(val) do
    case Float.parse(val) do
      {num, ""} -> num
      _ -> val
    end
  end

  defp non_blank(nil), do: nil
  defp non_blank(""), do: nil
  defp non_blank(s), do: s

  defp render_launch(conn, %{claims: %{message_type: "LtiDeepLinkingRequest"}} = context) do
    settings = context.claims.deep_linking_settings

    render(conn, :deep_link, context: context, settings: settings)
  end

  defp render_launch(conn, context) do
    render(conn, :launch,
      context: context,
      has_memberships: context.claims.memberships_endpoint != nil,
      has_ags: context.claims.ags_endpoint != nil
    )
  end

  defp build_content_items(%{"title" => title, "url" => url}) do
    case LTIResourceLink.new(title: non_blank(title), url: non_blank(url)) do
      {:ok, item} -> {:ok, [item]}
      {:error, _} = err -> err
    end
  end

  defp build_content_items(_params), do: {:ok, []}
end
