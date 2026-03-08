defmodule Ltix do
  @moduledoc """
  Ltix handles the LTI 1.3 OIDC launch flow for tool applications. It is
  built around 4 main components:

    * `Ltix.Registration` — what the tool knows about a platform (issuer,
      client_id, endpoints). Created during out-of-band registration

    * `Ltix.StorageAdapter` — behaviour your app implements to look up
      registrations, deployments, and manage nonces

    * `Ltix.LaunchContext` — the validated output of a successful launch,
      containing the parsed claims, registration, and deployment

    * `Ltix.LaunchClaims` — structured data parsed from the ID Token
      (roles, context, resource link, and more)

  ## Configuration

      config :ltix,
        storage_adapter: MyApp.LtiStorage

  All configuration can be overridden per-call via opts.

  ## Handling Launches

  The LTI launch flow requires two endpoints. In your login endpoint,
  call `handle_login/3` with the platform's initiation params and your
  launch URL:

      def login(conn, params) do
        launch_url = url(conn, ~p"/lti/launch")
        {:ok, %{redirect_uri: url, state: state}} =
          Ltix.handle_login(params, launch_url)

        conn
        |> put_session(:lti_state, state)
        |> redirect(external: url)
      end

  In your launch endpoint, call `handle_callback/3` with the POST
  params and the stored state:

      def launch(conn, params) do
        state = get_session(conn, :lti_state)
        {:ok, context} = Ltix.handle_callback(params, state)

        # context.claims has the parsed launch data
        # context.claims.target_link_uri is where to redirect
        # context.claims.roles tells you who the user is
      end
  """

  alias Ltix.LaunchContext
  alias Ltix.OIDC.{Callback, LoginInitiation}

  @doc """
  Handle a platform's login initiation and build an authorization redirect.

  The `redirect_uri` is the tool's launch URL where the platform will
  POST the authentication response.

  Returns `{:ok, %{redirect_uri: url, state: state}}` on success. Store
  `state` in the user's session for CSRF verification, then redirect the
  user agent to `redirect_uri`.

  The nonce is stored via `Ltix.StorageAdapter.store_nonce/2` automatically.

  ## Options

    * `:storage_adapter` — module implementing `Ltix.StorageAdapter`
      (defaults to application config)
  """
  # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
  # [Sec §5.1.1.2](https://www.imsglobal.org/spec/security/v1p0/#step-2-authentication-request)
  @spec handle_login(params :: map(), redirect_uri :: String.t(), opts :: keyword()) ::
          {:ok, %{redirect_uri: String.t(), state: String.t()}} | {:error, Exception.t()}
  def handle_login(params, redirect_uri, opts \\ []) do
    {storage_adapter, _opts} = pop_required!(opts, :storage_adapter)

    LoginInitiation.call(params, storage_adapter, redirect_uri)
  end

  @doc """
  Handle an authentication response and validate the ID Token.

  Returns `{:ok, %LaunchContext{}}` on success with parsed claims, registration,
  and deployment. The `state` parameter should be the value stored in the
  session during `handle_login/2`.

  Use `context.claims.target_link_uri` for the final redirect destination.

  ## Options

    * `:storage_adapter` — module implementing `Ltix.StorageAdapter`
      (defaults to application config)
    * `:allow_anonymous` — allow launches without a `sub` claim
      (defaults to application config, then `false`)
    * `:req_options` — options passed to the HTTP client for JWKS fetching
    * `:clock_skew` — seconds of tolerance for token expiration (default: `5`)
  """
  # [Sec §5.1.1.3](https://www.imsglobal.org/spec/security/v1p0/#step-3-authentication-response)
  # [Sec §5.1.3](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
  @spec handle_callback(params :: map(), state :: String.t(), opts :: keyword()) ::
          {:ok, LaunchContext.t()} | {:error, Exception.t()}
  def handle_callback(params, state, opts \\ []) do
    {storage_adapter, opts} = pop_required!(opts, :storage_adapter)
    opts = ensure_optional(opts, :allow_anonymous)

    Callback.call(params, state, storage_adapter, opts)
  end

  defp pop_required!(opts, key) do
    case Keyword.pop(opts, key) do
      {nil, opts} ->
        case Application.get_env(:ltix, key) do
          nil ->
            raise ArgumentError,
                  "missing :#{key} configuration \u2014 set it in config.exs or pass it in opts"

          value ->
            {value, opts}
        end

      {value, opts} ->
        {value, opts}
    end
  end

  defp ensure_optional(opts, key) do
    if Keyword.has_key?(opts, key) do
      opts
    else
      case Application.get_env(:ltix, key) do
        nil -> opts
        value -> Keyword.put(opts, key, value)
      end
    end
  end
end
