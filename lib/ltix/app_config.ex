defmodule Ltix.AppConfig do
  @moduledoc false

  @json_library (cond do
                   Application.compile_env(:ltix, :json_library) ->
                     Application.compile_env(:ltix, :json_library)

                   Code.ensure_loaded?(JSON) ->
                     JSON

                   Code.ensure_loaded?(Jason) ->
                     Jason

                   true ->
                     raise """
                     No JSON library found. Add `:jason` to your dependencies, or use Elixir 1.18 or later
                     with OTP 27 or later for the built-in `JSON` module. To use another JSON library, set it
                     in your configuration.

                         config :ltix, :json_library, YourJsonModule
                     """
                 end)

  def json_library! do
    @json_library
  end

  def plugins do
    Application.get_env(:ltix, :plugins, [])
  end

  def allow_anonymous_launches? do
    Application.get_env(:ltix, :allow_anonymous, false)
  end

  def max_token_age do
    Application.get_env(:ltix, :max_token_age, 3600)
  end

  def key_set do
    Application.get_env(:ltix, :key_set, Ltix.JWT.KeySet)
  end

  def local_network_access do
    Application.get_env(:ltix, :local_network_access, :none)
  end

  def default_key_size do
    Application.get_env(:ltix, :default_key_size, 4096)
  end
end
