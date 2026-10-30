defmodule Ltix.Test do
  @moduledoc """
  Helpers for testing an application that uses Ltix against a simulated
  platform.

  `setup_platform!/1` creates a test platform with its own signing key,
  registration, and deployment. The other helpers build the requests that
  platform sends, build launches directly, and stub its grade and memberships
  services. [Testing LTI Launches](testing-lti-launches.md) shows controller,
  business logic, and service tests.

      setup do
        %{platform: Ltix.Test.setup_platform!()}
      end

      test "instructors can manage grades", %{platform: platform} do
        launch = Ltix.Test.build_launch(platform, roles: [Ltix.Role.context_instructor()])

        assert MyApp.Permissions.can_manage_grades?(launch)
      end

  ## Setup

    * Route Ltix's requests through `Req.Test` in your test configuration.
      With `retry: false`, a stubbed failure returns at once.

          # config/test.exs
          config :ltix, req_options: [plug: {Req.Test, :ltix}, retry: false]

    * Start `Ltix.JWT.KeySet` in your supervision tree, as in production.
    * For a full launch with `launch_params/2`, make your storage adapter find
      the test platform's registration and deployment. Create them with
      `setup_platform!/1`'s `:registration` and `:deployment` options, or use
      `Ltix.Test.StorageAdapter`.

  ## Service stubs

  Each stub responds to one `Ltix.GradeService` or `Ltix.MembershipsService`
  operation, whatever platform the request goes to. `stub_token_response/1`
  responds to access token requests. Stubbing an operation again replaces its
  stub. A service request without a stub fails the test.

      Ltix.Test.stub_token_response()
      Ltix.Test.stub_post_score()

      launch =
        Ltix.Test.build_launch(platform, ags_endpoint: %{line_item: line_item, scopes: scopes})
      {:ok, client} = Ltix.GradeService.authenticate(launch)
      assert :ok = Ltix.GradeService.post_score(client, score)

  List stubs, such as `stub_list_members/2`, split results into pages of the
  call's `:per_page` size.

  Stubs work with `async: true`. To use them in a process your application
  supervises, see `allow_stubs/1`.

  To test a failing platform, pass `stub_token_response/1` or `stub_key_set/2`
  the response the platform sends. For an error or other custom response from
  a grade or memberships service, call `Req.Test.stub/2` with the service
  module, such as `Req.Test.stub(Ltix.GradeService, fn conn -> ... end)`. It
  replaces that service's `Ltix.Test` stubs.
  """

  @compile {:no_warn_undefined,
            [
              {Plug.Conn, :put_resp_header, 3},
              {Plug.Conn, :put_status, 2},
              {Plug.Conn, :send_resp, 3}
            ]}

  alias Ltix.AppConfig
  alias Ltix.Claims.Context
  alias Ltix.Claims.ResourceLink
  alias Ltix.DeepLinking.Settings
  alias Ltix.Deployment
  alias Ltix.Errors
  alias Ltix.Errors.Security.SignatureInvalid
  alias Ltix.GradeService
  alias Ltix.GradeService.Endpoint, as: GradeServiceEndpoint
  alias Ltix.GradeService.LineItem
  alias Ltix.GradeService.Result
  alias Ltix.JWT.KeySet
  alias Ltix.Launch
  alias Ltix.MembershipsService
  alias Ltix.MembershipsService.Endpoint, as: MembershipsServiceEndpoint
  alias Ltix.MembershipsService.Member
  alias Ltix.MembershipsService.MembershipContainer
  alias Ltix.OAuth.ClientCredentials
  alias Ltix.Options
  alias Ltix.PluginSet
  alias Ltix.PluginSet.Entry
  alias Ltix.Records
  alias Ltix.Registration
  alias Ltix.Role
  alias Ltix.Step
  alias Ltix.Test.Platform
  alias Ltix.Test.ServiceStub
  alias Ltix.Test.SetDeployment
  alias Ltix.Test.StorageAdapter
  alias Ltix.Test.StorageAdapterContract

  @default_issuer "https://platform.example.com"
  @default_client_id "tool-client-id"
  @default_deployment_id "deployment-001"

  @setup_platform_schema Zoi.keyword(
                           [
                             issuer: Zoi.string(),
                             client_id: Zoi.string(),
                             deployment_id: Zoi.string(),
                             registration: Zoi.any(),
                             deployment: Zoi.any(),
                             tool_jwk: Zoi.struct(Ltix.JWK)
                           ],
                           unrecognized_keys: :error
                         )

  @login_params_schema Zoi.keyword(
                         [
                           login_hint: Zoi.string() |> Zoi.default("user-hint"),
                           target_link_uri:
                             Zoi.string() |> Zoi.default("https://tool.example.com/launch")
                         ],
                         unrecognized_keys: :error
                       )

  @default_context %{id: "context-001"}

  @context_option Zoi.union(
                    [
                      Zoi.struct(Context),
                      Zoi.map(
                        %{
                          id: Zoi.nullish(Zoi.string()),
                          label: Zoi.nullish(Zoi.string()),
                          title: Zoi.nullish(Zoi.string()),
                          type: Zoi.nullish(Zoi.list(Zoi.string()))
                        },
                        unrecognized_keys: :preserve
                      )
                    ],
                    description:
                      "The context, as an `Ltix.Claims.Context` or a map of its fields and " <>
                        "property names. Its `:id` defaults to `\"context-001\"`."
                  )

  @launch_option_fields [
    message_type:
      Zoi.union([Zoi.enum([:resource_link, :deep_linking]), Zoi.string()],
        description:
          "One of `:resource_link`, `:deep_linking`, or a message type string, such as " <>
            "`\"LtiSubmissionReviewRequest\"`. A message type string adds no resource link or " <>
            "Deep Linking settings. Add the claims it requires with `:claims`."
      )
      |> Zoi.default(:resource_link),
    roles:
      Zoi.list(Zoi.string(),
        description: "The user's role URIs, such as `Ltix.Role.context_learner/0`."
      )
      |> Zoi.default([Role.context_instructor()]),
    subject:
      Zoi.nullable(Zoi.string(),
        description:
          "The user's subject identifier, or `nil` for an anonymous launch. " <>
            "Defaults to `\"user-12345\"`."
      ),
    name: Zoi.string(description: "The user's full name."),
    email: Zoi.string(description: "The user's email address."),
    given_name: Zoi.string(description: "The user's given name."),
    family_name: Zoi.string(description: "The user's family name."),
    target_link_uri:
      Zoi.string(description: "The URL the platform launches the user to.")
      |> Zoi.default("https://tool.example.com/launch"),
    context: @context_option,
    resource_link:
      Zoi.union(
        [
          Zoi.struct(ResourceLink),
          Zoi.map(
            %{
              id: Zoi.nullish(Zoi.string()),
              title: Zoi.nullish(Zoi.string()),
              description: Zoi.nullish(Zoi.string())
            },
            unrecognized_keys: :preserve
          )
        ],
        description:
          "The resource link, as an `Ltix.Claims.ResourceLink` or a map of its fields and " <>
            "property names. Defaults to `%{id: \"resource-link-001\", title: \"Example Assignment\"}`."
      ),
    deep_linking_settings:
      Zoi.union(
        [
          Zoi.struct(Settings),
          Zoi.map(
            %{
              deep_link_return_url: Zoi.nullish(Zoi.string()),
              accept_types: Zoi.nullish(Zoi.list(Zoi.string())),
              accept_presentation_document_targets: Zoi.nullish(Zoi.list(Zoi.string())),
              accept_media_types: Zoi.nullish(Zoi.string()),
              accept_multiple: Zoi.nullish(Zoi.boolean()),
              accept_line_item: Zoi.nullish(Zoi.boolean()),
              auto_create: Zoi.nullish(Zoi.boolean()),
              title: Zoi.nullish(Zoi.string()),
              text: Zoi.nullish(Zoi.string()),
              data: Zoi.nullish(Zoi.any())
            },
            unrecognized_keys: :preserve
          )
        ],
        description:
          "The Deep Linking settings, as an `Ltix.DeepLinking.Settings` or a map of its " <>
            "fields and property names. Fields you leave out allow every content item type and presentation " <>
            "target, and more than one content item."
      ),
    ags_endpoint:
      Zoi.union(
        [
          Zoi.struct(GradeServiceEndpoint),
          Zoi.map(
            %{
              scopes: Zoi.nullish(Zoi.list(Zoi.string())),
              line_items: Zoi.nullish(Zoi.string()),
              line_item: Zoi.nullish(Zoi.string())
            },
            unrecognized_keys: :preserve
          )
        ],
        description:
          "The grade service endpoint, as an `Ltix.GradeService.Endpoint` or a map of its " <>
            "fields and property names. The map must have `:scopes`. A launch without this option has no grade service endpoint."
      ),
    memberships_endpoint:
      Zoi.union(
        [
          Zoi.struct(MembershipsServiceEndpoint),
          Zoi.string(),
          Zoi.map(
            %{
              context_memberships_url: Zoi.nullish(Zoi.string()),
              service_versions: Zoi.nullish(Zoi.list(Zoi.string()))
            },
            unrecognized_keys: :preserve
          )
        ],
        description:
          "The memberships service endpoint, as an `Ltix.MembershipsService.Endpoint`, " <>
            "its URL, or a map of its fields and property names. Its `:service_versions` defaults to `[\"2.0\"]`. " <>
            "A launch without this option has no memberships service endpoint."
      ),
    claims:
      Zoi.map(Zoi.string(), Zoi.any(),
        description:
          "Raw claims, keyed by claim name, such as `\"sub\"` or a claim URI. They replace " <>
            "the built claims of the same name."
      )
  ]

  @launch_params_schema Zoi.keyword(
                          [
                            nonce:
                              Zoi.string(
                                description:
                                  "The nonce that `extract_nonce/1` returns from the login's authentication request."
                              )
                              |> Zoi.required(),
                            state:
                              Zoi.string(description: "The state `Ltix.handle_login/3` returned.")
                              |> Zoi.required(),
                            plugins:
                              Zoi.list(Zoi.any(),
                                description:
                                  "The plugins to build the claims with, after the " <>
                                    "[default plugins](`Ltix.DefaultPlugins`), each as `MyPlugin` or " <>
                                    "`{MyPlugin, opts}`. Defaults to `[]`."
                              )
                          ] ++ @launch_option_fields,
                          unrecognized_keys: :error
                        )

  @launch_options_schema Zoi.keyword(@launch_option_fields, unrecognized_keys: :error)

  @build_launch_schema Zoi.keyword(
                         @launch_option_fields ++
                           [
                             allow_anonymous:
                               Zoi.boolean(
                                 description:
                                   "When `true`, accept a resource link launch without a subject. " <>
                                     "Defaults to `false`."
                               ),
                             plugins:
                               Zoi.list(Zoi.any(),
                                 description:
                                   "The plugins the launch runs with, after the " <>
                                     "[default plugins](`Ltix.DefaultPlugins`), each as `MyPlugin` or " <>
                                     "`{MyPlugin, opts}`. Defaults to `[]`."
                               )
                           ],
                         unrecognized_keys: :error
                       )

  @stub_status_option Zoi.integer(
                        description:
                          "The response's HTTP status. Without `:body`, an error status " <>
                            "has an empty body."
                      )
                      |> Zoi.min(200)
                      |> Zoi.max(599)
                      |> Zoi.default(200)

  @stub_transport_error_option Zoi.atom(
                                 description:
                                   "A `Req.TransportError` reason, such as `:econnrefused` or " <>
                                     "`:timeout`, that fails the request without a response. " <>
                                     "It can't be combined with other options."
                               )

  @stub_token_response_schema Zoi.keyword(
                                [
                                  scopes:
                                    Zoi.list(Zoi.string(),
                                      description:
                                        "The granted scope URIs. An empty list grants every " <>
                                          "scope the client requests."
                                    )
                                    |> Zoi.default([]),
                                  access_token:
                                    Zoi.string(description: "The token string.")
                                    |> Zoi.default("test-token"),
                                  expires_in:
                                    Zoi.integer(description: "The token lifetime in seconds.")
                                    |> Zoi.default(3600),
                                  status: @stub_status_option,
                                  body:
                                    Zoi.any(
                                      description:
                                        "The body the token endpoint responds with. A string is " <>
                                          "sent as text, and anything else as JSON."
                                    ),
                                  transport_error: @stub_transport_error_option
                                ],
                                unrecognized_keys: :error
                              )

  @stub_key_set_schema Zoi.keyword(
                         [
                           status: @stub_status_option,
                           body:
                             Zoi.any(
                               description:
                                 "The body the key set URL responds with. A string is " <>
                                   "sent as text, and anything else as JSON."
                             ),
                           transport_error: @stub_transport_error_option
                         ],
                         unrecognized_keys: :error
                       )

  @stub_plugins_option Zoi.list(Zoi.any(),
                         description:
                           "The plugins to serialize properties with, after the " <>
                             "[default plugins](`Ltix.DefaultPlugins`), each as `MyPlugin` or " <>
                             "`{MyPlugin, opts}`. Defaults to `[]`."
                       )

  @stub_line_item_option Zoi.union([Zoi.string(), Zoi.struct(LineItem)],
                           description:
                             "The line item, as its URL or struct. The stub responds only to requests for " <>
                               "this line item, and replaces only the stub for it."
                         )

  @stub_line_item_schema Zoi.keyword([line_item: @stub_line_item_option],
                           unrecognized_keys: :error
                         )

  @stub_line_item_and_plugins_schema Zoi.keyword(
                                       [
                                         line_item: @stub_line_item_option,
                                         plugins: @stub_plugins_option
                                       ],
                                       unrecognized_keys: :error
                                     )

  @stub_plugins_schema Zoi.keyword([plugins: @stub_plugins_option], unrecognized_keys: :error)

  @stub_list_members_schema Zoi.keyword(
                              [
                                context: @context_option,
                                id:
                                  Zoi.string(
                                    description: "The membership container's `id`, a URL."
                                  ),
                                plugins: @stub_plugins_option
                              ],
                              unrecognized_keys: :error
                            )

  @sign_id_token_schema Zoi.keyword(
                          [
                            kid:
                              Zoi.nullable(Zoi.string(),
                                description:
                                  "Key ID for the token header. Defaults to the key's `kid`. Pass `nil` to leave it out."
                              ),
                            alg:
                              Zoi.string(description: "Signing algorithm.")
                              |> Zoi.default("RS256")
                          ],
                          unrecognized_keys: :error
                        )

  # --- Platform Setup ---

  @doc group: "Platform"
  @doc """
  Set up a simulated LTI platform in one call.

  Generates platform-side RSA keys, builds a registration and deployment,
  and stubs the key set URL. The configured key set cache must be
  started. Your application's own storage adapter (configured via
  `config :ltix, storage_adapter: ...`) handles persistence during the OIDC
  flow.

  ## Options

    * `:issuer` - platform issuer URL (defaults to `"https://platform.example.com"`)
    * `:client_id` - OAuth client ID (defaults to `"tool-client-id"`)
    * `:deployment_id` - deployment identifier (defaults to `"deployment-001"`)
    * `:registration` - either an app struct implementing `Ltix.Registerable`
      (mutually exclusive with `:issuer` and `:client_id`), or a 1-arity
      function that receives an `Ltix.Registration` and returns your
      application's struct. The function form lets you create a matching record in your
      own persistence layer using the registration details (issuer,
      client_id, endpoints). Works with `:issuer` and `:client_id`
      overrides.
    * `:deployment` - either an app struct implementing `Ltix.Deployable`
      (mutually exclusive with `:deployment_id`), or a 2-arity function
      `(Ltix.Deployment, registration)` where `registration` is whatever
      the registration step returned. Lets you create a deployment record
      linked to your registration.
    * `:tool_jwk` - the `Ltix.JWK` your tool signs with for this platform.
      Pass the key your own storage adapter signs with. Defaults to the
      key `Ltix.Test.StorageAdapter` signs with.
  """
  @spec setup_platform!(keyword()) :: Platform.t()
  def setup_platform!(opts \\ []) do
    opts = Options.parse!(opts, @setup_platform_schema)
    validate_setup_opts!(opts)

    jwk = Ltix.JWK.generate(key_size: 2048)

    registration = build_or_use_registration(opts)
    deployment = build_or_use_deployment(opts, registration)

    platform = %Platform{
      registration: registration,
      deployment: deployment,
      jwk: jwk,
      tool_jwk: Keyword.get_lazy(opts, :tool_jwk, &StorageAdapter.tool_jwk/0)
    }

    # Eagerly validate protocol implementations. `stub_key_set/2` resolves the
    # registration.
    resolved_deployment(platform)
    stub_key_set(platform)

    platform
  end

  @doc group: "Platform"
  @doc """
  Stubs the response to the test platform's key set URL.

  Without options, it serves the platform's keys, which `setup_platform!/1`
  already stubs. Pass options to test how your application handles a failing
  key set. `Ltix.handle_callback/3` then returns the error in the table below.

      Ltix.Test.stub_key_set(platform, status: 503)

      {:error, %Ltix.Errors.Unknown.TransportError{status: 503}} =
        Ltix.handle_callback(params, state)

  | Options | Launch error |
  |---|---|
  | `status: 401` or `status: 403` | `Ltix.Errors.Security.AccessDenied` |
  | any other error `:status` | `Ltix.Errors.Unknown.TransportError` |
  | `transport_error: :timeout` | `Ltix.Errors.Unknown.TransportError` |
  | `body: "<html>Maintenance</html>"` | `Ltix.Errors.Invalid.MalformedResponse` |
  | `body: %{"keys" => []}` | `Ltix.Errors.Security.KidNotFound` |

  Tests that run at the same time with the same key set URL can receive each
  other's key set responses. If you pass `setup_platform!/1` a `:registration`
  struct, give each test's registration its own `jwks_uri`.

  ## Options

  #{Zoi.describe(@stub_key_set_schema)}
  """
  @spec stub_key_set(Platform.t(), keyword()) :: :ok
  def stub_key_set(%Platform{} = platform, opts \\ []) do
    parsed = Options.parse!(opts, @stub_key_set_schema)
    reject_combined_options!(opts, :transport_error, [:status, :body])
    %Registration{jwks_uri: key_set_url} = resolved_registration(platform)
    response = stub_response(parsed, Ltix.JWK.to_jwks(platform.jwk))

    ServiceStub.put(KeySet, :key_set, key_set_url, fn conn ->
      response.(Plug.Conn.put_resp_header(conn, "cache-control", "max-age=300"))
    end)

    KeySet.expire_keys(key_set_url)
  end

  # The platform's response for the `:status`, `:body`, and `:transport_error`
  # of `opts`. A success status without `:body` sends `success_body`.
  defp stub_response(opts, success_body) do
    ServiceStub.require_plug!()

    case Keyword.fetch(opts, :transport_error) do
      {:ok, reason} ->
        validate_transport_error!(reason)
        &Req.Test.transport_error(&1, reason)

      :error ->
        status = Keyword.fetch!(opts, :status)

        if status in 300..399 do
          Options.invalid!(:status, "it must be a success or error status")
        end

        default = if status in 200..299, do: success_body, else: ""
        body = Keyword.get(opts, :body, default)
        &send_stub_body(Plug.Conn.put_status(&1, status), body)
    end
  end

  # `Req.Test.transport_error/2` checks its reason only when a request fails
  # with it, so the stub checks it up front.
  defp validate_transport_error!(reason) do
    Req.Test.transport_error(struct(Plug.Conn), reason)
  rescue
    ArgumentError ->
      reraise ArgumentError,
              [
                message:
                  "Option :transport_error is invalid, it isn't a Req.TransportError reason"
              ],
              __STACKTRACE__
  end

  defp send_stub_body(conn, body) when is_binary(body), do: Req.Test.text(conn, body)
  defp send_stub_body(conn, body), do: Req.Test.json(conn, body)

  @doc group: "Platform"
  @doc """
  Lets `pid` use the test process's stubs and its `Ltix.Test.StorageAdapter`,
  including those the test sets afterward.

  Processes the test starts, such as tasks, LiveViews, and
  `start_supervised/2` children, already use them. Call `allow_stubs/1` for
  any other process, such as one your application supervises, before it
  handles a launch or sends requests to the test platform.

      Ltix.Test.stub_token_response()
      Ltix.Test.stub_post_score()
      Ltix.Test.allow_stubs(Process.whereis(MyApp.GradeSync))

  `pid` can be a function that returns the process. Allow the stubs of your own
  services with `Req.Test.allow/3`.
  """
  @spec allow_stubs(pid() | (-> pid())) :: :ok
  def allow_stubs(pid), do: ServiceStub.allow(pid)

  @doc group: "Storage adapter"
  @doc """
  Assert that a storage adapter satisfies `Ltix.StorageAdapter`.

  Checks registration and deployment lookups, returned records, and nonce
  replay prevention. For an adapter that exports `key_id/2` and `sign/4`,
  also checks that its signatures verify against your published key set
  and that it returns an error for a key ID it can't sign with. Returns
  `:ok` or raises `ExUnit.AssertionError` with the failing contract check.

  Two parts of the contract can't be checked from outside your storage,
  that nonce records are kept until `expires_at` and that storage failures
  return `{:error, reason}`.

  The deployment, nonce, and signing callbacks receive the registration
  record your adapter's `get_registration/3` returns, as they do in a launch.

  Use isolated test storage and your application's normal test cleanup.

  ## Options

    * `:registration` is a required 1-arity factory. Receives a valid
      `Ltix.Registration` and returns your stored record implementing
      `Ltix.Registerable`. Preserve the supplied issuer and client ID.
    * `:deployment` is a required 2-arity factory. Receives an
      `Ltix.Deployment` and your registration record. Returns the stored
      record implementing `Ltix.Deployable`. Preserve the supplied deployment
      ID. Lookups must return the same stored record.
    * `:registration_identity` and `:deployment_identity` are optional 1-arity
      functions that return a record's storage identity, such as `& &1.id`.
      By default, the complete factory and lookup records must match. Use
      these functions when lookups preload associations or change metadata.
      Protocol-converted fields must still match.
    * `:jwks` is a 1-arity function that receives a registration record and
      returns the key set your tool publishes for it, such as the result of
      `Ltix.JWK.to_jwks/1`. Required when the adapter exports `key_id/2` and
      `sign/4`, and rejected when it exports neither. The key set must
      include the key `key_id/2` returns, without private keys.
    * `:storage_adapter_options` is the keyword list each callback receives
      as its last argument. Defaults to `[]`.
    * `:prepare_process` is a 0-arity function called in each concurrent
      callback process. Use it to allow database sandbox access or set
      process-local adapter state. Defaults to a no-op.
    * `:auto_create_deployments` defaults to `false`, requiring missing
      deployments to return `{:error, :not_found}`. Set to `true` for adapters
      that create a deployment when none exists. Return distinct storage
      identities to check that registrations with the same deployment ID
      get separate automatically created deployments.
    * `:timeout` is the positive timeout in milliseconds for concurrent
      process preparation and validation. Defaults to `5000`.

      test "storage adapter satisfies the contract" do
        parent = self()

        :ok = Ltix.Test.assert_storage_adapter!(MyApp.LtiStorage,
          registration: fn registration ->
            MyApp.Lti.create_registration!(Map.from_struct(registration))
          end,
          deployment: fn deployment, registration ->
            MyApp.Lti.create_deployment!(%{
              deployment_id: deployment.deployment_id,
              registration_id: registration.id
            })
          end,
          prepare_process: fn ->
            Ecto.Adapters.SQL.Sandbox.allow(MyApp.Repo, parent, self())
          end
        )
      end
  """
  @spec assert_storage_adapter!(module(), keyword()) :: :ok
  def assert_storage_adapter!(adapter, opts), do: StorageAdapterContract.verify!(adapter, opts)

  # --- Request Builders ---

  @doc group: "Login and launch"
  @doc """
  Build POST params for `Ltix.handle_login/3`.

  ## Options

    * `:login_hint` - login hint value (defaults to `"user-hint"`)
    * `:target_link_uri` - launch URL (defaults to `"https://tool.example.com/launch"`)
  """
  @spec login_params(Platform.t(), keyword()) :: map()
  def login_params(%Platform{} = platform, opts \\ []) do
    opts = Options.parse!(opts, @login_params_schema)

    %{
      "iss" => resolved_registration(platform).issuer,
      "login_hint" => Keyword.fetch!(opts, :login_hint),
      "target_link_uri" => Keyword.fetch!(opts, :target_link_uri)
    }
  end

  @doc group: "Login and launch"
  @doc """
  Returns the parameters the test platform posts to your launch URL, for
  `Ltix.handle_callback/3` or your own post in a controller test.

  They're `%{"id_token" => id_token, "state" => state}`, with the ID token
  signed by the platform's key.

      params =
        Ltix.Test.launch_params(platform,
          nonce: nonce,
          state: state,
          roles: [Ltix.Role.context_learner()]
        )

  ## Options

  When you [configure](`m:Ltix#module-configuration`) an option, the configured
  value is its default.

  #{Zoi.describe(@launch_params_schema)}
  """
  @spec launch_params(Platform.t(), keyword()) :: map()
  def launch_params(%Platform{} = platform, opts) do
    opts = Options.parse!(opts, @launch_params_schema)
    {nonce, opts} = Keyword.pop!(opts, :nonce)
    {state, opts} = Keyword.pop!(opts, :state)
    {enabled, opts} = Keyword.pop(opts, :plugins)

    claims =
      Map.put(build_claims(platform, opts, ok!(PluginSet.resolve(enabled))), "nonce", nonce)

    %{"id_token" => sign_id_token(claims, platform.jwk), "state" => state}
  end

  @doc group: "Login and launch"
  @doc """
  Extract the nonce from a login redirect URI.

      {:ok, result} = Ltix.handle_login(params, redirect_uri)
      nonce = Ltix.Test.extract_nonce(result.redirect_uri)
  """
  @spec extract_nonce(String.t()) :: String.t()
  def extract_nonce(redirect_uri) do
    redirect_uri
    |> URI.parse()
    |> Map.get(:query)
    |> URI.decode_query()
    |> Map.fetch!("nonce")
  end

  # --- Direct Launch Construction ---

  @doc group: "Login and launch"
  @doc """
  Returns a launch from the test platform without the login flow, for testing
  code that takes an `Ltix.Launch`.

  It skips the security checks and the storage adapter. Otherwise the launch
  matches what `Ltix.handle_callback/3` returns for `launch_params/2` with the
  same options, apart from Ltix's own data in `:private`. Plugins' launch steps
  run too. Raises the failing step's error, such as
  `Ltix.Errors.Invalid.MissingClaim`.

      launch = Ltix.Test.build_launch(platform,
        roles: [Ltix.Role.context_instructor(), Ltix.Role.instructor_teaching_assistant()],
        name: "Jane Smith",
        context: %{id: "course-1", title: "Elixir 101"}
      )

  This builds a Deep Linking launch.

      launch = Ltix.Test.build_launch(platform,
        message_type: :deep_linking,
        deep_linking_settings: %{accept_types: ["ltiResourceLink"]}
      )

  ## Options

  When you [configure](`m:Ltix#module-configuration`) an option, the configured
  value is its default.

  #{Zoi.describe(@build_launch_schema)}
  """
  @spec build_launch(Platform.t(), keyword()) :: Launch.t()
  def build_launch(%Platform{} = platform, opts \\ []) do
    opts = Options.parse!(opts, @build_launch_schema)
    {enabled, opts} = Keyword.pop(opts, :plugins)

    {allow_anonymous, opts} =
      Keyword.pop_lazy(opts, :allow_anonymous, &AppConfig.allow_anonymous_launches?/0)

    plugins = ok!(PluginSet.resolve(enabled))

    steps = Enum.flat_map(PluginSet.entries(plugins, Launch), &build_launch_step(&1, platform))

    launch = %Launch{
      registration: resolved_registration(platform),
      source_registration: platform.registration,
      raw: build_claims(platform, opts, plugins),
      private: %{ltix_options: [allow_anonymous: allow_anonymous]},
      plugins: plugins
    }

    launch = Step.run(launch, steps)

    case Errors.collect(launch.errors) do
      :ok -> launch
      {:error, error} -> raise error
    end
  end

  defp build_launch_step(%Entry{module: Launch.LookUpDeployment} = entry, platform) do
    [
      %{
        entry
        | module: SetDeployment,
          opts: [
            deployment: resolved_deployment(platform),
            source_deployment: platform.deployment
          ]
      }
    ]
  end

  defp build_launch_step(%Entry{module: step} = entry, _platform) do
    if step in Ltix.Core.security_steps(), do: [], else: [entry]
  end

  # --- Service Test Helpers ---

  @doc group: "Service stubs"
  @doc """
  Stubs the platform's OAuth token endpoint for Advantage service tests. Call
  it before a service's `authenticate/2`, such as
  `Ltix.GradeService.authenticate/2`.

      Ltix.Test.stub_token_response(scopes: [
        "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
        "https://purl.imsglobal.org/spec/lti-ags/scope/score"
      ])

  To test a failed authentication, stub the response the platform would send.
  `authenticate/2` then returns the error in the table below.

      Ltix.Test.stub_token_response(status: 400, body: %{"error" => "invalid_scope"})

      {:error, %Ltix.Errors.Invalid.TokenRequestFailed{error: "invalid_scope"}} =
        Ltix.GradeService.authenticate(launch)

  | Options | Authentication error |
  |---|---|
  | an error `:status`, with any `:body` | `Ltix.Errors.Invalid.TokenRequestFailed` |
  | `transport_error: :econnrefused` | `Ltix.Errors.Unknown.TransportError` |
  | `body: "<html>Maintenance</html>"` | `Ltix.Errors.Invalid.MalformedResponse` |

  ## Options

  #{Zoi.describe(@stub_token_response_schema)}
  """
  @spec stub_token_response(keyword()) :: :ok
  def stub_token_response(opts \\ []) do
    parsed = Options.parse!(opts, @stub_token_response_schema)
    token_options = [:scopes, :access_token, :expires_in]
    reject_combined_options!(opts, :transport_error, [:status, :body | token_options])
    reject_combined_options!(opts, :body, token_options)

    if parsed[:status] not in 200..299,
      do: reject_combined_options!(opts, :status, token_options)

    scopes = Keyword.fetch!(parsed, :scopes)

    token = %{
      "access_token" => Keyword.fetch!(parsed, :access_token),
      "token_type" => "Bearer",
      "expires_in" => Keyword.fetch!(parsed, :expires_in)
    }

    token = if scopes == [], do: token, else: Map.put(token, "scope", Enum.join(scopes, " "))
    ServiceStub.put(ClientCredentials, :token_response, nil, stub_response(parsed, token))
  end

  # --- Grade Service Stubs ---

  @doc group: "Service stubs"
  @doc """
  Stubs `Ltix.GradeService.list_line_items/2` and
  `Ltix.GradeService.stream_line_items/2` to return the given line items.

      alias Ltix.GradeService.LineItem

      Ltix.Test.stub_list_line_items([
        %LineItem{id: "https://lms.example.com/lineitems/1", label: "Quiz 1", score_maximum: 100},
        %LineItem{id: "https://lms.example.com/lineitems/2", label: "Quiz 2", score_maximum: 50}
      ])

  ## Options

  When you [configure](`m:Ltix#module-configuration`) an option, the configured
  value is its default.

  #{Zoi.describe(@stub_plugins_schema)}
  """
  @spec stub_list_line_items([LineItem.t()], keyword()) :: :ok
  def stub_list_line_items(line_items, opts \\ []) when is_list(line_items) do
    opts = Options.parse!(opts, @stub_plugins_schema)
    json = Enum.map(line_items, &stub_json(&1, opts[:plugins]))
    ServiceStub.put(GradeService, :list_line_items, nil, &ServiceStub.json_pages(&1, json))
  end

  @doc group: "Service stubs"
  @doc """
  Stubs `Ltix.GradeService.get_line_item/2` to return the given line item.

      Ltix.Test.stub_get_line_item(%Ltix.GradeService.LineItem{
        id: "https://lms.example.com/lineitems/1",
        label: "Quiz 1",
        score_maximum: 100
      })

  ## Options

  When you [configure](`m:Ltix#module-configuration`) an option, the configured
  value is its default.

  #{Zoi.describe(@stub_line_item_and_plugins_schema)}
  """
  @spec stub_get_line_item(LineItem.t(), keyword()) :: :ok
  def stub_get_line_item(%LineItem{} = item, opts \\ []),
    do: stub_line_item(:get_line_item, item, opts)

  @doc group: "Service stubs"
  @doc """
  Stubs `Ltix.GradeService.create_line_item/3` to return the given line item.

  Pass the line item the platform would return. That's usually the fields your
  code sends, plus the `:id` the platform assigns.

      Ltix.Test.stub_create_line_item(%Ltix.GradeService.LineItem{
        id: "https://lms.example.com/lineitems/new",
        label: "Quiz 1",
        score_maximum: 100
      })

  ## Options

  When you [configure](`m:Ltix#module-configuration`) an option, the configured
  value is its default.

  #{Zoi.describe(@stub_plugins_schema)}
  """
  @spec stub_create_line_item(LineItem.t(), keyword()) :: :ok
  def stub_create_line_item(%LineItem{} = item, opts \\ []) do
    opts = Options.parse!(opts, @stub_plugins_schema)
    json = stub_json(item, opts[:plugins])

    ServiceStub.put(GradeService, :create_line_item, nil, fn conn ->
      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(json)
    end)
  end

  @doc group: "Service stubs"
  @doc """
  Stubs `Ltix.GradeService.update_line_item/3` to return the given line item.

      Ltix.Test.stub_update_line_item(%Ltix.GradeService.LineItem{
        id: "https://lms.example.com/lineitems/1",
        label: "Updated Quiz",
        score_maximum: 100
      })

  ## Options

  When you [configure](`m:Ltix#module-configuration`) an option, the configured
  value is its default.

  #{Zoi.describe(@stub_line_item_and_plugins_schema)}
  """
  @spec stub_update_line_item(LineItem.t(), keyword()) :: :ok
  def stub_update_line_item(%LineItem{} = item, opts \\ []),
    do: stub_line_item(:update_line_item, item, opts)

  defp stub_line_item(operation, item, opts) do
    opts = Options.parse!(opts, @stub_line_item_and_plugins_schema)
    json = stub_json(item, opts[:plugins])
    url = stub_line_item_url(opts)
    ServiceStub.put(GradeService, operation, url, &Req.Test.json(&1, json))
  end

  defp stub_json(value, enabled), do: platform_json(value, ok!(PluginSet.resolve(enabled)))

  @doc group: "Service stubs"
  @doc """
  Stub `delete_line_item/2` to succeed.

      Ltix.Test.stub_delete_line_item()

  ## Options

  #{Zoi.describe(@stub_line_item_schema)}
  """
  @spec stub_delete_line_item(keyword()) :: :ok
  def stub_delete_line_item(opts \\ []) do
    url = stub_line_item_url(Options.parse!(opts, @stub_line_item_schema))
    ServiceStub.put(GradeService, :delete_line_item, url, &Plug.Conn.send_resp(&1, 204, ""))
  end

  @doc group: "Service stubs"
  @doc """
  Stub `post_score/3` to succeed.

      Ltix.Test.stub_post_score()

  ## Options

  #{Zoi.describe(@stub_line_item_schema)}
  """
  @spec stub_post_score(keyword()) :: :ok
  def stub_post_score(opts \\ []) do
    url = stub_line_item_url(Options.parse!(opts, @stub_line_item_schema))
    ServiceStub.put(GradeService, :post_score, url, &Plug.Conn.send_resp(&1, 200, ""))
  end

  @doc group: "Service stubs"
  @doc """
  Stubs `Ltix.GradeService.list_results/2` and
  `Ltix.GradeService.stream_results/2` to return the given results.

      alias Ltix.GradeService.Result

      Ltix.Test.stub_list_results([
        %Result{user_id: "student-1", result_score: 0.85, result_maximum: 1},
        %Result{user_id: "student-2", result_score: 0.92, result_maximum: 1}
      ])

  ## Options

  When you [configure](`m:Ltix#module-configuration`) an option, the configured
  value is its default.

  #{Zoi.describe(@stub_line_item_and_plugins_schema)}
  """
  @spec stub_list_results([Result.t()], keyword()) :: :ok
  def stub_list_results(results, opts \\ []) when is_list(results) do
    opts = Options.parse!(opts, @stub_line_item_and_plugins_schema)
    json = Enum.map(results, &stub_json(&1, opts[:plugins]))
    url = stub_line_item_url(opts)
    ServiceStub.put(GradeService, :list_results, url, &ServiceStub.json_pages(&1, json))
  end

  defp stub_line_item_url(opts) do
    case Keyword.fetch(opts, :line_item) do
      :error ->
        nil

      {:ok, %LineItem{id: nil}} ->
        Options.invalid!(:line_item, "the line item has no id")

      {:ok, %LineItem{id: url}} ->
        url

      {:ok, url} ->
        url
    end
  end

  # --- Memberships Service Stubs ---

  @doc group: "Service stubs"
  @doc """
  Stubs `Ltix.MembershipsService.list_members/2` and
  `Ltix.MembershipsService.stream_members/2` to return the given members or
  membership container.

      alias Ltix.MembershipsService.Member

      members = [
        %Member{user_id: "student-1", roles: [Ltix.Role.context_learner()], name: "Alice"},
        %Member{user_id: "teacher-1", roles: [Ltix.Role.context_instructor()], name: "Bob"}
      ]

      Ltix.Test.stub_list_members(members)

  Pass an `Ltix.MembershipsService.MembershipContainer` to return its `id`,
  `context`, and extensions too. With a container, passing `:context` or `:id`
  raises `ArgumentError`.

      roster = %Ltix.MembershipsService.MembershipContainer{
        context: %Ltix.Claims.Context{id: "course-42"},
        members: members
      }

      Ltix.Test.stub_list_members(roster)

  A member's `:message` is a list of messages, each a map of claims keyed by
  [short name](`m:Ltix.Core#module-claims`), such as
  `%{custom: %{"grade_level" => "8"}}`. The stub raises `ArgumentError` for a
  short name no plugin declares.

  ## Options

  When you [configure](`m:Ltix#module-configuration`) an option, the configured
  value is its default.

  #{Zoi.describe(@stub_list_members_schema)}
  """
  @spec stub_list_members([Member.t()] | MembershipContainer.t(), keyword()) :: :ok
  def stub_list_members(members, opts \\ [])

  def stub_list_members(%MembershipContainer{} = container, opts) do
    opts = Options.parse!(opts, @stub_list_members_schema)
    reject_combined_option!(opts, :context, "a membership container")
    reject_combined_option!(opts, :id, "a membership container")
    stub_membership_container(container, opts[:plugins])
  end

  def stub_list_members(members, opts) when is_list(members) do
    opts = Options.parse!(opts, @stub_list_members_schema)
    plugins = ok!(PluginSet.resolve(opts[:plugins]))
    context = claim_struct(:context, Context, @default_context, opts[:context], plugins)

    stub_membership_container(
      %MembershipContainer{id: opts[:id], context: context, members: members},
      plugins
    )
  end

  defp stub_membership_container(container, enabled) do
    plugins = ok!(PluginSet.resolve(enabled))
    members = Enum.map(container.members, &member_json(&1, plugins))
    json = platform_json(container, plugins)

    json =
      if container.context,
        do: Map.put(json, "context", platform_json(container.context, plugins)),
        else: json

    ServiceStub.put(MembershipsService, :list_members, nil, fn conn ->
      ServiceStub.json_pages(conn, members, &Map.put(json, "members", &1))
    end)
  end

  defp member_json(%Member{message: nil} = member, plugins), do: platform_json(member, plugins)

  defp member_json(%Member{} = member, plugins) do
    messages = Enum.map(member.message, &claims_json(&1, plugins))
    Map.put(platform_json(member, plugins), "message", messages)
  end

  # The raw claims a platform sends for claims keyed by short name.
  defp claims_json(claims, plugins) do
    Map.new(claims, fn {name, value} ->
      case Ltix.Claims.declaration(plugins, name) do
        nil -> raise ArgumentError, "no plugin declares the claim #{inspect(name)}"
        declaration -> {declaration.uri, claim_value_json(declaration, value, plugins)}
      end
    end)
  end

  defp claim_value_json(%{claim: claim}, %claim{} = value, plugins),
    do: platform_json(value, plugins)

  defp claim_value_json(%{claim: claim, opts: opts}, value, _plugins),
    do: claim.serialize(value, opts)

  # The JSON a platform sends for a type's struct. It includes the property
  # of every extension, whatever the property's write operations.
  defp platform_json(%type{} = value, plugins) do
    properties =
      for %Entry{module: property, opts: opts} <-
            Enum.uniq_by(PluginSet.entries(plugins, type), &{&1.module, &1.opts}),
          {:ok, extension} <- [Map.fetch(value.extensions, opts[:name])],
          into: %{},
          do: {opts[:property], property.serialize(extension, opts)}

    Map.merge(Ltix.Type.to_json(value, plugins), properties)
  end

  # --- Lower-Level Helpers ---

  @doc group: "Tokens"
  @doc """
  Verify a Deep Linking response JWT signed by the tool.

  Decodes the JWT using the public key of the platform's `tool_jwk` and
  returns the parsed claims on success.
  Returns `Ltix.Errors.Security.SignatureInvalid` when the token is
  malformed or was not signed with the tool's key.

      {:ok, response} = Ltix.DeepLinking.build_response(launch, items)
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, response.jwt)
      assert claims["https://purl.imsglobal.org/spec/lti/claim/message_type"] ==
               "LtiDeepLinkingResponse"
  """
  @spec verify_deep_linking_response(Platform.t(), String.t()) ::
          {:ok, map()} | {:error, Exception.t()}
  def verify_deep_linking_response(%Platform{} = platform, jwt) do
    public_key = Ltix.JWK.to_jose(platform.tool_jwk)

    # [Sec §5.2.3](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation-0)
    case verify_signature(public_key, jwt) do
      {true, %JOSE.JWT{fields: claims}, _jws} when is_map(claims) -> {:ok, claims}
      _invalid -> {:error, SignatureInvalid.exception()}
    end
  end

  defp verify_signature(public_key, jwt) when is_binary(jwt),
    do: JOSE.JWT.verify_strict(public_key, ["RS256"], jwt)

  defp verify_signature(_public_key, _jwt), do: :error

  @doc group: "Tokens"
  @doc """
  Sign claims as an ID token with a platform key.

  Use it to build launch tokens by hand, such as a token missing a claim.

      claims = Map.delete(Ltix.Test.valid_lti_claims(platform), "sub")
      id_token = Ltix.Test.sign_id_token(claims, platform.jwk)

  ## Options

  #{Zoi.describe(@sign_id_token_schema)}
  """
  @spec sign_id_token(map(), Ltix.JWK.t(), keyword()) :: String.t()
  def sign_id_token(claims, %Ltix.JWK{private_key_pem: pem} = jwk, opts \\ [])
      when is_binary(pem) do
    opts = Options.parse!(opts, @sign_id_token_schema)
    kid = Keyword.get(opts, :kid, jwk.kid)
    header = maybe_put(%{"alg" => Keyword.fetch!(opts, :alg)}, "kid", kid)

    {_meta, token} =
      jwk.private_key_pem
      |> JOSE.JWK.from_pem()
      |> JOSE.JWT.sign(JOSE.JWS.from_map(header), JOSE.JWT.from_map(claims))
      |> JOSE.JWS.compact()

    token
  end

  @doc group: "Tokens"
  @doc """
  Return a complete, valid LTI claim set.

  The issuer, audience, and deployment ID are the platform's. Caller
  can override individual claims via the `overrides` map.

      claims = Ltix.Test.valid_lti_claims(platform, %{"nonce" => nonce})
      id_token = Ltix.Test.sign_id_token(claims, platform.jwk)
  """
  @spec valid_lti_claims(Platform.t(), map()) :: map()
  def valid_lti_claims(%Platform{} = platform, overrides \\ %{}) do
    nonce = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    opts = Options.parse!([], @launch_options_schema)
    claims = build_claims(platform, opts, ok!(PluginSet.resolve(nil)))
    Map.merge(Map.put(claims, "nonce", nonce), overrides)
  end

  # --- Private ---

  @lti_claim_prefix "https://purl.imsglobal.org/spec/lti/claim/"

  # [Core §5.3](https://www.imsglobal.org/spec/lti/v1p3/#required-message-claims)
  # [Core §5.4](https://www.imsglobal.org/spec/lti/v1p3/#optional-message-claims)
  defp build_claims(platform, opts, plugins) do
    registration = resolved_registration(platform)
    now = System.system_time(:second)

    # Built for every message type, so an unknown key fails in each.
    resource_link =
      claim_struct(
        :resource_link,
        ResourceLink,
        %{id: "resource-link-001", title: "Example Assignment"},
        opts[:resource_link],
        plugins
      )

    settings =
      claim_struct(
        :deep_linking_settings,
        Settings,
        %{
          deep_link_return_url: "https://platform.example.com/deep_links",
          accept_types: ["ltiResourceLink", "link", "file", "html", "image"],
          accept_presentation_document_targets: ["iframe", "window", "embed"],
          accept_multiple: true
        },
        opts[:deep_linking_settings],
        plugins
      )

    context = claim_struct(:context, Context, @default_context, opts[:context], plugins)

    %{
      "iss" => registration.issuer,
      "aud" => registration.client_id,
      "exp" => now + 3600,
      "iat" => now,
      "sub" => Keyword.get(opts, :subject, "user-12345"),
      "name" => Keyword.get(opts, :name),
      "email" => Keyword.get(opts, :email),
      "given_name" => Keyword.get(opts, :given_name),
      "family_name" => Keyword.get(opts, :family_name),
      (@lti_claim_prefix <> "version") => "1.3.0",
      (@lti_claim_prefix <> "deployment_id") => resolved_deployment(platform).deployment_id,
      (@lti_claim_prefix <> "target_link_uri") => Keyword.fetch!(opts, :target_link_uri),
      (@lti_claim_prefix <> "roles") => Keyword.fetch!(opts, :roles),
      (@lti_claim_prefix <> "context") => platform_json(context, plugins),
      # [AGS §3.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#assignment-and-grade-service-claim)
      "https://purl.imsglobal.org/spec/lti-ags/claim/endpoint" =>
        ags_endpoint_claim(opts[:ags_endpoint], plugins),
      # [NRPS §3.6.1.1](https://www.imsglobal.org/spec/lti-nrps/v2p0/#lti-1-3-integration)
      "https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice" =>
        memberships_endpoint_claim(opts[:memberships_endpoint], plugins)
    }
    |> Map.merge(
      message_type_claims(Keyword.fetch!(opts, :message_type), resource_link, settings, plugins)
    )
    |> Map.reject(fn {_claim, value} -> is_nil(value) end)
    |> Map.merge(Keyword.get(opts, :claims, %{}))
  end

  # [Core §5.3.5](https://www.imsglobal.org/spec/lti/v1p3/#resource-link-claim)
  defp message_type_claims(:resource_link, resource_link, _settings, plugins) do
    %{
      (@lti_claim_prefix <> "message_type") => "LtiResourceLinkRequest",
      (@lti_claim_prefix <> "resource_link") => platform_json(resource_link, plugins)
    }
  end

  # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
  defp message_type_claims(:deep_linking, _resource_link, settings, plugins) do
    %{
      (@lti_claim_prefix <> "message_type") => "LtiDeepLinkingRequest",
      "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings" =>
        platform_json(settings, plugins)
    }
  end

  defp message_type_claims(message_type, _resource_link, _settings, _plugins)
       when is_binary(message_type),
       do: %{(@lti_claim_prefix <> "message_type") => message_type}

  # The claim's struct in an option, or one built from a map of its fields and
  # property names over defaults.
  defp claim_struct(_option, _claim, _defaults, %_{} = struct, _plugins), do: struct

  defp claim_struct(option, claim, defaults, value, plugins) do
    {fields, extensions} = claim_fields(option, claim, value || %{}, plugins)
    struct!(claim, Map.put(Map.merge(defaults, fields), :extensions, extensions))
  end

  # The standard fields and extensions of a claim's struct or of a map of its
  # fields and property names.
  defp claim_fields(_option, _claim, %_{} = struct, _plugins),
    do: {Ltix.Type.standard_fields(struct), struct.extensions}

  defp claim_fields(option, claim, value, plugins) do
    {extensions, fields} = Ltix.Type.split_properties(claim, value, plugins)

    case Map.keys(fields) -- Ltix.Type.field_names(claim) do
      [] ->
        {fields, extensions}

      [key | _] ->
        Options.invalid!(option, "unrecognized key: #{key}")
    end
  end

  defp ags_endpoint_claim(nil, _plugins), do: nil

  defp ags_endpoint_claim(endpoint, plugins) do
    {fields, extensions} = claim_fields(:ags_endpoint, GradeServiceEndpoint, endpoint, plugins)
    platform_json(%{GradeServiceEndpoint.new!(fields) | extensions: extensions}, plugins)
  end

  defp memberships_endpoint_claim(nil, _plugins), do: nil

  defp memberships_endpoint_claim(url, plugins) when is_binary(url),
    do: memberships_endpoint_claim(%{context_memberships_url: url}, plugins)

  # Checks the URL, and sends any service versions, so a test can launch with
  # versions the memberships service doesn't support.
  defp memberships_endpoint_claim(endpoint, plugins) do
    {fields, extensions} =
      claim_fields(:memberships_endpoint, MembershipsServiceEndpoint, endpoint, plugins)

    endpoint = MembershipsServiceEndpoint.new!(fields[:context_memberships_url])

    platform_json(
      %{
        endpoint
        | service_versions: fields[:service_versions] || ["2.0"],
          extensions: extensions
      },
      plugins
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # --- Setup Helpers ---

  defp validate_setup_opts!(opts) do
    registration = Keyword.get(opts, :registration)
    deployment = Keyword.get(opts, :deployment)

    # Struct registrations are mutually exclusive with :issuer/:client_id.
    # Function registrations are not, because the function receives a
    # registration built from those values.
    if !is_nil(registration) && !is_function(registration) do
      reject_combined_option!(opts, :issuer, "a :registration struct")
      reject_combined_option!(opts, :client_id, "a :registration struct")
    end

    if !is_nil(deployment) && !is_function(deployment) do
      reject_combined_option!(opts, :deployment_id, "a :deployment struct")
    end
  end

  defp reject_combined_options!(opts, key, keys) do
    if Keyword.has_key?(opts, key) do
      Enum.each(keys, &reject_combined_option!(opts, &1, inspect(key)))
    end
  end

  defp reject_combined_option!(opts, key, other) do
    if Keyword.has_key?(opts, key) do
      Options.invalid!(key, "cannot be combined with #{other}")
    end
  end

  defp build_or_use_registration(opts) do
    case Keyword.get(opts, :registration) do
      nil ->
        build_default_registration(opts)

      fun when is_function(fun, 1) ->
        fun.(build_default_registration(opts))

      registration ->
        registration
    end
  end

  defp build_default_registration(opts) do
    issuer = Keyword.get(opts, :issuer, @default_issuer)
    client_id = Keyword.get(opts, :client_id, @default_client_id)
    suffix = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)

    Registration.new!(%{
      issuer: issuer,
      client_id: client_id,
      auth_endpoint: "#{issuer}/auth",
      jwks_uri: "#{issuer}/.well-known/jwks-#{suffix}.json",
      token_endpoint: "#{issuer}/token"
    })
  end

  defp build_or_use_deployment(opts, registration) do
    default = fn -> Deployment.new!(Keyword.get(opts, :deployment_id, @default_deployment_id)) end

    case Keyword.get(opts, :deployment) do
      nil -> default.()
      fun when is_function(fun, 2) -> fun.(default.(), registration)
      deployment -> deployment
    end
  end

  defp resolved_registration(%Platform{} = platform),
    do: ok!(Records.convert!(platform.registration, :registration, :registration))

  defp resolved_deployment(%Platform{} = platform),
    do: ok!(Records.convert!(platform.deployment, :deployment, :deployment))

  defp ok!({:ok, value}), do: value
  defp ok!({:error, error}), do: raise(error)
end
