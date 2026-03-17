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

  def default_key_size do
    Application.get_env(:ltix, :default_key_size, 4096)
  end

  def pop_required!(opts, key) do
    with {nil, _opts} <- Keyword.pop(opts, key),
         nil <- Application.get_env(:ltix, key) do
      raise ArgumentError,
            "missing :#{key} configuration — set it in config.exs or pass it in opts"
    else
      {value, opts} -> {value, opts}
      value -> {value, opts}
    end
  end
end
