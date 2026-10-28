defmodule Ltix do
  @moduledoc """
  Ltix handles the tool side of LTI 1.3 launches, Advantage services, and Deep
  Linking.

  To set up a tool from scratch, follow [Getting Started](getting-started.md).

  ## Handling launches

  Your tool needs two endpoints for a launch. The login endpoint calls
  `handle_login/3`, keeps the state in the session, and redirects the browser to
  the platform.

      def login(conn, params) do
        launch_url = url(conn, ~p"/lti/launch")

        case Ltix.handle_login(params, launch_url) do
          {:ok, %{redirect_uri: redirect_uri, state: state}} ->
            conn
            |> put_session(:lti_state, state)
            |> redirect(external: redirect_uri)

          {:error, error} ->
            send_resp(conn, Ltix.Errors.status_code(error), "The launch could not be completed.")
        end
      end

  The platform then posts an ID token to the launch endpoint, which calls
  `handle_callback/3` with that state.

      def launch(conn, params) do
        state = get_session(conn, :lti_state)

        case Ltix.handle_callback(params, state) do
          {:ok, launch} ->
            conn
            |> delete_session(:lti_state)
            |> render(:launch, launch: launch)

          {:error, error} ->
            send_resp(conn, Ltix.Errors.status_code(error), "The launch could not be completed.")
        end
      end

  The browser sends the session cookie with the platform's cross-site post only
  when the cookie has `SameSite=None`. [Getting Started](getting-started.md)
  shows the setting.

  The parsed claims are in `launch.claims` (see `Ltix.Launch`).

  [Error Handling](error-handling.md) covers what each error means and how to
  respond.

  ## Advantage services

  Authenticate with a service using the launch, then call it.

      {:ok, client} = Ltix.GradeService.authenticate(launch)

      {:ok, score} =
        Ltix.GradeService.Score.new(
          user_id: launch.claims.subject,
          score_given: 85,
          score_maximum: 100,
          activity_progress: :completed,
          grading_progress: :fully_graded
        )

      :ok = Ltix.GradeService.post_score(client, score)

  See [Advantage Services](advantage-services.md). To call a service later, such
  as from a background job, see [Persisting Service
  Endpoints](persisting-service-endpoints.md).

  ## Deep Linking

  A Deep Linking request is a launch with the message type
  `"LtiDeepLinkingRequest"`. Respond with the content items the user picks.

      case launch.claims.message_type do
        "LtiDeepLinkingRequest" ->
          {:ok, link} =
            Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
              url: "https://tool.example.com/activity/1",
              title: "Quiz 1"
            )

          {:ok, response} = Ltix.DeepLinking.build_response(launch, [link])

          # The template has a form that posts response.jwt to response.return_url, in a field named JWT
          render(conn, :deep_linking_response, response: response)

        "LtiResourceLinkRequest" ->
          render(conn, :launch, launch: launch)
      end

  See [Deep Linking](deep-linking.md).

  ## Main modules

    * `Ltix.Registration` and `Ltix.Deployment` - what your tool stores about a
      platform and each deployment on it
    * `Ltix.StorageAdapter` - the behaviour your application implements to look
      up registrations and deployments, record used nonces, and sign your tool's
      messages
    * `Ltix.Launch` - a verified launch
    * `Ltix.Role` - role checks
    * `Ltix.GradeService`, `Ltix.MembershipsService`, and `Ltix.DeepLinking` -
      the Advantage services and Deep Linking
    * `Ltix.Plugin` - plugins that add claims, message types, content item
      types, and steps. See [Writing Plugins](writing-plugins.md).
    * `Ltix.Test` - a simulated platform for your tests

  ## Configuration

  Set defaults in your application configuration.

      config :ltix, storage_adapter: MyApp.LtiStorage

  An option passed to a call overrides the configured value for that call, and
  `:req_options` passed to a call are merged over the configured ones.

    * `:storage_adapter` - your `Ltix.StorageAdapter` module (required)
    * `:allow_anonymous` - when `true`, accept resource link launches without a
      `sub` claim (defaults to `false`)
    * `:max_token_age` - the maximum age of an ID token Ltix accepts, in
      seconds, or `:infinity` (defaults to `3600`)
    * `:local_network_access` - the non-public addresses Ltix may connect to
      when it calls a platform (defaults to `:none`). `:local` allows private
      network addresses, and `:loopback` allows those and this machine. The
      `:finch`, `:adapter`, `:unix_socket`, and proxy options in `:req_options`
      require `:loopback`, as do its `:tcp_module` and `:cb_info` transport
      options.
    * `:json_library` - the JSON module Ltix encodes and decodes with (defaults
      to `JSON` on Elixir 1.18 and OTP 27 or later, and to `Jason` otherwise).
      Ltix reads it at compile time. Set it in `config/config.exs`.
    * `:req_options` - options for `Req.request/2` on every platform request,
      such as timeouts, Req steps, or a `Req.Test` plug

          config :ltix, req_options: [receive_timeout: 10_000]

    * `:key_set` - the name of the `Ltix.JWT.KeySet` cache you start in your
      supervision tree (defaults to `Ltix.JWT.KeySet`)
    * `:default_key_size` - the RSA key size in bits for `Ltix.JWK.generate/1`
      (defaults to `4096`)
    * `:plugins` - plugins every call runs with, after the
      [default plugins](`Ltix.DefaultPlugins`), each as `MyPlugin` or
      `{MyPlugin, opts}` (defaults to `[]`). See
      [Writing Plugins](writing-plugins.md).

          config :ltix, plugins: [{MyPlugin, tenant: "acme"}]

  Pass these options to a call. They can't be configured.

    * `:storage_adapter_options` - a keyword list passed to each storage adapter
      callback (defaults to `[]`)
    * `:clock_skew` - seconds of tolerance for the ID token's `exp`, `iat`, and
      `nbf` claims in `handle_callback/3` (defaults to `5`)
  """

  alias Ltix.AppConfig
  alias Ltix.Errors
  alias Ltix.Launch
  alias Ltix.Login
  alias Ltix.Options
  alias Ltix.PluginSet
  alias Ltix.Step

  @storage_adapter_fields [
    storage_adapter: Zoi.module(description: "Your `Ltix.StorageAdapter` module."),
    storage_adapter_options:
      Zoi.keyword(Zoi.any(),
        description: "A keyword list passed to each storage adapter callback."
      )
      |> Zoi.default([])
  ]

  @plugins_option Zoi.list(Zoi.any(),
                    description:
                      "Plugins the call runs with, after the [default plugins](`Ltix.DefaultPlugins`), each as `MyPlugin` or `{MyPlugin, opts}`. Defaults to `[]`. See [Writing Plugins](writing-plugins.md)."
                  )

  @login_schema Zoi.keyword(@storage_adapter_fields ++ [plugins: @plugins_option],
                  unrecognized_keys: :error
                )

  @callback_schema Zoi.keyword(
                     @storage_adapter_fields ++
                       [
                         allow_anonymous:
                           Zoi.boolean(
                             description:
                               "When `true`, accept resource link launches without a `sub` claim. Defaults to `false`."
                           ),
                         max_token_age:
                           Zoi.union([Zoi.integer() |> Zoi.positive(), Zoi.literal(:infinity)],
                             description:
                               "The maximum age of an ID token Ltix accepts, in seconds, or `:infinity`. Defaults to `3600`."
                           ),
                         local_network_access: Ltix.HTTP.local_network_access_option(),
                         req_options:
                           Zoi.keyword(Zoi.any(),
                             description:
                               "Options for `Req.request/2` on the key set fetch, such as timeouts, Req steps, or a `Req.Test` plug. They're merged over the configured ones."
                           ),
                         key_set:
                           Zoi.atom(
                             description:
                               "The name of the `Ltix.JWT.KeySet` cache you start in your supervision tree. Defaults to `Ltix.JWT.KeySet`."
                           ),
                         clock_skew:
                           Zoi.integer(
                             description:
                               "Seconds of tolerance for the ID token's `exp`, `iat`, and `nbf` claims. Defaults to `5`."
                           )
                           |> Zoi.non_negative(),
                         plugins: @plugins_option
                       ],
                     unrecognized_keys: :error
                   )

  @doc """
  Handles a platform's login request and returns the authentication request to
  redirect the browser to.

  `params` are the request's query or form parameters. `redirect_uri` is your
  launch URL, and must be one of the redirect URIs the platform has for your
  tool.

      {:ok, %{redirect_uri: redirect_uri, state: state}} = Ltix.handle_login(params, launch_url)

  Keep `state` in the user's session for `handle_callback/3`, and redirect the
  browser to the returned `redirect_uri`, the platform's authentication URL.

  ## Errors

  Returns `{:error, error}` with an Ltix error when the login fails. See
  [Error Handling](error-handling.md).

  Raises `ArgumentError` for an unknown or invalid option, or when no storage
  adapter is configured.

  ## Options

  When you [configure](`m:Ltix#module-configuration`) an option, the configured
  value is its default.

  #{Zoi.describe(@login_schema)}
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
  Same as `handle_login/3` but raises on error.

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

  Raises `ArgumentError` for an unknown or invalid option, or when no storage
  adapter is configured. Raises `Ltix.Errors.Unknown.KeySetNotStarted` when
  the key set cache isn't running.

  ## Options

  When you [configure](`m:Ltix#module-configuration`) an option, the configured
  value is its default.

  #{Zoi.describe(@callback_schema)}
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
  Same as `handle_callback/3` but raises on error.

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
      deployment_id: claims[:deployment_id],
      message_type: claims[:message_type]
    }
  end

  defp callback_metadata({:error, _error}),
    do: %{issuer: nil, client_id: nil, deployment_id: nil, message_type: nil}
end
