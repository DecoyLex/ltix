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

  All configuration can also be passed (or overridden) per-call via opts.

  ### Required

    * `:storage_adapter` — module implementing `Ltix.StorageAdapter`.
      Looked up at runtime, so it works with releases.

  ### Optional

    * `:allow_anonymous` — when `true`, allow launches without a `sub`
      claim in the ID Token. Defaults to `false`.

    * `:json_library` — JSON encoder/decoder module. Detected at
      compile time: uses `JSON` (Elixir 1.18+/OTP 27+) if available,
      then `Jason`. Only set this if you need a different library.

    * `:req_options` — default options passed to `Req.request/2` for
      all HTTP calls (JWKS fetching, OAuth token requests, service
      calls). Useful for setting timeouts, middleware, or test
      adapters:

          config :ltix, req_options: [receive_timeout: 10_000]

    * `:jwks_cache` — module implementing `Ltix.JWT.KeySet.Cache` for
      caching platform public keys. Defaults to
      `Ltix.JWT.KeySet.EtsCache`. A `Ltix.JWT.KeySet.CachexCache`
      adapter is also provided.

    * `:cachex_cache_name` — Cachex cache name when using
      `Ltix.JWT.KeySet.CachexCache`. Defaults to `:ltix_jwks`.

  ### Launch claim parsers

  Custom claim and role parsers are configured under the
  `Ltix.LaunchClaims` key:

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

  ## Advantage Services

  After a successful launch, call platform services like roster queries
  and grade passback. Authenticate with the platform's token endpoint,
  then call service functions:

      {:ok, client} = Ltix.MembershipsService.authenticate(context)
      {:ok, roster} = Ltix.MembershipsService.get_members(client)

      Enum.each(roster, fn member ->
        IO.puts("\#{member.name}: \#{inspect(member.roles)}")
      end)

  Post grades back to the platform's gradebook:

      {:ok, client} = Ltix.GradeService.authenticate(context)
      :ok = Ltix.GradeService.post_score(client, score)

  See the [Advantage Services](advantage-services.md) guide for OAuth
  details, token lifecycle, and multi-service authentication.

  ## Deep Linking

  When a platform sends an `LtiDeepLinkingRequest` launch, the same
  `handle_callback/3` returns a `%LaunchContext{}`. Branch on the
  message type and build a response:

      {:ok, context} = Ltix.handle_callback(params, state)

      case context.claims.message_type do
        "LtiDeepLinkingRequest" ->
          {:ok, link} = Ltix.DeepLinking.ContentItem.LtiResourceLink.new(
            url: "https://tool.example.com/activity/1",
            title: "Quiz 1"
          )

          {:ok, response} = Ltix.DeepLinking.build_response(context, [link])
          # POST response.jwt to response.return_url

        "LtiResourceLinkRequest" ->
          # Normal launch flow
      end

  See the [Deep Linking](deep-linking.md) guide for content item types,
  line items, and platform constraints.
  """

  alias Ltix.AppConfig
  alias Ltix.LaunchContext
  alias Ltix.OIDC.Callback
  alias Ltix.OIDC.LoginInitiation

  @doc """
  Handle a platform's login initiation and build an authorization redirect.

  The `redirect_uri` is the tool's launch URL where the platform will
  POST the authentication response.

  Returns `{:ok, %{redirect_uri: url, state: state}}` on success. Store
  `state` in the user's session for CSRF verification, then redirect the
  user agent to `redirect_uri`.

  The nonce is stored via `c:Ltix.StorageAdapter.store_nonce/2` automatically.

  ## Options

    * `:storage_adapter` — module implementing `Ltix.StorageAdapter`
      (defaults to application config)
  """
  # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
  # [Sec §5.1.1.2](https://www.imsglobal.org/spec/security/v1p0/#step-2-authentication-request)
  @spec handle_login(params :: map(), redirect_uri :: String.t(), opts :: keyword()) ::
          {:ok, %{redirect_uri: String.t(), state: String.t()}} | {:error, Exception.t()}
  def handle_login(params, redirect_uri, opts \\ []) do
    {storage_adapter, _opts} = AppConfig.pop_required!(opts, :storage_adapter)

    meta = span_metadata(:handle_login_start, params)

    :telemetry.span([:ltix, :login], meta, fn ->
      result = LoginInitiation.call(params, storage_adapter, redirect_uri)
      {result, meta}
    end)
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
    * `:claim_parsers` — custom claim parser modules (see `Ltix.LaunchClaims.from_json/2`)
    * `:clock_skew` — seconds of tolerance for token expiration (default: `5`)
  """
  # [Sec §5.1.1.3](https://www.imsglobal.org/spec/security/v1p0/#step-3-authentication-response)
  # [Sec §5.1.3](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
  @spec handle_callback(params :: map(), state :: String.t(), opts :: keyword()) ::
          {:ok, LaunchContext.t()} | {:error, Exception.t()}
  def handle_callback(params, state, opts \\ []) do
    {storage_adapter, opts} = AppConfig.pop_required!(opts, :storage_adapter)
    opts = Keyword.put_new(opts, :allow_anonymous, AppConfig.allow_anonymous_launches?())

    :telemetry.span([:ltix, :callback], %{}, fn ->
      result = Callback.call(params, state, storage_adapter, opts)

      metadata = span_metadata(:handle_callback_stop, result)
      {result, metadata}
    end)
  end

  defp span_metadata(:handle_login_start, params) do
    %{
      issuer: params["iss"],
      client_id: params["client_id"],
      redirect_uri: params["redirect_uri"]
    }
  end

  defp span_metadata(:handle_callback_stop, {:ok, %LaunchContext{claims: claims}}) do
    %{
      issuer: claims.issuer,
      client_id: claims.audience,
      deployment_id: claims.deployment_id,
      message_type: claims.message_type
    }
  end

  defp span_metadata(:handle_callback_stop, {:error, _error}) do
    %{
      issuer: nil,
      client_id: nil,
      deployment_id: nil,
      message_type: nil
    }
  end
end
