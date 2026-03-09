defmodule PhoenixExampleWeb.LtiController do
  use PhoenixExampleWeb, :controller
  require Logger

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
        |> render(:launch,
          context: context,
          has_memberships: context.claims.memberships_endpoint != nil
        )

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
         {:ok, client} <- Ltix.MembershipsService.authenticate(context),
         {:ok, roster} <- Ltix.MembershipsService.get_members(client) do
      render(conn, :roster, roster: roster, error: nil)
    else
      nil ->
        render(conn, :roster,
          roster: nil,
          error: "No active launch session. Please launch from your LMS first."
        )

      {:error, %{__struct__: _} = exception} ->
        dbg(exception)
        Logger.error(Exception.message(exception))
        render(conn, :roster, roster: nil, error: Exception.message(exception))

      {:error, reason} ->
        render(conn, :roster, roster: nil, error: "Failed to fetch roster: #{inspect(reason)}")
    end
  end

  def echo(conn, params) do
    render(conn, :echo, params: params)
  end
end
