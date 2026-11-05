defmodule Ltix.Test do
  @moduledoc """
  Helpers for testing an application that uses Ltix against a simulated
  platform.

  `setup_platform!/1` creates a test platform with its own signing key,
  registration, and deployment. The other helpers build the requests that
  platform sends, build launches directly, and stub its grade and memberships
  services. [Testing LTI Launches](testing-lti-launches.md) shows controller,
  business logic, and service tests.

  ```elixir
  setup do
    %{platform: Ltix.Test.setup_platform!()}
  end

  test "instructors can manage grades", %{platform: platform} do
    launch = Ltix.Test.build_launch(platform, roles: [Ltix.Role.context_instructor()])

    assert MyApp.Permissions.can_manage_grades?(launch)
  end
  ```

  ## Setup

    * Route Ltix's requests through `Req.Test` in your test configuration.
      With `retry: false`, a stubbed failure returns at once.

      ```elixir
      # config/test.exs
      config :ltix, req_options: [plug: {Req.Test, :ltix}, retry: false]
      ```

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

  ```elixir
  Ltix.Test.stub_token_response()
  Ltix.Test.stub_post_score()

  launch =
    Ltix.Test.build_launch(platform,
      claims: %{ags_endpoint: %{line_item: line_item, scopes: scopes}}
    )
  {:ok, client} = Ltix.GradeService.authenticate(launch)
  assert :ok = Ltix.GradeService.post_score(client, score)
  ```

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
  alias Ltix.Deployment
  alias Ltix.Errors
  alias Ltix.Errors.Security.SignatureInvalid
  alias Ltix.GradeService
  alias Ltix.GradeService.LineItem
  alias Ltix.GradeService.Result
  alias Ltix.JWT.KeySet
  alias Ltix.Launch
  alias Ltix.MembershipsService
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
                             issuer:
                               Zoi.string(
                                 description:
                                   "The platform's issuer URL. Defaults to `\"https://platform.example.com\"`."
                               ),
                             client_id:
                               Zoi.string(
                                 description:
                                   "The OAuth client ID. Defaults to `\"tool-client-id\"`."
                               ),
                             deployment_id:
                               Zoi.string(
                                 description:
                                   "The deployment ID. Defaults to `\"deployment-001\"`."
                               ),
                             registration:
                               Zoi.any(
                                 description:
                                   "A struct implementing `Ltix.Registerable`, or a function that receives an `Ltix.Registration` and returns your application's struct. Use a function to store a record with the registration's issuer, client ID, and endpoints. A function works with `:issuer` and `:client_id`, and a struct can't be combined with them."
                               ),
                             deployment:
                               Zoi.any(
                                 description:
                                   "A struct implementing `Ltix.Deployable`, or a function that receives an `Ltix.Deployment` and the record the `:registration` function returned, and returns your deployment record. A struct can't be combined with `:deployment_id`."
                               ),
                             tool_jwk:
                               Zoi.struct(Ltix.JWK,
                                 description:
                                   "The `Ltix.JWK` your tool signs with for this platform. Pass the key your own storage adapter signs with. Defaults to the key `Ltix.Test.StorageAdapter` signs with."
                               )
                           ],
                           unrecognized_keys: :error
                         )

  @login_params_schema Zoi.keyword(
                         [
                           login_hint:
                             Zoi.string(description: "The login hint.")
                             |> Zoi.default("user-hint"),
                           target_link_uri:
                             Zoi.string(description: "The launch URL.")
                             |> Zoi.default("https://tool.example.com/launch")
                         ],
                         unrecognized_keys: :error
                       )

  @default_context %{id: "context-001"}
  @default_resource_link %{id: "resource-link-001", title: "Example Assignment"}
  @default_deep_linking_settings %{
    deep_link_return_url: "https://platform.example.com/deep_links",
    accept_types: ["ltiResourceLink", "link", "file", "html", "image"],
    accept_presentation_document_targets: ["iframe", "window", "embed"],
    accept_multiple: true
  }

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
            "`\"LtiSubmissionReviewRequest\"`. `:resource_link` adds a resource link, " <>
            ~s(`%{id: "resource-link-001", title: "Example Assignment"}`, and `:deep_linking` ) <>
            "adds Deep Linking settings that accept the five standard content item types, every " <>
            "presentation target, and more than one content item. Every launch has a context, " <>
            ~s(`%{id: "context-001"}`. ) <>
            "Add the claims a message type string requires with `:claims`."
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
    claims:
      Zoi.map(Zoi.union([Zoi.atom(), Zoi.string()]), Zoi.any(),
        description:
          "Claims to send, keyed by short name or by name. A short name, such as `:context`, " <>
            "`:ags_endpoint`, or a plugin's claim, takes the claim's value. An object claim takes its " <>
            "struct, or a map of its fields and property names merged over the launch's default " <>
            "fields. An endpoint claim checks the endpoint with its `new/1`. A name, such as " <>
            "`\"sub\"` or a claim URI, takes the raw JSON, which replaces the built claim."
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

  @allow_stubs_schema Zoi.keyword(
                        [
                          plugins:
                            Zoi.list(Zoi.any(),
                              description:
                                "The plugins whose services' stubs `pid` uses, after the " <>
                                  "[default plugins](`Ltix.DefaultPlugins`), each as `MyPlugin` or " <>
                                  "`{MyPlugin, opts}`. Defaults to the configured plugins."
                            )
                        ],
                        unrecognized_keys: :error
                      )

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

  #{Zoi.describe(@setup_platform_schema)}
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

  ```elixir
  Ltix.Test.stub_key_set(platform, status: 503)

  {:error, %Ltix.Errors.Unknown.TransportError{status: 503}} =
    Ltix.handle_callback(params, state)
  ```

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

  The stubs include the platform's key set and token endpoints, and the service
  of each endpoint claim in the plugin set, such as `Ltix.GradeService` or a
  plugin's service stubbed with `Req.Test.stub/2`.

  Processes the test starts, such as tasks, LiveViews, and
  `start_supervised/2` children, already use them. Call `allow_stubs/1` for
  any other process, such as one your application supervises, before it
  handles a launch or sends requests to the test platform.

  ```elixir
  Ltix.Test.stub_token_response()
  Ltix.Test.stub_post_score()
  Ltix.Test.allow_stubs(Process.whereis(MyApp.GradeSync))
  ```

  `pid` can be a function that returns the process.

  ## Options

  #{Zoi.describe(@allow_stubs_schema)}
  """
  @spec allow_stubs(pid() | (-> pid()), keyword()) :: :ok
  def allow_stubs(pid, opts \\ []) do
    opts = Options.parse!(opts, @allow_stubs_schema)
    ServiceStub.allow(pid, ok!(PluginSet.resolve(opts[:plugins])))
  end

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

  #{Zoi.describe(Ltix.Test.StorageAdapterContract.options_schema())}

  ## Examples

  ```elixir
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
  ```
  """
  @spec assert_storage_adapter!(module(), keyword()) :: :ok
  def assert_storage_adapter!(adapter, opts), do: StorageAdapterContract.verify!(adapter, opts)

  # --- Request Builders ---

  @doc group: "Login and launch"
  @doc """
  Build POST params for `Ltix.handle_login/3`.

  ## Options

  #{Zoi.describe(@login_params_schema)}
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

  ```elixir
  params =
    Ltix.Test.launch_params(platform,
      nonce: nonce,
      state: state,
      roles: [Ltix.Role.context_learner()]
    )
  ```

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

  ```elixir
  {:ok, result} = Ltix.handle_login(params, redirect_uri)
  nonce = Ltix.Test.extract_nonce(result.redirect_uri)
  ```
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

  It skips the storage adapter, and every launch step ordered before
  `Ltix.Launch.Verified`, the steps that verify the message. Otherwise the
  launch matches what `Ltix.handle_callback/3` returns for `launch_params/2`
  with the same options, apart from Ltix's own data in `:private`. Plugins'
  other launch steps run too. Raises the failing step's error, such as
  `Ltix.Errors.Invalid.MissingClaim`.

  ```elixir
  launch = Ltix.Test.build_launch(platform,
    roles: [Ltix.Role.context_instructor(), Ltix.Role.instructor_teaching_assistant()],
    name: "Jane Smith",
    claims: %{context: %{id: "course-1", title: "Elixir 101"}}
  )
  ```

  This builds a Deep Linking launch.

  ```elixir
  launch = Ltix.Test.build_launch(platform,
    message_type: :deep_linking,
    claims: %{deep_linking_settings: %{accept_types: ["ltiResourceLink"]}}
  )
  ```

  A plugin's claims take the same values by short name.

  ```elixir
  launch = Ltix.Test.build_launch(platform,
    claims: %{proctoring_endpoint: %{events_url: "https://lms.example.com/events"}},
    plugins: [Proctoring]
  )
  ```

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

    # The steps before `Ltix.Launch.Verified` verify the message.
    steps =
      plugins
      |> PluginSet.entries(Launch)
      |> Enum.drop_while(&(&1.module != Launch.Verified))
      |> Enum.map(&build_launch_step(&1, platform))

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
    %{
      entry
      | module: SetDeployment,
        opts: [
          deployment: resolved_deployment(platform),
          source_deployment: platform.deployment
        ]
    }
  end

  defp build_launch_step(entry, _platform), do: entry

  # --- Service Test Helpers ---

  @doc group: "Service stubs"
  @doc """
  Stubs the platform's OAuth token endpoint for Advantage service tests. Call
  it before a service's `authenticate/2`, such as
  `Ltix.GradeService.authenticate/2`.

  ```elixir
  Ltix.Test.stub_token_response(scopes: [
    "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
    "https://purl.imsglobal.org/spec/lti-ags/scope/score"
  ])
  ```

  To test a failed authentication, stub the response the platform would send.
  `authenticate/2` then returns the error in the table below.

  ```elixir
  Ltix.Test.stub_token_response(status: 400, body: %{"error" => "invalid_scope"})

  {:error, %Ltix.Errors.Invalid.TokenRequestFailed{error: "invalid_scope"}} =
    Ltix.GradeService.authenticate(launch)
  ```

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

  ```elixir
  alias Ltix.GradeService.LineItem

  Ltix.Test.stub_list_line_items([
    %LineItem{id: "https://lms.example.com/lineitems/1", label: "Quiz 1", score_maximum: 100},
    %LineItem{id: "https://lms.example.com/lineitems/2", label: "Quiz 2", score_maximum: 50}
  ])
  ```

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

  ```elixir
  Ltix.Test.stub_get_line_item(%Ltix.GradeService.LineItem{
    id: "https://lms.example.com/lineitems/1",
    label: "Quiz 1",
    score_maximum: 100
  })
  ```

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

  ```elixir
  Ltix.Test.stub_create_line_item(%Ltix.GradeService.LineItem{
    id: "https://lms.example.com/lineitems/new",
    label: "Quiz 1",
    score_maximum: 100
  })
  ```

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

  ```elixir
  Ltix.Test.stub_update_line_item(%Ltix.GradeService.LineItem{
    id: "https://lms.example.com/lineitems/1",
    label: "Updated Quiz",
    score_maximum: 100
  })
  ```

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

  ```elixir
  Ltix.Test.stub_delete_line_item()
  ```

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

  ```elixir
  Ltix.Test.stub_post_score()
  ```

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

  ```elixir
  alias Ltix.GradeService.Result

  Ltix.Test.stub_list_results([
    %Result{user_id: "student-1", result_score: 0.85, result_maximum: 1},
    %Result{user_id: "student-2", result_score: 0.92, result_maximum: 1}
  ])
  ```

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

  ```elixir
  alias Ltix.MembershipsService.Member

  members = [
    %Member{user_id: "student-1", roles: [Ltix.Role.context_learner()], name: "Alice"},
    %Member{user_id: "teacher-1", roles: [Ltix.Role.context_instructor()], name: "Bob"}
  ]

  Ltix.Test.stub_list_members(members)
  ```

  Pass an `Ltix.MembershipsService.MembershipContainer` to return its `id`,
  `context`, and extensions too. With a container, passing `:context` or `:id`
  raises `ArgumentError`.

  ```elixir
  roster = %Ltix.MembershipsService.MembershipContainer{
    context: %Ltix.Claims.Context{id: "course-42"},
    members: members
  }

  Ltix.Test.stub_list_members(roster)
  ```

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
    context = context_struct(opts[:context], plugins)

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

  defp context_struct(%Context{} = context, _plugins), do: context

  defp context_struct(value, plugins) do
    {fields, extensions} =
      claim_fields(
        Ltix.Claims.declaration(plugins, :context),
        merge_fields(@default_context, value || %{}),
        plugins,
        :context
      )

    struct!(Context, Map.put(fields, :extensions, extensions))
  end

  defp member_json(%Member{message: nil} = member, plugins), do: platform_json(member, plugins)

  defp member_json(%Member{} = member, plugins) do
    messages = Enum.map(member.message, &claims_json(&1, plugins))
    Map.put(platform_json(member, plugins), "message", messages)
  end

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

  ```elixir
  {:ok, response} = Ltix.DeepLinking.build_response(launch, items)
  {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, response.jwt)
  assert claims["https://purl.imsglobal.org/spec/lti/claim/message_type"] ==
           "LtiDeepLinkingResponse"
  ```
  """
  @spec verify_deep_linking_response(Platform.t(), String.t()) ::
          {:ok, map()} | {:error, Exception.t()}
  def verify_deep_linking_response(%Platform{} = platform, jwt) do
    public_key = Ltix.JWK.to_jose(platform.tool_jwk)

    # [Sec §5.2.3](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation-0)
    with {true, payload, _jws} <- verify_signature(public_key, jwt),
         {:ok, claims} when is_map(claims) <- AppConfig.json_library!().decode(payload) do
      {:ok, claims}
    else
      _invalid -> {:error, SignatureInvalid.exception()}
    end
  end

  defp verify_signature(public_key, jwt) when is_binary(jwt),
    do: JOSE.JWS.verify_strict(public_key, ["RS256"], jwt)

  defp verify_signature(_public_key, _jwt), do: :error

  @doc group: "Tokens"
  @doc """
  Sign claims as an ID token with a platform key.

  Use it to build launch tokens by hand, such as a token missing a claim.

  ```elixir
  claims = Map.delete(Ltix.Test.valid_lti_claims(platform), "sub")
  id_token = Ltix.Test.sign_id_token(claims, platform.jwk)
  ```

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

  ```elixir
  claims = Ltix.Test.valid_lti_claims(platform, %{"nonce" => nonce})
  id_token = Ltix.Test.sign_id_token(claims, platform.jwk)
  ```
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

  # [Core, Required message claims](https://standards.1edtech.org/lti/specifications/core/lti-spec#required-message-claims)
  # [Core, Optional message claims](https://standards.1edtech.org/lti/specifications/core/lti-spec#optional-message-claims)
  defp build_claims(platform, opts, plugins) do
    registration = resolved_registration(platform)
    now = System.system_time(:second)
    message_type = Keyword.fetch!(opts, :message_type)
    {named, raw} = Map.split_with(Keyword.get(opts, :claims, %{}), &is_atom(elem(&1, 0)))

    named =
      Map.merge(default_claims(message_type), named, fn _name, defaults, value ->
        merge_fields(defaults, value)
      end)

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
      (@lti_claim_prefix <> "message_type") => message_type_claim(message_type),
      (@lti_claim_prefix <> "version") => "1.3.0",
      (@lti_claim_prefix <> "deployment_id") => resolved_deployment(platform).deployment_id,
      (@lti_claim_prefix <> "target_link_uri") => Keyword.fetch!(opts, :target_link_uri),
      (@lti_claim_prefix <> "roles") => Keyword.fetch!(opts, :roles)
    }
    |> Map.reject(fn {_claim, value} -> is_nil(value) end)
    |> Map.merge(claims_json(named, plugins, :claims))
    |> Map.merge(raw)
  end

  defp message_type_claim(:resource_link), do: "LtiResourceLinkRequest"
  defp message_type_claim(:deep_linking), do: "LtiDeepLinkingRequest"
  defp message_type_claim(message_type) when is_binary(message_type), do: message_type

  # The fields of the claims a launch has by default, which a claim given by
  # short name is merged over.
  # [Core, Resource link claim](https://standards.1edtech.org/lti/specifications/core/lti-spec#resource-link-claim)
  defp default_claims(:resource_link),
    do: %{context: @default_context, resource_link: @default_resource_link}

  # [DL, Deep linking settings](https://standards.1edtech.org/lti/specifications/launch_messages/deep_linking/lti-deep-linking-spec#deep-linking-settings)
  defp default_claims(:deep_linking),
    do: %{context: @default_context, deep_linking_settings: @default_deep_linking_settings}

  defp default_claims(message_type) when is_binary(message_type),
    do: %{context: @default_context}

  defp merge_fields(_defaults, %_{} = struct), do: struct

  defp merge_fields(defaults, value) do
    case Options.keyword_to_map(value) do
      fields when is_map(fields) -> Map.merge(defaults, fields)
      value -> value
    end
  end

  # The raw claims a platform sends for claims keyed by short name, leaving out
  # `nil` values. `option` is the option that has them, for error messages.
  defp claims_json(claims, plugins, option \\ nil) do
    for {name, value} <- claims, value != nil, into: %{} do
      case Ltix.Claims.declaration(plugins, name) do
        nil -> invalid_claims!(option, "no plugin declares the claim #{inspect(name)}")
        declaration -> {declaration.uri, claim_json(declaration, value, plugins, option)}
      end
    end
  end

  # An endpoint claim checks the endpoint with its `new/1`, the way a service
  # does before it requests a token.
  defp claim_json(%{claim: claim, service: service} = declaration, value, plugins, option)
       when service != nil do
    {fields, extensions} = claim_fields(declaration, value, plugins, option)

    case claim.new(fields) do
      {:ok, endpoint} -> platform_json(%{endpoint | extensions: extensions}, plugins)
      {:error, error} -> raise error
    end
  end

  defp claim_json(%{claim: claim, opts: opts} = declaration, value, plugins, option) do
    if Ltix.Type.field_names(claim) == [] do
      claim.serialize(value, opts)
    else
      {fields, extensions} = claim_fields(declaration, value, plugins, option)
      platform_json(struct!(claim, Map.put(fields, :extensions, extensions)), plugins)
    end
  end

  # The standard fields and extensions of an object claim's struct, or of a
  # keyword list or map of its fields and property names.
  defp claim_fields(%{claim: claim}, %claim{} = struct, _plugins, _option),
    do: {Ltix.Type.standard_fields(struct), struct.extensions}

  defp claim_fields(%{claim: claim, name: name}, value, plugins, option) do
    case Options.keyword_to_map(value) do
      fields when is_map(fields) and not is_struct(fields) ->
        {extensions, fields} = Ltix.Type.split_properties(claim, fields, plugins)

        case Map.keys(fields) -- Ltix.Type.field_names(claim) do
          [] -> {fields, extensions}
          [key | _] -> invalid_claims!(option, "#{inspect(name)} has an unrecognized key, #{key}")
        end

      _value ->
        invalid_claims!(
          option,
          "#{inspect(name)} must be a #{inspect(claim)} struct, " <>
            "or a keyword list or map of the claim's fields and property names"
        )
    end
  end

  defp invalid_claims!(nil, reason), do: raise(ArgumentError, reason)
  defp invalid_claims!(option, reason), do: Options.invalid!(option, reason)

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
