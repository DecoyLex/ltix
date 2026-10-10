defmodule Ltix do
  @moduledoc """
  Ltix handles the LTI 1.3 OIDC launch flow for tool applications. It is
  built around 4 main components.

    * `Ltix.Registration` - what the tool stores about a platform (issuer,
      client_id, endpoints). Created during out-of-band registration

    * `Ltix.StorageAdapter` - behaviour your app implements to look up
      registrations, deployments, and manage nonces

    * `Ltix.LaunchContext` - the validated output of a successful launch,
      containing the parsed claims, registration, and deployment

    * `Ltix.LaunchClaims` - structured data parsed from the ID Token
      (roles, context, resource link, and more)

  ## Configuration

      config :ltix,
        storage_adapter: MyApp.LtiStorage

  `handle_login/3` takes `:storage_adapter` and `:storage_adapter_options`,
  and `handle_callback/3` takes both of those, `:allow_anonymous`, `:max_token_age`,
  `:local_network_access`, `:req_options`, and `:key_set`, to override the
  setting for a single call. Unknown or invalid options raise
  `Ltix.Errors.Invalid.InvalidOption`.

  ### Required

    * `:storage_adapter` - module implementing `Ltix.StorageAdapter`.
      Looked up at runtime, so it works with releases.

  ### Optional

    * `:allow_anonymous` - when `true`, allow launches without a `sub`
      claim in the ID Token. Defaults to `false`.

    * `:max_token_age` - seconds after the platform issued the ID Token
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
      all HTTP calls (JWKS fetching, OAuth token requests, service
      calls). Useful for setting timeouts, middleware, or test
      adapters.

          config :ltix, req_options: [receive_timeout: 10_000]

    * `:key_set` - name of the `Ltix.JWT.KeySet` to get platform public
      keys from. Defaults to `Ltix.JWT.KeySet`. The key set must be
      started in your supervision tree.

    * `:default_key_size` - RSA key size in bits for `Ltix.JWK.generate/1`
      when no `:key_size` is given. Defaults to `4096`.

  ### Launch claim parsers

  Custom claim and role parsers are configured under the
  `Ltix.LaunchClaims` key.

      config :ltix, Ltix.LaunchClaims,
        claim_parsers: %{
          "https://example.com/custom" => MyApp.CustomClaimParser
        },
        role_parsers: %{
          "https://example.com/roles/" => MyApp.CustomRoleParser
        }

  See [Custom Claim Parsers](custom-claim-parsers.md) and
  [Custom Role Parsers](custom-role-parsers.md) for details.

  ## Handling Launches

  The LTI launch flow requires two endpoints. In your login endpoint,
  call `handle_login/3` with the platform's initiation params and your
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
        {:ok, context} = Ltix.handle_callback(params, state)

        # context.claims has the parsed launch data
        # context.claims.target_link_uri is where to redirect
        # context.claims.roles tells you who the user is
      end

  ## Advantage Services

  After a successful launch, call platform services like roster queries
  and grade passback. Authenticate with the platform's token endpoint,
  then call service functions.

      {:ok, client} = Ltix.MembershipsService.authenticate(context)
      {:ok, roster} = Ltix.MembershipsService.list_members(client)

      Enum.each(roster, fn member ->
        IO.puts("\#{member.name}: \#{inspect(member.roles)}")
      end)

  Post grades back to the platform's gradebook.

      {:ok, client} = Ltix.GradeService.authenticate(context)
      :ok = Ltix.GradeService.post_score(client, score)

  See the [Advantage Services](advantage-services.md) guide for OAuth
  details, token lifecycle, and multi-service authentication.

  ## Deep Linking

  When a platform sends an `LtiDeepLinkingRequest` launch, the same
  `handle_callback/3` returns a `%LaunchContext{}`. Branch on the
  message type and build a response.

      {:ok, context} = Ltix.handle_callback(params, state)

      case context.claims.message_type do
        "LtiDeepLinkingRequest" ->
          {:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
            url: "https://tool.example.com/activity/1",
            title: "Quiz 1"
          )

          {:ok, response} = Ltix.DeepLinking.build_response(context, [link])
          # POST response.jwt to response.return_url

        "LtiResourceLinkRequest" ->
          redirect(conn, external: context.claims.target_link_uri)
      end

  See the [Deep Linking](deep-linking.md) guide for content item types,
  line items, and platform constraints.
  """

  alias Ltix.AppConfig
  alias Ltix.LaunchContext
  alias Ltix.OIDC.Callback
  alias Ltix.OIDC.LoginInitiation
  alias Ltix.Options

  @login_schema Zoi.keyword(
                  [
                    storage_adapter: Zoi.module(),
                    storage_adapter_options: Zoi.keyword(Zoi.any()) |> Zoi.default([])
                  ],
                  unrecognized_keys: :error
                )

  @callback_schema Zoi.keyword(
                     [
                       storage_adapter: Zoi.module(),
                       storage_adapter_options: Zoi.keyword(Zoi.any()) |> Zoi.default([]),
                       allow_anonymous: Zoi.boolean(),
                       req_options: Zoi.keyword(Zoi.any()),
                       claim_parsers: Zoi.map(Zoi.string(), Zoi.any()),
                       role_parsers: Zoi.map(Zoi.string(), Zoi.any()),
                       key_set: Zoi.atom(),
                       clock_skew: Zoi.integer() |> Zoi.non_negative(),
                       max_token_age:
                         Zoi.union([Zoi.integer() |> Zoi.positive(), Zoi.literal(:infinity)]),
                       local_network_access: Ltix.HTTP.local_network_access_option()
                     ],
                     unrecognized_keys: :error
                   )

  @doc """
  Handle a platform's login initiation and build an authorization redirect.

  The `redirect_uri` is the tool's launch URL where the platform will
  POST the authentication response.

  Returns `{:ok, %{redirect_uri: url, state: state}}` on success. Store
  `state` in the user's session for CSRF verification, then redirect the
  user agent to `redirect_uri`.

  ## Options

    * `:storage_adapter` - module implementing `Ltix.StorageAdapter`
      (defaults to application config)
    * `:storage_adapter_options` - keyword list passed to each storage
      adapter callback (defaults to `[]`)
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
        LoginInitiation.call(
          params,
          storage_adapter,
          redirect_uri,
          Keyword.fetch!(opts, :storage_adapter_options)
        )

      {result, meta}
    end)
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
  Handle an authentication response and validate the ID Token.

  Returns `{:ok, %LaunchContext{}}` on success with parsed claims, registration,
  and deployment. The `state` parameter should be the value stored in the
  session during `handle_login/3`.

  Use `context.claims.target_link_uri` for the final redirect destination.

  ## Options

    * `:storage_adapter` - module implementing `Ltix.StorageAdapter`
      (defaults to application config)
    * `:storage_adapter_options` - keyword list passed to each storage
      adapter callback (defaults to `[]`)
    * `:allow_anonymous` - allow launches without a `sub` claim
      (defaults to application config, then `false`)
    * `:req_options` - options passed to the HTTP client for JWKS fetching
    * `:key_set` - name of the `Ltix.JWT.KeySet` to get platform public keys
      from (defaults to application config, then `Ltix.JWT.KeySet`)
    * `:claim_parsers` - custom claim parsers (see `Ltix.LaunchClaims.from_json/2`)
    * `:role_parsers` - custom role parsers (see `Ltix.LaunchClaims.Role.parse/2`)
    * `:clock_skew` - seconds of tolerance for the token's `exp`, `iat`, and
      `nbf` (defaults to `5`)
    * `:max_token_age` - seconds after the platform issued the ID Token that
      the launch is still accepted, or `:infinity` to accept any age
      (defaults to application config, then `3600`)
    * `:local_network_access` - `:local` or `:loopback` to fetch the
      platform's keys from a private network address or this machine
      (defaults to application config, then `:none`)
  """
  # [Sec §5.1.1.3](https://www.imsglobal.org/spec/security/v1p0/#step-3-authentication-response)
  # [Sec §5.1.3](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
  @spec handle_callback(params :: map(), state :: String.t(), opts :: keyword()) ::
          {:ok, LaunchContext.t()} | {:error, Exception.t()}
  def handle_callback(params, state, opts \\ []) do
    opts = Options.parse!(opts, @callback_schema)
    storage_adapter = Options.fetch_configured!(opts, :storage_adapter)
    opts = Keyword.put_new(opts, :allow_anonymous, AppConfig.allow_anonymous_launches?())

    :telemetry.span([:ltix, :callback], %{}, fn ->
      case Callback.launch(params, state, storage_adapter, opts) do
        {:ok, context, registration} ->
          {{:ok, context}, callback_metadata(context, registration)}

        {:error, _error} = error ->
          {error, %{issuer: nil, client_id: nil, deployment_id: nil, message_type: nil}}
      end
    end)
  end

  @doc """
  Same as `handle_callback/3`, but returns the launch context or raises
  the error.

  Takes the same options as `handle_callback/3`.

      context = Ltix.handle_callback!(params, state)
  """
  @spec handle_callback!(params :: map(), state :: String.t(), opts :: keyword()) ::
          LaunchContext.t()
  def handle_callback!(params, state, opts \\ []) do
    case handle_callback(params, state, opts) do
      {:ok, context} -> context
      {:error, error} -> raise error
    end
  end

  defp callback_metadata(%LaunchContext{claims: claims}, registration) do
    %{
      issuer: registration.issuer,
      client_id: registration.client_id,
      deployment_id: claims.deployment_id,
      message_type: claims.message_type
    }
  end
end
