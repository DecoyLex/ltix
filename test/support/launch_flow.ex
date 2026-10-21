defmodule LaunchFlow do
  @moduledoc false

  # Launches into the tool as a platform and a browser do, by logging in and
  # handling the callback. The login takes the storage adapter options of
  # `callback_opts`, and the callback takes every option.

  @launch_url "https://tool.example.com/launch"

  # Launches with the claims `Ltix.Test.launch_params/2` builds from `launch_opts`.
  def launch(platform, launch_opts \\ [], callback_opts \\ []) do
    login = login!(platform, callback_opts)

    params =
      Ltix.Test.launch_params(platform, [nonce: nonce(login), state: login.state] ++ launch_opts)

    callback(params, login.state, callback_opts)
  end

  # Launches with the claims of `Ltix.Test.valid_lti_claims/2`, changed by `change`.
  def launch_with_claims(platform, change, callback_opts \\ []) do
    login = login!(platform, callback_opts)
    claims = change.(Ltix.Test.valid_lti_claims(platform, %{"nonce" => nonce(login)}))
    callback_with_claims(platform, claims, login.state, callback_opts)
  end

  # Handles the callback of a login with `state`, with `claims` signed by the
  # platform.
  def callback_with_claims(platform, claims, state, opts \\ []) do
    params = %{"id_token" => Ltix.Test.sign_id_token(claims, platform.jwk), "state" => state}
    callback(params, state, opts)
  end

  def login!(platform, opts \\ []) do
    {:ok, login} =
      Ltix.handle_login(
        Ltix.Test.login_params(platform),
        @launch_url,
        Keyword.take(opts, [:storage_adapter, :storage_adapter_options])
      )

    login
  end

  def nonce(login), do: Ltix.Test.extract_nonce(login.redirect_uri)

  def callback(params, state, opts \\ []) do
    Ltix.handle_callback(
      params,
      state,
      Keyword.merge([req_options: [plug: {Req.Test, Ltix.JWT.KeySet}]], opts)
    )
  end
end
