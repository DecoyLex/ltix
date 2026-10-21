defmodule Ltix do
  @moduledoc """
  Ltix handles the LTI 1.3 OIDC launch flow for tool applications. It is
  built around these components.

    * `Ltix.Registration` - what the tool stores about a platform (issuer,
      client_id, endpoints). Created during out-of-band registration

    * `Ltix.StorageAdapter` - behaviour your app implements to look up
      registrations, deployments, and manage nonces

    * `Ltix.Launch` - the verified launch, with the registration,
      deployment, endpoints, and the claims parsed from the ID token (roles,
      context, resource link, and more)

    * `Ltix.Plugin` - plugins that extend Ltix. Ltix's own support for each
      specification is a default plugin

  ## Configuration

      config :ltix,
        storage_adapter: MyApp.LtiStorage

  `handle_login/3` takes `:storage_adapter`, `:storage_adapter_options`, and
  `:plugins`. `handle_callback/3` takes `:storage_adapter`,
  `:storage_adapter_options`, `:allow_anonymous`, `:max_token_age`,
  `:local_network_access`, `:req_options`, `:key_set`, `:clock_skew`, and
  `:plugins`. An option passed to a call overrides the application
  configuration for that call. Unknown or invalid options raise
  `Ltix.Errors.Invalid.InvalidOption`.

  ### Required

    * `:storage_adapter` - module implementing `Ltix.StorageAdapter`.
      Looked up at runtime, so it works with releases.

  ### Optional

    * `:allow_anonymous` - when `true`, allow launches without a `sub`
      claim in the ID token. Defaults to `false`.

    * `:max_token_age` - seconds after the platform issued the ID token
      that the launch is still accepted, or `:infinity` to accept any age.
      Defaults to `3600`.

    * `:local_network_access` - the addresses platform requests may
      connect to besides public ones. `:local` adds private network
      addresses, and `:loopback` adds those and this machine. Defaults to
      `:none`. The functions that send platform requests take the same
      option. The `:finch`, `:adapter`, `:unix_socket`, and proxy options
      in `:req_options` need `:loopback`, because Ltix can't check the
      addresses they connect to.

    * `:json_library` - JSON encoder/decoder module. Detected at
      compile time, using `JSON` (Elixir 1.18+/OTP 27+) if available,
      then `Jason`. Only set this if you need a different library. With
      `JSON` or `Jason`, a token that repeats a claim has the last value.
      With another library, it has the value that library's `decode/1`
      returns.

    * `:req_options` - default options passed to `Req.request/2` for
      all HTTP calls, such as key set fetches, OAuth token requests, and
      service calls. Useful for setting timeouts, middleware, or test
      adapters.

          config :ltix, req_options: [receive_timeout: 10_000]

    * `:key_set` - name of the key set cache to get platform public keys
      from. Defaults to `Ltix.JWT.KeySet`. The key set cache must be
      started in your supervision tree.

    * `:default_key_size` - RSA key size in bits for `Ltix.JWK.generate/1`
      when no `:key_size` is given. Defaults to `4096`.

    * `:plugins` - the plugins for calls that run plugins, such as
      `handle_login/3` and `handle_callback/3`, each as `MyPlugin` or
      `{MyPlugin, opts}`. Defaults to `[]`. The
      [default plugins](`Ltix.DefaultPlugins`) always come first. See
      [Writing Plugins](writing-plugins.md).

          config :ltix, plugins: [{MyLibrary, tenant: "acme"}]

  ## Handling Launches

  The LTI launch flow requires two endpoints. In your login endpoint,
  call `handle_login/3` with the platform's login parameters and your
  launch URL.

      def login(conn, params) do
        launch_url = url(conn, ~p"/lti/launch")
        {:ok, %{redirect_uri: url, state: state}} =
          Ltix.handle_login(params, launch_url)

        conn
        |> put_session(:lti_state, state)
        |> redirect(external: url)
      end

  In your launch endpoint, call `handle_callback/3` with the POST
  params and the stored state.

      def launch(conn, params) do
        state = get_session(conn, :lti_state)
        {:ok, launch} = Ltix.handle_callback(params, state)

        # launch.claims has the parsed claims
        # launch.claims.target_link_uri is where to redirect
        # launch.claims.roles has the user's roles
      end

  ## Advantage Services

  After a successful launch, call platform services like roster queries
  and grade passback. Authenticate with the platform's token endpoint,
  then call service functions.

      {:ok, client} = Ltix.MembershipsService.authenticate(launch)
      {:ok, roster} = Ltix.MembershipsService.list_members(client)

      Enum.each(roster, fn member ->
        IO.puts("\#{member.name}: \#{inspect(member.roles)}")
      end)

  Post grades back to the platform's gradebook.

      {:ok, client} = Ltix.GradeService.authenticate(launch)
      :ok = Ltix.GradeService.post_score(client, score)

  See the [Advantage Services](advantage-services.md) guide for OAuth
  details, token lifecycle, and multi-service authentication.

  ## Deep Linking

  When a platform sends an `LtiDeepLinkingRequest` launch, the same
  `handle_callback/3` returns an `Ltix.Launch`. Branch on the
  message type and build a response.

      {:ok, launch} = Ltix.handle_callback(params, state)

      case launch.claims.message_type do
        "LtiDeepLinkingRequest" ->
          {:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
            url: "https://tool.example.com/activity/1",
            title: "Quiz 1"
          )

          {:ok, response} = Ltix.DeepLinking.build_response(launch, [link])
          # POST response.jwt to response.return_url

        "LtiResourceLinkRequest" ->
          render(conn, :launch, launch: launch)
      end

  See the [Deep Linking](deep-linking.md) guide for content item types,
  line items, and platform constraints.
  """

  alias Ltix.AppConfig
  alias Ltix.Errors
  alias Ltix.Launch
  alias Ltix.Login
  alias Ltix.Options
  alias Ltix.PluginSet
  alias Ltix.Step

  @login_schema Zoi.keyword(
                  [
                    storage_adapter: Zoi.module(),
                    storage_adapter_options: Zoi.keyword(Zoi.any()) |> Zoi.default([]),
                    plugins: Zoi.list(Zoi.any())
                  ],
                  unrecognized_keys: :error
                )

  @callback_schema Zoi.keyword(
                     [
                       storage_adapter: Zoi.module(),
                       storage_adapter_options: Zoi.keyword(Zoi.any()) |> Zoi.default([]),
                       allow_anonymous: Zoi.boolean(),
                       req_options: Zoi.keyword(Zoi.any()),
                       key_set: Zoi.atom(),
                       clock_skew: Zoi.integer() |> Zoi.non_negative(),
                       max_token_age:
                         Zoi.union([Zoi.integer() |> Zoi.positive(), Zoi.literal(:infinity)]),
                       local_network_access: Ltix.HTTP.local_network_access_option(),
                       plugins: Zoi.list(Zoi.any())
                     ],
                     unrecognized_keys: :error
                   )

  @doc """
  Handles a platform's login and builds the authentication request.

  The `redirect_uri` is the tool's launch URL where the platform will
  POST the authentication response.

  Returns `{:ok, %{redirect_uri: url, state: state}}` on success. Store
  `state` in the user's session for CSRF verification, then redirect the
  user agent to `redirect_uri`.

  Steps that plugins add to `Ltix.Login` run during the call, and the errors
  they return are returned. Returns
  `{:error, %Ltix.Errors.Unknown.InvalidPluginSet{}}` when the plugins
  conflict.

  ## Options

    * `:storage_adapter` - module implementing `Ltix.StorageAdapter`
      (defaults to application config)
    * `:storage_adapter_options` - keyword list passed to each storage
      adapter callback (defaults to `[]`)
    * `:plugins` - the plugins for this call, each as `MyPlugin` or
      `{MyPlugin, opts}` (defaults to the `:plugins` application
      configuration)
  """
  # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
  # [Sec §5.1.1.2](https://www.imsglobal.org/spec/security/v1p0/#step-2-authentication-request)
  @spec handle_login(params :: map(), redirect_uri :: String.t(), opts :: keyword()) ::
          {:ok, %{redirect_uri: String.t(), state: String.t()}} | {:error, Exception.t()}
  def handle_login(params, redirect_uri, opts \\ []) do
    opts = Options.parse!(opts, @login_schema)
    storage_adapter = Options.fetch_configured!(opts, :storage_adapter)

    meta = %{issuer: params["iss"], client_id: params["client_id"], redirect_uri: redirect_uri}

    :telemetry.span([:ltix, :login], meta, fn ->
      result =
        with {:ok, plugins} <- PluginSet.resolve(opts[:plugins]) do
          private = %{
            ltix_redirect_uri: redirect_uri,
            ltix_storage_adapter: storage_adapter,
            ltix_storage_adapter_options: Keyword.fetch!(opts, :storage_adapter_options)
          }

          run_login(%Login{params: params, private: private, plugins: plugins})
        end

      {result, meta}
    end)
  end

  defp run_login(login) do
    %Login{errors: errors, private: private} = Step.run(login)

    with :ok <- Errors.collect(errors),
         do:
           {:ok, %{redirect_uri: private.ltix_authentication_request, state: private.ltix_state}}
  end

  @doc """
  Same as `handle_login/3`, but returns the redirect or raises the error.

  Takes the same options as `handle_login/3`.

      %{redirect_uri: url, state: state} = Ltix.handle_login!(params, launch_url)
  """
  @spec handle_login!(params :: map(), redirect_uri :: String.t(), opts :: keyword()) ::
          %{redirect_uri: String.t(), state: String.t()}
  def handle_login!(params, redirect_uri, opts \\ []) do
    case handle_login(params, redirect_uri, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Handles the platform's authentication response and returns the verified
  launch.

  `params` are the parameters the platform posted to your launch URL. `state` is
  the state `handle_login/3` returned.

      {:ok, launch} = Ltix.handle_callback(params, get_session(conn, :lti_state))

  ## Errors

  Returns `{:error, error}` with an Ltix error when the launch fails. See
  [Error Handling](error-handling.md).

  `Ltix.Errors.Security.StateMismatch` usually means the browser didn't send
  the session cookie, so check the cookie's `SameSite` setting.
  [Getting Started](getting-started.md) shows the setting.

  Raises `Ltix.Errors.Invalid.InvalidOption` for an unknown or invalid option,
  or when no storage adapter is configured. Raises
  `Ltix.Errors.Unknown.KeySetNotStarted` when the key set cache isn't running.

  ## Options

    * `:storage_adapter` - module implementing `Ltix.StorageAdapter`
      (defaults to application config)
    * `:storage_adapter_options` - keyword list passed to each storage
      adapter callback (defaults to `[]`)
    * `:allow_anonymous` - allow launches without a `sub` claim
      (defaults to application config, then `false`)
    * `:req_options` - options passed to the HTTP client for key set fetches
    * `:key_set` - name of the key set cache to get platform public keys
      from (defaults to application config, then `Ltix.JWT.KeySet`)
    * `:clock_skew` - seconds of tolerance for the token's `exp`, `iat`, and
      `nbf` (defaults to `5`)
    * `:max_token_age` - seconds after the platform issued the ID token that
      the launch is still accepted, or `:infinity` to accept any age
      (defaults to application config, then `3600`)
    * `:local_network_access` - `:local` or `:loopback` to fetch the
      platform's keys from a private network address or this machine
      (defaults to application config, then `:none`)
    * `:plugins` - the plugins for this call, each as `MyPlugin` or
      `{MyPlugin, opts}` (defaults to the `:plugins` application
      configuration)
  """
  # [Sec §5.1.1.3](https://www.imsglobal.org/spec/security/v1p0/#step-3-authentication-response)
  # [Sec §5.1.3](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
  @spec handle_callback(params :: map(), state :: String.t(), opts :: keyword()) ::
          {:ok, Launch.t()} | {:error, Exception.t()}
  def handle_callback(params, state, opts \\ []) do
    opts = Options.parse!(opts, @callback_schema)
    storage_adapter = Options.fetch_configured!(opts, :storage_adapter)
    {plugins, opts} = Keyword.pop(opts, :plugins)
    {storage_adapter_options, opts} = Keyword.pop!(opts, :storage_adapter_options)

    launch_options =
      opts
      |> Keyword.delete(:storage_adapter)
      |> Keyword.put_new(:allow_anonymous, AppConfig.allow_anonymous_launches?())

    :telemetry.span([:ltix, :callback], %{}, fn ->
      result =
        with {:ok, plugins} <- PluginSet.resolve(plugins) do
          private = %{
            ltix_params: params,
            ltix_state: state,
            ltix_storage_adapter: storage_adapter,
            ltix_storage_adapter_options: storage_adapter_options,
            ltix_options: launch_options
          }

          run_launch(%Launch{private: private, plugins: plugins})
        end

      {result, callback_metadata(result)}
    end)
  end

  defp run_launch(launch) do
    launch = Step.run(launch)
    with :ok <- Errors.collect(launch.errors), do: {:ok, launch}
  end

  @doc """
  Same as `handle_callback/3`, but returns the launch or raises the error.

  Takes the same options as `handle_callback/3`.

      launch = Ltix.handle_callback!(params, state)
  """
  @spec handle_callback!(params :: map(), state :: String.t(), opts :: keyword()) :: Launch.t()
  def handle_callback!(params, state, opts \\ []) do
    case handle_callback(params, state, opts) do
      {:ok, launch} -> launch
      {:error, error} -> raise error
    end
  end

  defp callback_metadata({:ok, %Launch{registration: registration, claims: claims}}) do
    %{
      issuer: registration.issuer,
      client_id: registration.client_id,
      deployment_id: claims.deployment_id,
      message_type: claims.message_type
    }
  end

  defp callback_metadata({:error, _error}),
    do: %{issuer: nil, client_id: nil, deployment_id: nil, message_type: nil}
end
