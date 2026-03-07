# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :phoenix_example,
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :phoenix_example, PhoenixExampleWeb.Endpoint,
  url: [host: "localhost", scheme: "https", port: 4000],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PhoenixExampleWeb.ErrorHTML, json: PhoenixExampleWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: PhoenixExample.PubSub,
  live_view: [signing_salt: "8YPiBxxx"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Ltix storage adapter
config :ltix, storage_adapter: PhoenixExample.LtiStorage

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
