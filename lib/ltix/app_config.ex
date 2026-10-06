defmodule Ltix.AppConfig do
  @moduledoc false

  alias Ltix.LaunchClaims

  @json_library (cond do
                   Application.compile_env(:ltix, :json_library) ->
                     Application.compile_env(:ltix, :json_library)

                   Code.ensure_loaded?(JSON) ->
                     JSON

                   Code.ensure_loaded?(Jason) ->
                     Jason

                   true ->
                     raise """
                     No JSON library found. Please add either `:jason` to your dependencies or upgrade to Elixir 1.18+/OTP 27+
                     to use the built-in `JSON` module.

                     If you want to use a different JSON library, set the following in your config:

                         config :ltix, :json_library, YourJsonModule
                     """
                 end)

  def json_library! do
    @json_library
  end

  def claims_parsers! do
    Application.get_env(:ltix, LaunchClaims, [])[:claim_parsers] || %{}
  end

  def role_parsers! do
    Application.get_env(:ltix, LaunchClaims, [])[:role_parsers] || %{}
  end

  def allow_anonymous_launches? do
    Application.get_env(:ltix, :allow_anonymous, false)
  end

  def max_token_age do
    Application.get_env(:ltix, :max_token_age, 3600)
  end

  def local_network_access do
    Application.get_env(:ltix, :local_network_access, :none)
  end

  def default_key_size do
    Application.get_env(:ltix, :default_key_size, 4096)
  end
end
