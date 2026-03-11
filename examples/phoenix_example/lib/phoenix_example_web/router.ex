defmodule PhoenixExampleWeb.Router do
  use PhoenixExampleWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PhoenixExampleWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # LTI endpoints receive form POSTs from platforms — no CSRF protection.
  pipeline :lti do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :put_root_layout, html: {PhoenixExampleWeb.Layouts, :root}
  end

  scope "/", PhoenixExampleWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/lti", PhoenixExampleWeb do
    pipe_through :lti

    post "/login", LtiController, :login
    post "/launch", LtiController, :launch
    post "/echo", LtiController, :echo
    post "/deep_link", LtiController, :deep_link_respond
    get "/roster", LtiController, :roster
    get "/grades", LtiController, :grades
    post "/grades/line_items", LtiController, :create_line_item
    get "/grades/results", LtiController, :grade_results
    post "/grades/score", LtiController, :post_score
  end
end
