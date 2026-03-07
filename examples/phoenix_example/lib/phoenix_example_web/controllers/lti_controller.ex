defmodule PhoenixExampleWeb.LtiController do
  use PhoenixExampleWeb, :controller

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
        conn
        |> delete_session(:lti_state)
        |> render(:launch, context: context)

      {:error, reason} ->
        conn
        |> put_status(401)
        |> text("Launch validation failed: #{Exception.message(reason)}")
    end
  end

  def echo(conn, params) do
    render(conn, :echo, params: params)
  end
end
