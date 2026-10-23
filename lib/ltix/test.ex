defmodule Ltix.Test do
  @moduledoc """
  Helpers for testing applications that use Ltix.

  Reduces LTI test setup to a single call. `setup_platform!/1` generates
  RSA keys, builds key sets, and creates registrations and
  deployments.

      setup do
        %{platform: Ltix.Test.setup_platform!()}
      end

  Your application's own storage adapter (configured in `config/test.exs`)
  handles persistence. `setup_platform!/1` provides the platform-side
  simulation, which is RSA keys, a key set URL stub, and
  registration/deployment data your adapter can look up. Without an adapter of your own, start the
  in-memory `Ltix.Test.StorageAdapter` with the platform.

  Add the optional `:plug` dependency to your test environment to use
  `setup_platform!/1` and HTTP stubs. The stubs take effect only when Ltix
  sends its requests through `Req.Test`, so add this to `config/test.exs`.

      config :ltix, req_options: [plug: {Req.Test, :ltix}]

  ## Connecting to your storage adapter

  Pass a `:registration` function to create records in your own persistence
  layer. The function receives a valid `Ltix.Registration` with the
  registration details and returns your application's struct (which must
  implement `Ltix.Registerable`).

      setup do
        jwk = MyApp.Lti.generate_jwk!()

        platform = Ltix.Test.setup_platform!(
          registration: fn reg ->
            MyApp.Lti.create_registration!(%{
              issuer: reg.issuer,
              client_id: reg.client_id,
              auth_endpoint: reg.auth_endpoint,
              jwks_uri: reg.jwks_uri,
              token_endpoint: reg.token_endpoint,
              jwk_id: jwk.id
            })
          end,
          tool_jwk: Ltix.JWK.new!(private_key_pem: jwk.private_key_pem, kid: jwk.kid),
          deployment: fn dep, my_reg ->
            MyApp.Lti.create_deployment!(%{
              deployment_id: dep.deployment_id,
              registration_id: my_reg.id
            })
          end
        )

        %{platform: platform}
      end

  ## Controller tests (full OIDC flow)

  Simulate a platform-initiated launch against your controller endpoints.
  Your app's storage adapter resolves registrations and nonces as it would
  in production.

      test "instructor launch renders dashboard", %{conn: conn, platform: platform} do
        conn = post(conn, ~p"/lti/login", Ltix.Test.login_params(platform))

        state = get_session(conn, :lti_state)
        nonce = Ltix.Test.extract_nonce(redirected_to(conn, 302))

        conn =
          conn
          |> recycle()
          |> Plug.Test.init_test_session(%{lti_state: state})
          |> post(~p"/lti/launch",
            Ltix.Test.launch_params(platform,
              nonce: nonce,
              state: state,
              roles: [:instructor],
              name: "Jane Doe"
            )
          )

        assert html_response(conn, 200) =~ "Dashboard"
      end

  ## Unit tests (direct context construction)

  When testing business logic that receives a `%LaunchContext{}`, skip
  the OIDC flow entirely with `build_launch_context/2`.

      test "instructors can manage grades", %{platform: platform} do
        context = Ltix.Test.build_launch_context(platform,
          roles: [:instructor],
          name: "Jane Smith"
        )

        assert MyApp.Permissions.can_manage_grades?(context)
      end

  ## Hand-built tokens

  To send a token `launch_params/2` doesn't build, start from
  `valid_lti_claims/2`, change the claims, and sign them with the
  platform's key using `sign_id_token/3`.

      claims = Map.delete(Ltix.Test.valid_lti_claims(platform, %{"nonce" => nonce}), "sub")
      params = %{"id_token" => Ltix.Test.sign_id_token(claims, platform.jwk), "state" => state}

  ## Advantage service tests

  When testing code that calls `Ltix.GradeService` or
  `Ltix.MembershipsService`, stub the OAuth token endpoint and each
  operation your code calls. Each stub handles one operation, stubbing an
  operation again replaces its stub, and a request without a matching stub
  fails the test with its method and URL.

      setup do
        platform = Ltix.Test.setup_platform!()

        Ltix.Test.stub_token_response(scopes: [
          "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
          "https://purl.imsglobal.org/spec/lti-ags/scope/score"
        ])

        Ltix.Test.stub_list_line_items([
          %Ltix.GradeService.LineItem{
            id: "https://platform.example.com/lineitems/1",
            label: "Quiz",
            score_maximum: 100
          }
        ])

        Ltix.Test.stub_post_score()

        %{platform: platform}
      end

      test "posts a score to every line item", %{platform: platform} do
        context = Ltix.Test.build_launch_context(platform,
          ags_endpoint: %{
            line_items: "https://platform.example.com/lineitems",
            scopes: [
              "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
              "https://purl.imsglobal.org/spec/lti-ags/scope/score"
            ]
          }
        )

        {:ok, client} = Ltix.GradeService.authenticate(context)

        score =
          Ltix.GradeService.Score.new!(
            user_id: "student-42",
            score_given: 85,
            score_maximum: 100,
            activity_progress: :completed,
            grading_progress: :fully_graded
          )

        for item <- Ltix.GradeService.list_line_items!(client) do
          :ok = Ltix.GradeService.post_score(client, score, line_item: item)
        end
      end

  See the [Testing LTI Launches](testing-lti-launches.md) cookbook for
  more examples, including role customization, raw claim overrides, and
  memberships service testing.
  """

  @compile {:no_warn_undefined,
            [
              {Plug.Conn, :put_resp_header, 3},
              {Plug.Conn, :put_status, 2},
              {Plug.Conn, :send_resp, 3}
            ]}

  alias Ltix.Deployment
  alias Ltix.Errors.Invalid.InvalidOption
  alias Ltix.Errors.Security.SignatureInvalid
  alias Ltix.GradeService
  alias Ltix.GradeService.LineItem
  alias Ltix.GradeService.Result
  alias Ltix.JWT.KeySet
  alias Ltix.LaunchClaims
  alias Ltix.LaunchClaims.AGSEndpoint
  alias Ltix.LaunchClaims.Context
  alias Ltix.LaunchClaims.DeepLinkingSettings
  alias Ltix.LaunchClaims.MembershipsEndpoint
  alias Ltix.LaunchClaims.ResourceLink
  alias Ltix.LaunchClaims.Role
  alias Ltix.LaunchContext
  alias Ltix.MembershipsService
  alias Ltix.MembershipsService.Member
  alias Ltix.OAuth.ClientCredentials
  alias Ltix.Options
  alias Ltix.Records
  alias Ltix.Registration
  alias Ltix.Test.Platform
  alias Ltix.Test.ServiceStub
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
                        unrecognized_keys: :error
                      )
                    ],
                    description:
                      "Course or section, as a `%Ltix.LaunchClaims.Context{}` or a map of its fields. " <>
                        "The `:id` defaults to `\"context-001\"`."
                  )

  @launch_option_fields [
    message_type:
      Zoi.enum([:resource_link, :deep_linking],
        description: "`:deep_linking` for a Deep Linking request."
      )
      |> Zoi.default(:resource_link),
    roles:
      Zoi.list(Zoi.union([Zoi.atom(), Zoi.string(), Zoi.struct(Role)]),
        description:
          "Role atoms such as `:instructor`, `%Ltix.LaunchClaims.Role{}` structs, or role URIs. " <>
            "URIs Ltix does not recognize are listed in `unrecognized_roles`."
      )
      |> Zoi.default([:instructor]),
    subject:
      Zoi.nullable(Zoi.string(),
        description:
          "User identifier. Defaults to `\"user-12345\"`. Pass `nil` for an anonymous launch."
      ),
    name: Zoi.string(description: "Full name."),
    email: Zoi.string(description: "Email address."),
    given_name: Zoi.string(description: "Given name."),
    family_name: Zoi.string(description: "Family name."),
    target_link_uri:
      Zoi.string(description: "Launch URL.")
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
            unrecognized_keys: :error
          )
        ],
        description:
          "Resource link of a resource link launch, as a `%Ltix.LaunchClaims.ResourceLink{}` " <>
            "or a map of its fields. Defaults to `%{id: \"resource-link-001\", title: \"Example Assignment\"}`."
      ),
    deep_linking_settings:
      Zoi.union(
        [
          Zoi.struct(DeepLinkingSettings),
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
            unrecognized_keys: :error
          )
        ],
        description:
          "Settings of a Deep Linking request, as a `%Ltix.LaunchClaims.DeepLinkingSettings{}` " <>
            "or a map of its fields. Fields you leave out accept the five standard content " <>
            "types, every presentation target, and multiple items."
      ),
    ags_endpoint:
      Zoi.union(
        [
          Zoi.struct(AGSEndpoint),
          Zoi.map(
            %{
              scopes: Zoi.nullish(Zoi.list(Zoi.string())),
              line_items: Zoi.nullish(Zoi.string()),
              line_item: Zoi.nullish(Zoi.string())
            },
            unrecognized_keys: :error
          )
        ],
        description:
          "Grade service endpoint, as a `%Ltix.LaunchClaims.AGSEndpoint{}` or a map of its " <>
            "fields. Requires `:scopes`."
      ),
    memberships_endpoint:
      Zoi.union(
        [
          Zoi.struct(MembershipsEndpoint),
          Zoi.string(),
          Zoi.map(
            %{
              context_memberships_url: Zoi.nullish(Zoi.string()),
              service_versions: Zoi.nullish(Zoi.list(Zoi.string()))
            },
            unrecognized_keys: :error
          )
        ],
        description:
          "Memberships service endpoint, as a `%Ltix.LaunchClaims.MembershipsEndpoint{}`, " <>
            "its URL, or a map of its fields. `:service_versions` defaults to `[\"2.0\"]`."
      ),
    claims:
      Zoi.map(Zoi.string(), Zoi.any(),
        description: "Raw claims merged over the built claims, keyed by claim name."
      )
  ]

  @launch_params_schema Zoi.keyword(
                          [
                            nonce:
                              Zoi.string(
                                description:
                                  "Nonce from the login redirect, read with `extract_nonce/1`."
                              )
                              |> Zoi.required(),
                            state:
                              Zoi.string(description: "State from the login result.")
                              |> Zoi.required()
                          ] ++ @launch_option_fields,
                          unrecognized_keys: :error
                        )

  @build_launch_context_schema Zoi.keyword(@launch_option_fields, unrecognized_keys: :error)

  @stub_token_response_schema Zoi.keyword(
                                [
                                  scopes: Zoi.list(Zoi.string()) |> Zoi.default([]),
                                  access_token: Zoi.string() |> Zoi.default("test-token"),
                                  expires_in: Zoi.integer() |> Zoi.default(3600)
                                ],
                                unrecognized_keys: :error
                              )

  @stub_line_item_schema Zoi.keyword(
                           [
                             line_item:
                               Zoi.union([Zoi.string(), Zoi.struct(LineItem)],
                                 description:
                                   "Line item URL or struct. Limits the stub to requests for this line item, " <>
                                     "and replaces only the stub for it."
                               )
                           ],
                           unrecognized_keys: :error
                         )

  @stub_list_members_schema Zoi.keyword(
                              [
                                context: @context_option,
                                id: Zoi.string(description: "Container ID URL.")
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
    require_plug!()

    opts = Options.parse!(opts, @setup_platform_schema)
    validate_setup_opts!(opts)

    jwk = Ltix.JWK.generate(key_size: 2048)
    jwks = Ltix.JWK.to_jwks(jwk)

    registration = build_or_use_registration(opts)
    deployment = build_or_use_deployment(opts, registration)

    platform = %Platform{
      registration: registration,
      deployment: deployment,
      jwk: jwk,
      tool_jwk: Keyword.get_lazy(opts, :tool_jwk, &StorageAdapter.tool_jwk/0)
    }

    # Eagerly validate protocol implementations
    %Registration{jwks_uri: jwks_uri} = resolved_registration(platform)
    resolved_deployment(platform)

    stub_jwks(jwks_uri, jwks)
    KeySet.expire_keys(jwks_uri)

    platform
  end

  # Serves each platform set up in this test process its own keys at its own
  # key set URL.
  defp stub_jwks(jwks_uri, jwks) do
    %URI{host: host, path: path} = URI.parse(jwks_uri)
    key_sets = Map.put(Process.get({__MODULE__, :key_sets}, %{}), {host, path}, jwks)
    Process.put({__MODULE__, :key_sets}, key_sets)

    Req.Test.stub(KeySet, fn conn ->
      case Map.fetch(key_sets, {conn.host, conn.request_path}) do
        {:ok, jwks} ->
          conn
          |> Plug.Conn.put_resp_header("cache-control", "max-age=300")
          |> Req.Test.json(jwks)

        :error ->
          Plug.Conn.send_resp(conn, 404, "")
      end
    end)
  end

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

  @doc """
  Build POST params for `Ltix.handle_callback/3`.

  Signs a JWT with the platform's private key and returns
  `%{"id_token" => jwt, "state" => state}`. Takes the same launch options
  as `build_launch_context/2`, plus the `:nonce` and `:state` of the login.

  ## Options

  #{Zoi.describe(@launch_params_schema)}
  """
  @spec launch_params(Platform.t(), keyword()) :: map()
  def launch_params(%Platform{} = platform, opts) do
    opts = Options.parse!(opts, @launch_params_schema)
    {nonce, opts} = Keyword.pop!(opts, :nonce)
    {state, opts} = Keyword.pop!(opts, :state)
    claims = Map.put(build_claims(platform, opts), "nonce", nonce)

    %{"id_token" => sign_id_token(claims, platform.jwk), "state" => state}
  end

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

  # --- Direct Context Construction ---

  @doc """
  Build a `%LaunchContext{}` directly for unit testing.

  Returns the context `Ltix.handle_callback/3` would return for a launch
  from `launch_params/2` with the same launch options, without the OIDC flow.

      context = Ltix.Test.build_launch_context(platform,
        roles: [:instructor, :teaching_assistant],
        name: "Jane Smith",
        context: %{id: "course-1", title: "Elixir 101"}
      )

  For Deep Linking contexts, pass `message_type: :deep_linking`.

      context = Ltix.Test.build_launch_context(platform,
        message_type: :deep_linking,
        deep_linking_settings: %{accept_types: ["ltiResourceLink"]}
      )

  ## Options

  #{Zoi.describe(@build_launch_context_schema)}
  """
  @spec build_launch_context(Platform.t(), keyword()) :: LaunchContext.t()
  def build_launch_context(%Platform{} = platform, opts \\ []) do
    claims = build_claims(platform, Options.parse!(opts, @build_launch_context_schema))

    %LaunchContext{
      claims: ok!(LaunchClaims.from_json(claims)),
      registration: platform.registration,
      deployment: platform.deployment
    }
  end

  # --- Service Test Helpers ---

  @doc """
  Stub the OAuth token endpoint for advantage service tests.

  Stubs the OAuth token endpoint so advantage service tests don't make
  real HTTP calls. Call this in your test setup before authenticating a
  service client.

      Ltix.Test.stub_token_response(scopes: [
        "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
        "https://purl.imsglobal.org/spec/lti-ags/scope/score"
      ])

  ## Options

    * `:scopes` - list of granted scope URIs (defaults to `[]`). An empty list
      grants the requested scopes.
    * `:access_token` - token string (defaults to `"test-token"`)
    * `:expires_in` - token lifetime in seconds (defaults to `3600`)
  """
  @spec stub_token_response(keyword()) :: :ok
  def stub_token_response(opts \\ []) do
    require_plug!()

    opts = Options.parse!(opts, @stub_token_response_schema)
    scopes = Keyword.fetch!(opts, :scopes)

    response = %{
      "access_token" => Keyword.fetch!(opts, :access_token),
      "token_type" => "Bearer",
      "expires_in" => Keyword.fetch!(opts, :expires_in)
    }

    response =
      if scopes == [], do: response, else: Map.put(response, "scope", Enum.join(scopes, " "))

    Req.Test.stub(ClientCredentials, fn conn ->
      Req.Test.json(conn, response)
    end)
  end

  # --- Grade Service Stubs ---

  @doc """
  Stub `list_line_items/2` and `stream_line_items/2` to return the given
  line items.

      Ltix.Test.stub_list_line_items([
        %LineItem{id: "https://lms.example.com/lineitems/1", label: "Quiz 1", score_maximum: 100},
        %LineItem{id: "https://lms.example.com/lineitems/2", label: "Quiz 2", score_maximum: 50}
      ])

  Responds to a request with a `:per_page` size one page at a time, linking
  to the next page like a platform does.
  """
  @spec stub_list_line_items([LineItem.t()]) :: :ok
  def stub_list_line_items(line_items) when is_list(line_items) do
    require_plug!()
    json = Enum.map(line_items, &LineItem.to_map/1)
    ServiceStub.put(GradeService, :list_line_items, nil, &ServiceStub.json_pages(&1, json))
  end

  @doc """
  Stub `get_line_item/2` to return the given line item.

      Ltix.Test.stub_get_line_item(
        %LineItem{id: "https://lms.example.com/lineitems/1", label: "Quiz 1", score_maximum: 100}
      )

  ## Options

  #{Zoi.describe(@stub_line_item_schema)}
  """
  @spec stub_get_line_item(LineItem.t(), keyword()) :: :ok
  def stub_get_line_item(%LineItem{} = item, opts \\ []),
    do: stub_line_item(:get_line_item, item, opts)

  @doc """
  Stub `create_line_item/2` to return the given line item.

  Pass the line item you want the platform to "return" (typically the
  same fields the caller sent, plus an `:id` assigned by the platform).

      Ltix.Test.stub_create_line_item(
        %LineItem{id: "https://lms.example.com/lineitems/new", label: "Quiz 1", score_maximum: 100}
      )
  """
  @spec stub_create_line_item(LineItem.t()) :: :ok
  def stub_create_line_item(%LineItem{} = item) do
    require_plug!()
    json = LineItem.to_map(item)

    ServiceStub.put(GradeService, :create_line_item, nil, fn conn ->
      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(json)
    end)
  end

  @doc """
  Stub `update_line_item/2` to return the given line item.

      Ltix.Test.stub_update_line_item(
        %LineItem{id: "https://lms.example.com/lineitems/1", label: "Updated Quiz", score_maximum: 100}
      )

  ## Options

  #{Zoi.describe(@stub_line_item_schema)}
  """
  @spec stub_update_line_item(LineItem.t(), keyword()) :: :ok
  def stub_update_line_item(%LineItem{} = item, opts \\ []),
    do: stub_line_item(:update_line_item, item, opts)

  defp stub_line_item(operation, item, opts) do
    require_plug!()
    json = LineItem.to_map(item)
    url = stub_line_item_url(opts)
    ServiceStub.put(GradeService, operation, url, &Req.Test.json(&1, json))
  end

  @doc """
  Stub `delete_line_item/2` to succeed.

      Ltix.Test.stub_delete_line_item()

  ## Options

  #{Zoi.describe(@stub_line_item_schema)}
  """
  @spec stub_delete_line_item(keyword()) :: :ok
  def stub_delete_line_item(opts \\ []) do
    require_plug!()
    url = stub_line_item_url(opts)
    ServiceStub.put(GradeService, :delete_line_item, url, &Plug.Conn.send_resp(&1, 204, ""))
  end

  @doc """
  Stub `post_score/3` to succeed.

      Ltix.Test.stub_post_score()

  ## Options

  #{Zoi.describe(@stub_line_item_schema)}
  """
  @spec stub_post_score(keyword()) :: :ok
  def stub_post_score(opts \\ []) do
    require_plug!()
    url = stub_line_item_url(opts)
    ServiceStub.put(GradeService, :post_score, url, &Plug.Conn.send_resp(&1, 200, ""))
  end

  @doc """
  Stub `list_results/2` and `stream_results/2` to return the given results.

      Ltix.Test.stub_list_results([
        %Result{user_id: "student-1", result_score: 0.85, result_maximum: 1},
        %Result{user_id: "student-2", result_score: 0.92, result_maximum: 1}
      ])

  Responds to a request with a `:per_page` size one page at a time, linking
  to the next page like a platform does.

  ## Options

  #{Zoi.describe(@stub_line_item_schema)}
  """
  @spec stub_list_results([Result.t()], keyword()) :: :ok
  def stub_list_results(results, opts \\ []) when is_list(results) do
    require_plug!()
    json = Enum.map(results, &Result.to_map/1)
    url = stub_line_item_url(opts)
    ServiceStub.put(GradeService, :list_results, url, &ServiceStub.json_pages(&1, json))
  end

  defp stub_line_item_url(opts) do
    case Keyword.fetch(Options.parse!(opts, @stub_line_item_schema), :line_item) do
      :error ->
        nil

      {:ok, %LineItem{id: nil} = item} ->
        raise InvalidOption, key: :line_item, value: item, reason: "the line item has no id"

      {:ok, %LineItem{id: url}} ->
        url

      {:ok, url} ->
        url
    end
  end

  # --- Memberships Service Stubs ---

  @doc """
  Stub `list_members/2` and `stream_members/2` to return the given members.

      Ltix.Test.stub_list_members([
        %Member{user_id: "student-1", roles: [Role.from_atom(:learner)], name: "Alice"},
        %Member{user_id: "student-2", roles: [Role.from_atom(:instructor)], name: "Bob"}
      ])

  Responds to a request with a `:per_page` size one page at a time, linking
  to the next page like a platform does.

  ## Options

  #{Zoi.describe(@stub_list_members_schema)}
  """
  @spec stub_list_members([Member.t()], keyword()) :: :ok
  def stub_list_members(members, opts \\ []) when is_list(members) do
    require_plug!()

    opts = Options.parse!(opts, @stub_list_members_schema)
    context = context_claim(Keyword.get(opts, :context, %{}))
    container = maybe_put(%{"context" => context}, "id", Keyword.get(opts, :id))

    json = Enum.map(members, &Member.to_map/1)

    ServiceStub.put(MembershipsService, :list_members, nil, fn conn ->
      ServiceStub.json_pages(conn, json, &Map.put(container, "members", &1))
    end)
  end

  # --- Lower-Level Helpers ---

  @doc """
  Verify a Deep Linking response JWT signed by the tool.

  Decodes the JWT using the public key of the platform's `tool_jwk` and
  returns the parsed claims on success.
  Returns `Ltix.Errors.Security.SignatureInvalid` when the token is
  malformed or was not signed with the tool's key.

      {:ok, response} = Ltix.DeepLinking.build_response(context, items)
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
    claims = build_claims(platform, Options.parse!([], @build_launch_context_schema))
    Map.merge(Map.put(claims, "nonce", nonce), overrides)
  end

  # --- Private ---

  @lti_claim_prefix "https://purl.imsglobal.org/spec/lti/claim/"

  # [Core §5.3](https://www.imsglobal.org/spec/lti/v1p3/#required-message-claims)
  # [Core §5.4](https://www.imsglobal.org/spec/lti/v1p3/#optional-message-claims)
  defp build_claims(platform, opts) do
    registration = resolved_registration(platform)
    now = System.system_time(:second)

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
      (@lti_claim_prefix <> "roles") => Enum.map(Keyword.fetch!(opts, :roles), &role_uri/1),
      (@lti_claim_prefix <> "context") => context_claim(Keyword.get(opts, :context, %{})),
      # [AGS §3.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#assignment-and-grade-service-claim)
      "https://purl.imsglobal.org/spec/lti-ags/claim/endpoint" =>
        ags_endpoint_claim(Keyword.get(opts, :ags_endpoint)),
      # [NRPS §3.6.1.1](https://www.imsglobal.org/spec/lti-nrps/v2p0/#lti-1-3-integration)
      "https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice" =>
        memberships_endpoint_claim(Keyword.get(opts, :memberships_endpoint))
    }
    |> Map.merge(message_type_claims(Keyword.fetch!(opts, :message_type), opts))
    |> Map.reject(fn {_claim, value} -> is_nil(value) end)
    |> Map.merge(Keyword.get(opts, :claims, %{}))
  end

  # [Core §5.3.5](https://www.imsglobal.org/spec/lti/v1p3/#resource-link-claim)
  defp message_type_claims(:resource_link, opts) do
    resource_link =
      Map.merge(
        %{id: "resource-link-001", title: "Example Assignment"},
        plain_map(Keyword.get(opts, :resource_link, %{}))
      )

    %{
      (@lti_claim_prefix <> "message_type") => "LtiResourceLinkRequest",
      (@lti_claim_prefix <> "resource_link") => json_map(resource_link)
    }
  end

  # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
  defp message_type_claims(:deep_linking, opts) do
    settings =
      Map.merge(
        %{
          deep_link_return_url: "https://platform.example.com/deep_links",
          accept_types: ["ltiResourceLink", "link", "file", "html", "image"],
          accept_presentation_document_targets: ["iframe", "window", "embed"],
          accept_multiple: true
        },
        plain_map(Keyword.get(opts, :deep_linking_settings, %{}))
      )

    {accept_line_item, settings} = Map.pop(settings, :accept_line_item)
    settings = Map.put(settings, :accept_lineitem, accept_line_item)

    %{
      (@lti_claim_prefix <> "message_type") => "LtiDeepLinkingRequest",
      "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings" => json_map(settings)
    }
  end

  defp role_uri(uri) when is_binary(uri), do: uri

  defp role_uri(role) do
    Role.to_uri!(if is_atom(role), do: Role.from_atom(role), else: role)
  rescue
    ArgumentError ->
      reraise InvalidOption,
              [key: :roles, value: role, reason: "it is not a known role"],
              __STACKTRACE__
  end

  defp context_claim(context), do: json_map(Map.merge(%{id: "context-001"}, plain_map(context)))

  defp ags_endpoint_claim(nil), do: nil

  defp ags_endpoint_claim(endpoint) do
    endpoint = AGSEndpoint.new!(plain_map(endpoint))

    json_map(%{
      scope: endpoint.scopes,
      lineitems: endpoint.line_items,
      lineitem: endpoint.line_item
    })
  end

  defp memberships_endpoint_claim(nil), do: nil

  defp memberships_endpoint_claim(url) when is_binary(url),
    do: memberships_endpoint_claim(%{context_memberships_url: url})

  defp memberships_endpoint_claim(endpoint) do
    endpoint = plain_map(endpoint)
    url = endpoint[:context_memberships_url]
    # Raises for an invalid URL.
    MembershipsEndpoint.new!(url)

    json_map(%{
      context_memberships_url: url,
      service_versions: endpoint[:service_versions] || ["2.0"]
    })
  end

  defp plain_map(%_{} = struct), do: Map.from_struct(struct)
  defp plain_map(map), do: map

  # Claim JSON omits absent fields.
  defp json_map(map) do
    for {key, value} <- map, not is_nil(value), into: %{}, do: {Atom.to_string(key), value}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # --- Setup Helpers ---

  defp require_plug! do
    unless Code.ensure_loaded?(Plug.Conn) do
      raise "Ltix HTTP test helpers require Plug. Add the optional :plug dependency to your test environment."
    end
  end

  defp validate_setup_opts!(opts) do
    registration = Keyword.get(opts, :registration)
    deployment = Keyword.get(opts, :deployment)

    # Struct registrations are mutually exclusive with :issuer/:client_id.
    # Function registrations are not, because the function receives a
    # registration built from those values.
    if not is_nil(registration) and not is_function(registration) do
      reject_combined_option!(opts, :issuer, :registration)
      reject_combined_option!(opts, :client_id, :registration)
    end

    if not is_nil(deployment) and not is_function(deployment) do
      reject_combined_option!(opts, :deployment_id, :deployment)
    end
  end

  defp reject_combined_option!(opts, key, struct_key) do
    if Keyword.has_key?(opts, key) do
      raise InvalidOption,
        key: key,
        value: Keyword.fetch!(opts, key),
        reason: "cannot be combined with a #{inspect(struct_key)} struct"
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
