defmodule LtixTest do
  use ExUnit.Case

  alias Ltix.Deployment
  alias Ltix.Errors.Invalid.DeploymentNotFound
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.Errors.Invalid.InvalidOption
  alias Ltix.Errors.Invalid.MissingParameter
  alias Ltix.Errors.Invalid.RegistrationNotFound
  alias Ltix.Errors.Unknown.StorageError
  alias Ltix.LaunchContext
  alias Ltix.Registration
  alias Ltix.Test.StorageAdapter

  @redirect_uri "https://tool.example.com/callback"

  defmodule UnregisteredStorageAdapter do
    @moduledoc false
    @behaviour Ltix.StorageAdapter

    @impl Ltix.StorageAdapter
    def get_registration(_issuer, _client_id), do: {:error, :not_found}

    @impl Ltix.StorageAdapter
    defdelegate get_deployment(registration, deployment_id), to: StorageAdapter

    @impl Ltix.StorageAdapter
    defdelegate store_nonce(nonce, registration), to: StorageAdapter

    @impl Ltix.StorageAdapter
    defdelegate validate_nonce(nonce, registration), to: StorageAdapter
  end

  defmodule RecordingCache do
    @moduledoc false
    @behaviour Ltix.JWT.KeySet.Cache

    @impl Ltix.JWT.KeySet.Cache
    def get(jwks_uri) do
      send(self(), {:jwks_cache, :get, jwks_uri})
      :miss
    end

    @impl Ltix.JWT.KeySet.Cache
    def put(jwks_uri, _entry, _max_age) do
      send(self(), {:jwks_cache, :put, jwks_uri})
      :ok
    end
  end

  # Returns a result sent by the test for a callback, otherwise delegates.
  defmodule ScriptedStorageAdapter do
    @moduledoc false
    @behaviour Ltix.StorageAdapter

    @impl Ltix.StorageAdapter
    def get_registration(issuer, client_id) do
      scripted(:get_registration, fn -> StorageAdapter.get_registration(issuer, client_id) end)
    end

    @impl Ltix.StorageAdapter
    def get_deployment(registration, deployment_id) do
      scripted(:get_deployment, fn ->
        StorageAdapter.get_deployment(registration, deployment_id)
      end)
    end

    @impl Ltix.StorageAdapter
    def store_nonce(nonce, registration) do
      scripted(:store_nonce, fn -> StorageAdapter.store_nonce(nonce, registration) end)
    end

    @impl Ltix.StorageAdapter
    def validate_nonce(nonce, registration) do
      scripted(:validate_nonce, fn -> StorageAdapter.validate_nonce(nonce, registration) end)
    end

    defp scripted(callback, default) do
      receive do
        {:storage_result, ^callback, result} -> result
      after
        0 -> default.()
      end
    end
  end

  setup do
    previous_configuration =
      Map.new([:allow_anonymous, :storage_adapter, Ltix.LaunchClaims], fn key ->
        {key, Application.fetch_env(:ltix, key)}
      end)

    platform_jwk = Ltix.JWK.generate()
    jwks = Ltix.JWK.to_jwks(platform_jwk)

    {:ok, registration} =
      Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri:
          "https://platform.example.com/.well-known/jwks-#{System.unique_integer([:positive])}.json",
        tool_jwk: Ltix.JWK.generate()
      })

    {:ok, deployment} = Deployment.new("deployment-001")

    platform = %Ltix.Test.Platform{
      registration: registration,
      deployment: deployment,
      jwk: platform_jwk
    }

    {:ok, pid} =
      StorageAdapter.start_link(platforms: [platform])

    StorageAdapter.set_pid(pid)

    {:ok, login} =
      Ltix.handle_login(
        %{
          "iss" => registration.issuer,
          "client_id" => registration.client_id,
          "login_hint" => "user-hint",
          "target_link_uri" => "https://tool.example.com/launch"
        },
        "https://tool.example.com/launch",
        storage_adapter: StorageAdapter
      )

    nonce = Ltix.Test.extract_nonce(login.redirect_uri)
    state = login.state

    Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("cache-control", "max-age=300")
      |> Req.Test.json(jwks)
    end)

    claims = Ltix.Test.valid_lti_claims(platform, %{"nonce" => nonce})
    id_token = Ltix.Test.sign_id_token(claims, platform_jwk)

    on_exit(fn ->
      Enum.each(previous_configuration, fn
        {key, {:ok, value}} -> Application.put_env(:ltix, key, value)
        {key, :error} -> Application.delete_env(:ltix, key)
      end)
    end)

    %{
      platform: platform,
      registration: registration,
      deployment: deployment,
      platform_jwk: platform_jwk,
      nonce: nonce,
      state: state,
      id_token: id_token,
      claims: claims
    }
  end

  describe "handle_login/3" do
    # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
    # [Sec §5.1.1.2](https://www.imsglobal.org/spec/security/v1p0/#step-2-authentication-request)
    test "returns redirect_uri and state" do
      assert {:ok, result} =
               Ltix.handle_login(login_params(), @redirect_uri, storage_adapter: StorageAdapter)

      uri = URI.parse(result.redirect_uri)
      assert uri.host == "platform.example.com"

      query = URI.decode_query(uri.query)
      assert query["scope"] == "openid"
      assert query["response_type"] == "id_token"
      assert query["client_id"] == "tool-client-id"
      assert query["redirect_uri"] == @redirect_uri
      assert query["state"] == result.state
    end

    test "looks up the registration by issuer alone when client_id is empty" do
      assert {:ok, result} =
               Ltix.handle_login(Map.put(login_params(), "client_id", ""), @redirect_uri,
                 storage_adapter: StorageAdapter
               )

      assert URI.decode_query(URI.parse(result.redirect_uri).query)["client_id"] ==
               "tool-client-id"
    end

    test "reads storage_adapter from application config" do
      assert {:ok, %{redirect_uri: redirect_uri, state: state}} =
               Ltix.handle_login(login_params(), @redirect_uri)

      assert redirect_uri =~ "platform.example.com"
      assert byte_size(state) > 0
    end

    test "opts override application config" do
      Application.put_env(:ltix, :storage_adapter, UnregisteredStorageAdapter)

      assert {:error, %RegistrationNotFound{issuer: "https://platform.example.com"}} =
               Ltix.handle_login(login_params(), @redirect_uri)

      assert {:ok, result} =
               Ltix.handle_login(login_params(), @redirect_uri, storage_adapter: StorageAdapter)

      query = URI.decode_query(URI.parse(result.redirect_uri).query)
      assert query["client_id"] == "tool-client-id"
      assert query["redirect_uri"] == @redirect_uri
    end

    test "raises when no storage adapter is passed or configured" do
      Application.delete_env(:ltix, :storage_adapter)

      assert_raise InvalidOption,
                   ~r/Option :storage_adapter is required. Pass it or set it/,
                   fn ->
                     Ltix.handle_login(login_params(), @redirect_uri)
                   end
    end

    test "raises on unknown and invalid options" do
      assert_raise InvalidOption, "Option :storage is unknown", fn ->
        Ltix.handle_login(login_params(), @redirect_uri, storage: StorageAdapter)
      end

      assert_raise InvalidOption, ~r/Option :storage_adapter is invalid/, fn ->
        Ltix.handle_login(login_params(), @redirect_uri, storage_adapter: "StorageAdapter")
      end
    end

    test "reports the redirect_uri it was given in login telemetry" do
      ref = :telemetry_test.attach_event_handlers(self(), [[:ltix, :login, :stop]])

      assert {:ok, _result} =
               Ltix.handle_login(login_params(), @redirect_uri, storage_adapter: StorageAdapter)

      assert_received {[:ltix, :login, :stop], ^ref, _measurements,
                       %{
                         issuer: "https://platform.example.com",
                         client_id: nil,
                         redirect_uri: @redirect_uri
                       }}
    end

    test "delegates errors from underlying modules" do
      params = Map.delete(login_params(), "iss")

      assert {:error, %MissingParameter{parameter: "iss"}} =
               Ltix.handle_login(params, @redirect_uri, storage_adapter: StorageAdapter)
    end
  end

  describe "handle_login!/3" do
    test "returns the redirect or raises the error" do
      assert %{redirect_uri: "https://platform.example.com/auth?" <> _, state: _state} =
               Ltix.handle_login!(login_params(), @redirect_uri, storage_adapter: StorageAdapter)

      assert_raise RegistrationNotFound, fn ->
        Ltix.handle_login!(login_params(), @redirect_uri,
          storage_adapter: UnregisteredStorageAdapter
        )
      end
    end
  end

  describe "handle_callback!/3" do
    test "returns the launch context or raises the error", ctx do
      params = %{"id_token" => ctx.id_token, "state" => ctx.state}

      assert %LaunchContext{} =
               Ltix.handle_callback!(params, ctx.state, req_options: req_options())

      assert_raise MissingParameter, fn ->
        Ltix.handle_callback!(%{"state" => ctx.state}, ctx.state, req_options: req_options())
      end
    end
  end

  describe "handle_callback/3" do
    test "raises on unknown and invalid options", ctx do
      params = %{"id_token" => ctx.id_token, "state" => ctx.state}

      assert_raise InvalidOption, "Option :allow_anonymous_launches is unknown", fn ->
        Ltix.handle_callback(params, ctx.state, allow_anonymous_launches: true)
      end

      assert_raise InvalidOption, ~r/Option :clock_skew is invalid/, fn ->
        Ltix.handle_callback(params, ctx.state, clock_skew: -1)
      end
    end

    test "raises when no storage adapter is passed or configured", ctx do
      Application.delete_env(:ltix, :storage_adapter)
      params = %{"id_token" => ctx.id_token, "state" => ctx.state}

      assert_raise InvalidOption,
                   ~r/Option :storage_adapter is required. Pass it or set it/,
                   fn ->
                     Ltix.handle_callback(params, ctx.state)
                   end
    end

    # [Sec §5.1.1.3](https://www.imsglobal.org/spec/security/v1p0/#step-3-authentication-response)
    test "returns LaunchContext", ctx do
      params = %{"id_token" => ctx.id_token, "state" => ctx.state}

      assert {:ok, %LaunchContext{} = launch} =
               Ltix.handle_callback(params, ctx.state,
                 storage_adapter: StorageAdapter,
                 req_options: req_options()
               )

      assert launch.registration == ctx.registration
      assert launch.deployment == ctx.deployment
      assert launch.claims.message_type == "LtiResourceLinkRequest"
    end

    test "uses the jwks_cache option for platform keys", ctx do
      params = %{"id_token" => ctx.id_token, "state" => ctx.state}
      jwks_uri = ctx.registration.jwks_uri

      assert {:ok, %LaunchContext{}} =
               Ltix.handle_callback(params, ctx.state,
                 jwks_cache: RecordingCache,
                 req_options: req_options()
               )

      assert_received {:jwks_cache, :get, ^jwks_uri}
      assert_received {:jwks_cache, :put, ^jwks_uri}
    end

    test "reports the registration's client_id in callback telemetry", ctx do
      ref = :telemetry_test.attach_event_handlers(self(), [[:ltix, :callback, :stop]])

      claims = Map.put(ctx.claims, "aud", ["tool-client-id"])
      id_token = Ltix.Test.sign_id_token(claims, ctx.platform_jwk)
      params = %{"id_token" => id_token, "state" => ctx.state}

      assert {:ok, %LaunchContext{}} =
               Ltix.handle_callback(params, ctx.state, req_options: req_options())

      assert_received {[:ltix, :callback, :stop], ^ref, _measurements,
                       %{client_id: "tool-client-id", issuer: "https://platform.example.com"}}
    end

    test "reads storage_adapter from application config", ctx do
      params = %{"id_token" => ctx.id_token, "state" => ctx.state}

      assert {:ok, %LaunchContext{}} =
               Ltix.handle_callback(params, ctx.state, req_options: req_options())
    end

    test "reads allow_anonymous from application config", ctx do
      Application.put_env(:ltix, :allow_anonymous, true)

      claims = Map.delete(ctx.claims, "sub")
      id_token = Ltix.Test.sign_id_token(claims, ctx.platform_jwk)
      params = %{"id_token" => id_token, "state" => ctx.state}

      assert {:ok, %LaunchContext{} = launch} =
               Ltix.handle_callback(params, ctx.state, req_options: req_options())

      assert launch.claims.subject == nil
    end

    test "opts override application config", ctx do
      Application.put_env(:ltix, :allow_anonymous, false)

      claims = Map.delete(ctx.claims, "sub")
      id_token = Ltix.Test.sign_id_token(claims, ctx.platform_jwk)
      params = %{"id_token" => id_token, "state" => ctx.state}

      # Override allow_anonymous to true via opts
      assert {:ok, %LaunchContext{}} =
               Ltix.handle_callback(params, ctx.state,
                 allow_anonymous: true,
                 req_options: req_options()
               )
    end

    for {key, prefix, required, field} <- [
          {"https://purl.imsglobal.org/spec/lti/claim/context", "context", %{"id" => "course"},
           "id"},
          {"https://purl.imsglobal.org/spec/lti/claim/context", "context", %{"id" => "course"},
           "label"},
          {"https://purl.imsglobal.org/spec/lti/claim/context", "context", %{"id" => "course"},
           "title"},
          {"https://purl.imsglobal.org/spec/lti/claim/resource_link", "resource_link",
           %{"id" => "link"}, "title"},
          {"https://purl.imsglobal.org/spec/lti/claim/resource_link", "resource_link",
           %{"id" => "link"}, "description"},
          {"https://purl.imsglobal.org/spec/lti/claim/tool_platform", "tool_platform",
           %{"guid" => "platform"}, "guid"},
          {"https://purl.imsglobal.org/spec/lti/claim/tool_platform", "tool_platform",
           %{"guid" => "platform"}, "name"},
          {"https://purl.imsglobal.org/spec/lti/claim/tool_platform", "tool_platform",
           %{"guid" => "platform"}, "contact_email"},
          {"https://purl.imsglobal.org/spec/lti/claim/tool_platform", "tool_platform",
           %{"guid" => "platform"}, "description"},
          {"https://purl.imsglobal.org/spec/lti/claim/tool_platform", "tool_platform",
           %{"guid" => "platform"}, "url"},
          {"https://purl.imsglobal.org/spec/lti/claim/tool_platform", "tool_platform",
           %{"guid" => "platform"}, "product_family_code"},
          {"https://purl.imsglobal.org/spec/lti/claim/tool_platform", "tool_platform",
           %{"guid" => "platform"}, "version"},
          {"https://purl.imsglobal.org/spec/lti/claim/launch_presentation", "launch_presentation",
           %{}, "document_target"},
          {"https://purl.imsglobal.org/spec/lti/claim/launch_presentation", "launch_presentation",
           %{}, "return_url"},
          {"https://purl.imsglobal.org/spec/lti/claim/launch_presentation", "launch_presentation",
           %{}, "locale"},
          {"https://purl.imsglobal.org/spec/lti/claim/lis", "lis", %{}, "person_sourcedid"},
          {"https://purl.imsglobal.org/spec/lti/claim/lis", "lis", %{},
           "course_offering_sourcedid"},
          {"https://purl.imsglobal.org/spec/lti/claim/lis", "lis", %{},
           "course_section_sourcedid"},
          {"https://purl.imsglobal.org/spec/lti-ags/claim/endpoint", "ags_endpoint", %{},
           "lineitems"},
          {"https://purl.imsglobal.org/spec/lti-ags/claim/endpoint", "ags_endpoint", %{},
           "lineitem"},
          {"https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice",
           "memberships_endpoint", %{}, "context_memberships_url"},
          {"https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings",
           "deep_linking_settings",
           %{
             "deep_link_return_url" => "https://platform.example.com/return",
             "accept_types" => [],
             "accept_presentation_document_targets" => []
           }, "deep_link_return_url"},
          {"https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings",
           "deep_linking_settings",
           %{
             "deep_link_return_url" => "https://platform.example.com/return",
             "accept_types" => [],
             "accept_presentation_document_targets" => []
           }, "accept_media_types"},
          {"https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings",
           "deep_linking_settings",
           %{
             "deep_link_return_url" => "https://platform.example.com/return",
             "accept_types" => [],
             "accept_presentation_document_targets" => []
           }, "title"},
          {"https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings",
           "deep_linking_settings",
           %{
             "deep_link_return_url" => "https://platform.example.com/return",
             "accept_types" => [],
             "accept_presentation_document_targets" => []
           }, "text"}
        ] do
      test "handles malformed #{prefix}.#{field} according to its launch role", ctx do
        key = unquote(key)
        field = unquote(field)
        required = unquote(Macro.escape(required))

        for value <- [123, false, %{}, [], [%{}]] do
          assert {:ok, %LaunchContext{claims: claims}} =
                   callback_with_claim(ctx, key, Map.put(required, field, value))

          parsed = Map.fetch!(claims, String.to_existing_atom(unquote(prefix)))

          if field in ["id", "guid", "deep_link_return_url"] do
            assert parsed == nil
          else
            assert Map.fetch!(parsed, struct_field(field)) == nil
          end

          assert claims.subject == "user-12345"
        end
      end
    end

    test "preserves valid builtin strings, optional null fields and numeric dimensions", ctx do
      for {key, body, field, expected} <- [
            {"https://purl.imsglobal.org/spec/lti/claim/context",
             %{"id" => "course", "label" => nil, "title" => "Biology", "type" => []}, :context,
             %Ltix.LaunchClaims.Context{id: "course", label: nil, title: "Biology", type: []}},
            {"https://purl.imsglobal.org/spec/lti/claim/resource_link",
             %{"id" => "link", "title" => nil, "description" => "Read this"}, :resource_link,
             %Ltix.LaunchClaims.ResourceLink{id: "link", title: nil, description: "Read this"}},
            {"https://purl.imsglobal.org/spec/lti/claim/tool_platform",
             %{"guid" => "platform", "name" => nil, "url" => "https://platform.example.com"},
             :tool_platform,
             %Ltix.LaunchClaims.ToolPlatform{
               guid: "platform",
               name: nil,
               url: "https://platform.example.com"
             }},
            {"https://purl.imsglobal.org/spec/lti/claim/launch_presentation",
             %{
               "document_target" => "tab",
               "height" => 600.5,
               "width" => 800,
               "return_url" => nil
             }, :launch_presentation,
             %Ltix.LaunchClaims.LaunchPresentation{
               document_target: "tab",
               height: 600.5,
               width: 800,
               return_url: nil
             }},
            {"https://purl.imsglobal.org/spec/lti/claim/lis",
             %{"person_sourcedid" => nil, "course_offering_sourcedid" => "course"}, :lis,
             %Ltix.LaunchClaims.LIS{person_source_id: nil, course_offering_source_id: "course"}},
            {"https://purl.imsglobal.org/spec/lti-ags/claim/endpoint",
             %{
               "scope" => [],
               "lineitems" => nil,
               "lineitem" => "https://platform.example.com/item"
             }, :ags_endpoint,
             %Ltix.LaunchClaims.AGSEndpoint{
               scopes: [],
               line_items: nil,
               line_item: "https://platform.example.com/item"
             }},
            {"https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice",
             %{"context_memberships_url" => nil, "service_versions" => ["2.0"]},
             :memberships_endpoint,
             %Ltix.LaunchClaims.MembershipsEndpoint{
               context_memberships_url: nil,
               service_versions: ["2.0"]
             }},
            {"https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings",
             %{
               "deep_link_return_url" => "https://platform.example.com/return",
               "accept_types" => [],
               "accept_presentation_document_targets" => [],
               "accept_multiple" => true,
               "accept_lineitem" => false,
               "auto_create" => nil,
               "title" => nil
             }, :deep_linking_settings,
             %Ltix.LaunchClaims.DeepLinkingSettings{
               deep_link_return_url: "https://platform.example.com/return",
               accept_types: [],
               accept_presentation_document_targets: [],
               accept_multiple: true,
               accept_line_item: false,
               auto_create: nil,
               title: nil
             }}
          ] do
        assert {:ok, %LaunchContext{claims: claims}} = callback_with_claim(ctx, key, body)
        assert Map.fetch!(claims, field) == expected
      end
    end

    for field <- ~w(email name given_name family_name middle_name picture locale) do
      test "omits malformed #{field} profile claims", ctx do
        field = unquote(field)

        for value <- [123, false, %{}, [], [%{}]] do
          assert {:ok, %LaunchContext{claims: claims}} =
                   callback_with_claim(ctx, field, value)

          assert Map.fetch!(claims, String.to_existing_atom(field)) == nil
          assert claims.subject == "user-12345"
        end

        assert {:ok, %LaunchContext{claims: claims}} = callback_with_claim(ctx, field, nil)
        assert Map.fetch!(claims, String.to_existing_atom(field)) == nil
      end
    end

    test "rejects nonnumeric issued-at claims and preserves fractional NumericDates", ctx do
      for value <- ["invalid", "123", false, %{}, []] do
        assert {:error, %InvalidClaim{claim: "iat", value: ^value}} =
                 callback_with_claim(ctx, "iat", value)
      end

      for {key, field} <- [{"iat", :issued_at}, {"exp", :expires_at}] do
        value = ctx.claims[key] + 0.5
        assert {:ok, %LaunchContext{claims: claims}} = callback_with_claim(ctx, key, value)
        assert Map.fetch!(claims, field) == value
      end
    end

    test "a claim parser that returns neither {:ok, value} nor {:error, reason} fails the launch",
         ctx do
      parser = fn _value -> "overridden name" end

      assert {:error, %Ltix.Errors.Unknown.Unknown{} = error} =
               callback_with_claim(ctx, "name", "Jane", claim_parsers: %{"name" => parser})

      assert Exception.message(error) =~ ~s(returned "overridden name")
    end

    test "per-call standard claim parsers override configured builtin parsers", ctx do
      key = "https://purl.imsglobal.org/spec/lti/claim/context"

      configured = fn _raw ->
        {:error, InvalidClaim.exception(claim: "configured.context")}
      end

      Application.put_env(:ltix, Ltix.LaunchClaims, claim_parsers: %{key => configured})

      raw = %{"id" => [%{}]}

      assert {:error, %InvalidClaim{claim: "configured.context"}} =
               callback_with_claim(ctx, key, raw)

      override = fn ^raw -> {:ok, %Ltix.LaunchClaims.Context{id: "overridden"}} end

      assert {:ok,
              %LaunchContext{
                claims: %Ltix.LaunchClaims{context: %Ltix.LaunchClaims.Context{id: "overridden"}}
              }} =
               callback_with_claim(ctx, key, raw, claim_parsers: %{key => override})
    end

    test "configured role parsers take precedence over the built-in LIS parser", ctx do
      uri = "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"
      reviewer = %Ltix.LaunchClaims.Role{type: :context, name: :reviewer, uri: uri}

      Application.put_env(:ltix, Ltix.LaunchClaims,
        role_parsers: %{"http://purl.imsglobal.org/vocab/" => fn ^uri -> {:ok, reviewer} end}
      )

      assert {:ok, %LaunchContext{claims: %{roles: [^reviewer]}}} =
               callback_with_claim(ctx, "https://purl.imsglobal.org/spec/lti/claim/roles", [uri])
    end

    test "per-call role parsers take precedence over the built-in LIS parser", ctx do
      uri = "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"
      reviewer = %Ltix.LaunchClaims.Role{type: :context, name: :reviewer, uri: uri}
      parser = fn ^uri -> {:ok, reviewer} end

      assert {:ok, %LaunchContext{claims: %{roles: [^reviewer]}}} =
               callback_with_claim(ctx, "https://purl.imsglobal.org/spec/lti/claim/roles", [uri],
                 role_parsers: %{"http://purl.imsglobal.org/vocab/lis/v2/membership#" => parser}
               )
    end

    test "the built-in LIS parser handles roles a custom parser rejects", ctx do
      uri = "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"

      assert {:ok, %LaunchContext{claims: %{roles: [%{name: :instructor}]}}} =
               callback_with_claim(ctx, "https://purl.imsglobal.org/spec/lti/claim/roles", [uri],
                 role_parsers: %{"http://purl.imsglobal.org/vocab/" => fn _uri -> :error end}
               )
    end

    test "accepts null optional nested claims", ctx do
      for {key, field} <- [
            {"https://purl.imsglobal.org/spec/lti/claim/context", :context},
            {"https://purl.imsglobal.org/spec/lti/claim/tool_platform", :tool_platform},
            {"https://purl.imsglobal.org/spec/lti/claim/launch_presentation",
             :launch_presentation},
            {"https://purl.imsglobal.org/spec/lti/claim/lis", :lis},
            {"https://purl.imsglobal.org/spec/lti-ags/claim/endpoint", :ags_endpoint},
            {"https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice",
             :memberships_endpoint},
            {"https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings",
             :deep_linking_settings}
          ] do
        assert {:ok, %LaunchContext{claims: claims}} = callback_with_claim(ctx, key, nil)
        assert Map.fetch!(claims, field) == nil
      end
    end

    test "delegates errors from underlying modules" do
      params = %{"state" => "some-state"}

      assert {:error, %MissingParameter{parameter: "id_token"}} =
               Ltix.handle_callback(params, "some-state",
                 storage_adapter: StorageAdapter,
                 req_options: req_options()
               )
    end
  end

  describe "storage adapter failures" do
    for callback <- [:get_registration, :store_nonce],
        result <- [{:error, :timeout}, :unexpected] do
      test "handle_login returns StorageError when #{callback} returns #{inspect(result)}" do
        callback = unquote(callback)
        result = unquote(result)
        send(self(), {:storage_result, callback, result})

        assert {:error, %StorageError{callback: ^callback, result: ^result}} =
                 Ltix.handle_login(login_params(), @redirect_uri,
                   storage_adapter: ScriptedStorageAdapter
                 )
      end
    end

    for callback <- [:get_registration, :validate_nonce, :get_deployment],
        result <- [{:error, :timeout}, :unexpected] do
      test "handle_callback returns StorageError when #{callback} returns #{inspect(result)}",
           ctx do
        callback = unquote(callback)
        result = unquote(result)
        send(self(), {:storage_result, callback, result})

        assert {:error, %StorageError{callback: ^callback, result: ^result}} =
                 Ltix.handle_callback(
                   %{"id_token" => ctx.id_token, "state" => ctx.state},
                   ctx.state,
                   storage_adapter: ScriptedStorageAdapter,
                   req_options: req_options()
                 )
      end
    end

    test "a registration that is not Registerable fails the login and launch", ctx do
      for record <- [nil, %{}, %BareRegistration{registration: ctx.registration}] do
        send(self(), {:storage_result, :get_registration, {:ok, record}})

        assert {:error, %StorageError{callback: :get_registration, result: {:ok, ^record}}} =
                 Ltix.handle_login(login_params(), @redirect_uri,
                   storage_adapter: ScriptedStorageAdapter
                 )

        send(self(), {:storage_result, :get_registration, {:ok, record}})

        assert {:error, %StorageError{callback: :get_registration, result: {:ok, ^record}}} =
                 Ltix.handle_callback(
                   %{"id_token" => ctx.id_token, "state" => ctx.state},
                   ctx.state,
                   storage_adapter: ScriptedStorageAdapter,
                   req_options: req_options()
                 )
      end
    end

    test "a deployment that is not Deployable fails the launch", ctx do
      for record <- [nil, %{}] do
        send(self(), {:storage_result, :get_deployment, {:ok, record}})

        assert {:error, %StorageError{callback: :get_deployment, result: {:ok, ^record}} = error} =
                 callback_with_claim(ctx, "sub", ctx.claims["sub"],
                   storage_adapter: ScriptedStorageAdapter
                 )

        assert Exception.message(error) =~ "Ltix.Deployable"
      end
    end

    test "handle_callback returns StorageError when get_deployment returns another deployment",
         ctx do
      other_deployment = Deployment.new!("other-deployment")
      send(self(), {:storage_result, :get_deployment, {:ok, other_deployment}})

      assert {:error,
              %StorageError{callback: :get_deployment, result: {:ok, ^other_deployment}} = error} =
               Ltix.handle_callback(
                 %{"id_token" => ctx.id_token, "state" => ctx.state},
                 ctx.state,
                 storage_adapter: ScriptedStorageAdapter,
                 req_options: req_options()
               )

      assert Exception.message(error) ==
               ~s(Storage adapter callback get_deployment returned deployment "other-deployment" ) <>
                 ~s(for deployment_id "deployment-001")
    end

    test "an invalid registration struct from the storage adapter fails the login", ctx do
      registration = %{ctx.registration | jwks_uri: "http://platform.example.com/jwks"}
      send(self(), {:storage_result, :get_registration, {:ok, registration}})

      assert {:error, %InvalidField{struct: Registration, field: :jwks_uri}} =
               Ltix.handle_login(login_params(), @redirect_uri,
                 storage_adapter: ScriptedStorageAdapter
               )
    end

    test "Ltix errors returned by the storage adapter are returned unchanged", ctx do
      error = DeploymentNotFound.exception(deployment_id: "deployment-001")
      send(self(), {:storage_result, :get_deployment, {:error, error}})

      assert {:error, ^error} =
               Ltix.handle_callback(
                 %{"id_token" => ctx.id_token, "state" => ctx.state},
                 ctx.state,
                 storage_adapter: ScriptedStorageAdapter,
                 req_options: req_options()
               )
    end
  end

  # Claim names the specification spells differently from struct fields.
  @struct_fields %{
    "lineitems" => :line_items,
    "lineitem" => :line_item,
    "scope" => :scopes,
    "person_sourcedid" => :person_source_id,
    "course_offering_sourcedid" => :course_offering_source_id,
    "course_section_sourcedid" => :course_section_source_id
  }

  defp struct_field(claim_name) do
    Map.get_lazy(@struct_fields, claim_name, fn -> String.to_existing_atom(claim_name) end)
  end

  defp callback_with_claim(ctx, key, value, opts \\ []) do
    {:ok, login} =
      Ltix.handle_login(login_params(), @redirect_uri, storage_adapter: StorageAdapter)

    nonce = Ltix.Test.extract_nonce(login.redirect_uri)

    claims =
      ctx.claims
      |> Map.put("nonce", nonce)
      |> Map.put(key, value)

    id_token = Ltix.Test.sign_id_token(claims, ctx.platform_jwk)

    Ltix.handle_callback(
      %{"id_token" => id_token, "state" => login.state},
      login.state,
      Keyword.merge([storage_adapter: StorageAdapter, req_options: req_options()], opts)
    )
  end

  defp login_params do
    %{
      "iss" => "https://platform.example.com",
      "login_hint" => "user-hint-123",
      "target_link_uri" => "https://tool.example.com/launch"
    }
  end

  defp req_options, do: [plug: {Req.Test, Ltix.JWT.KeySet}]
end
