defmodule LtixTest do
  use ExUnit.Case

  alias Ltix.Deployment
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingParameter
  alias Ltix.Errors.Invalid.RegistrationNotFound
  alias Ltix.LaunchContext
  alias Ltix.Registration
  alias Ltix.Test.JWTHelper
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

  setup do
    previous_configuration =
      Map.new([:allow_anonymous, :storage_adapter], fn key ->
        {key, Application.fetch_env(:ltix, key)}
      end)

    {private, public, kid} = JWTHelper.generate_rsa_key_pair()
    jwks = JWTHelper.build_jwks([public])

    {:ok, registration} =
      Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri: "https://platform.example.com/.well-known/jwks.json",
        tool_jwk: Ltix.JWK.generate()
      })

    {:ok, deployment} = Deployment.new("deployment-001")

    {:ok, pid} =
      StorageAdapter.start_link(
        registrations: [registration],
        deployments: [deployment]
      )

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

    claims = JWTHelper.valid_lti_claims(%{"nonce" => nonce})
    id_token = JWTHelper.mint_id_token(claims, private, kid: kid)

    on_exit(fn ->
      Enum.each(previous_configuration, fn
        {key, {:ok, value}} -> Application.put_env(:ltix, key, value)
        {key, :error} -> Application.delete_env(:ltix, key)
      end)
    end)

    %{
      registration: registration,
      deployment: deployment,
      private: private,
      kid: kid,
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

    test "delegates errors from underlying modules" do
      params = Map.delete(login_params(), "iss")

      assert {:error, %MissingParameter{parameter: "iss"}} =
               Ltix.handle_login(params, @redirect_uri, storage_adapter: StorageAdapter)
    end
  end

  describe "handle_callback/3" do
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

    test "reads storage_adapter from application config", ctx do
      params = %{"id_token" => ctx.id_token, "state" => ctx.state}

      assert {:ok, %LaunchContext{}} =
               Ltix.handle_callback(params, ctx.state, req_options: req_options())
    end

    test "reads allow_anonymous from application config", ctx do
      Application.put_env(:ltix, :allow_anonymous, true)

      claims = Map.delete(ctx.claims, "sub")
      id_token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)
      params = %{"id_token" => id_token, "state" => ctx.state}

      assert {:ok, %LaunchContext{} = launch} =
               Ltix.handle_callback(params, ctx.state, req_options: req_options())

      assert launch.claims.subject == nil
    end

    test "opts override application config", ctx do
      Application.put_env(:ltix, :allow_anonymous, false)

      claims = Map.delete(ctx.claims, "sub")
      id_token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)
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
            assert Map.fetch!(parsed, String.to_existing_atom(field)) == nil
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
             %Ltix.LaunchClaims.Lis{person_sourcedid: nil, course_offering_sourcedid: "course"}},
            {"https://purl.imsglobal.org/spec/lti-ags/claim/endpoint",
             %{
               "scope" => [],
               "lineitems" => nil,
               "lineitem" => "https://platform.example.com/item"
             }, :ags_endpoint,
             %Ltix.LaunchClaims.AgsEndpoint{
               scope: [],
               lineitems: nil,
               lineitem: "https://platform.example.com/item"
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
               accept_lineitem: false,
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

    test "per-call standard claim parsers override configured builtin parsers", ctx do
      key = "https://purl.imsglobal.org/spec/lti/claim/context"
      previous = Application.get_env(:ltix, Ltix.LaunchClaims)

      on_exit(fn ->
        if previous == nil,
          do: Application.delete_env(:ltix, Ltix.LaunchClaims),
          else: Application.put_env(:ltix, Ltix.LaunchClaims, previous)
      end)

      configured = fn _raw ->
        {:error, InvalidClaim.exception(claim: "configured.context")}
      end

      Application.put_env(
        :ltix,
        Ltix.LaunchClaims,
        Keyword.put(previous || [], :claim_parsers, %{key => configured})
      )

      raw = %{"id" => [%{}]}
      override = fn ^raw -> {:ok, %Ltix.LaunchClaims.Context{id: "overridden"}} end

      assert {:ok,
              %LaunchContext{
                claims: %Ltix.LaunchClaims{context: %Ltix.LaunchClaims.Context{id: "overridden"}}
              }} =
               callback_with_claim(ctx, key, raw, claim_parsers: %{key => override})
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

  defp callback_with_claim(ctx, key, value, opts \\ []) do
    {:ok, login} =
      Ltix.handle_login(login_params(), @redirect_uri, storage_adapter: StorageAdapter)

    nonce = Ltix.Test.extract_nonce(login.redirect_uri)

    claims =
      ctx.claims
      |> Map.put("nonce", nonce)
      |> Map.put(key, value)

    id_token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)

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
