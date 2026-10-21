defmodule Ltix.OAuthTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid
  alias Ltix.Errors.Invalid.InvalidEndpoint
  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.Errors.Invalid.InvalidOption
  alias Ltix.Errors.Invalid.MalformedResponse
  alias Ltix.Errors.Invalid.ScopeMismatch
  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.Errors.Invalid.TokenRequestFailed
  alias Ltix.Errors.Unknown.InvalidPluginSet
  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.Errors.Unknown.Unknown
  alias Ltix.Launch
  alias Ltix.OAuth
  alias Ltix.OAuth.Client
  alias Ltix.PluginSet.Conflict
  alias Ltix.PluginSet.Entry
  alias Ltix.Test.StorageAdapter
  alias TestPlugins.Calendar
  alias TestPlugins.Modules
  alias TestPlugins.Records

  @records_scope "https://example.com/scope/records.readonly"
  @calendar_scope "https://example.com/scope/calendar.write"
  @nrps_scope "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"
  @ags_scopes [
    "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
    "https://purl.imsglobal.org/spec/lti-ags/scope/score"
  ]

  @records_claim "https://tool.example.com/claim/records"
  @calendar_claim "https://tool.example.com/claim/calendar"
  @tenant_claim "https://tool.example.com/claim/tenant"

  @plugins [Records, Calendar]

  setup do
    {:ok, registration} =
      Ltix.Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri: "https://platform.example.com/.well-known/jwks.json",
        token_endpoint: "https://platform.example.com/token"
      })

    %{registration: registration}
  end

  defp req_options, do: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]

  defp records_endpoint, do: %Records.Endpoint{url: "https://platform.example.com/records"}
  defp calendar_endpoint, do: %Calendar.Endpoint{url: "https://platform.example.com/calendar"}

  # Authenticates with the service plugins, against the token endpoint stub.
  defp authenticate(subject, opts), do: OAuth.authenticate(subject, defaults(opts))
  defp authenticate!(subject, opts), do: OAuth.authenticate!(subject, defaults(opts))

  defp defaults(opts), do: Keyword.merge([plugins: @plugins, req_options: req_options()], opts)

  defp build_launch(opts \\ []) do
    platform = Ltix.Test.setup_platform!()

    Ltix.Test.build_launch(
      platform,
      Keyword.merge(
        [
          plugins: @plugins,
          claims: %{
            @records_claim => %{"url" => "https://platform.example.com/records"},
            @calendar_claim => %{"url" => "https://platform.example.com/calendar"}
          }
        ],
        opts
      )
    )
  end

  # Sends `{:token_request, scopes, assertion_claims}` for each token request.
  defp capture_token_requests do
    owner = self()
    public_jwk = JOSE.JWK.to_public(Ltix.JWK.to_jose(StorageAdapter.tool_jwk()))

    Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = URI.decode_query(body)

      {true, %JOSE.JWT{fields: claims}, _jws} =
        JOSE.JWT.verify(public_jwk, params["client_assertion"])

      send(owner, {:token_request, String.split(params["scope"]), claims})

      Req.Test.json(conn, %{
        "access_token" => "captured-token",
        "token_type" => "Bearer",
        "expires_in" => 3600
      })
    end)
  end

  describe "authenticate/2" do
    test "raises ArgumentError for a registration that doesn't convert", ctx do
      assert_raise ArgumentError, ~r/Ltix.Registerable/, fn ->
        authenticate(%BareRegistration{registration: ctx.registration},
          endpoints: %{Records => records_endpoint()}
        )
      end
    end

    test "acquires token with single-service endpoint", ctx do
      Ltix.Test.stub_token_response(scopes: [@records_scope])

      assert {:ok, %Client{} = client} =
               authenticate(ctx.registration,
                 endpoints: %{Records => records_endpoint()}
               )

      assert client.token.access_token == "test-token"
      assert MapSet.member?(client.token.granted_scopes, @records_scope)
      assert client.endpoints == %{Records => records_endpoint()}
      assert client.registration == ctx.registration
    end

    test "configured token response helper grants only its configured scopes", ctx do
      Ltix.Test.stub_token_response(scopes: [@calendar_scope], access_token: "configured-token")

      assert {:ok, %Client{token: %{access_token: "configured-token"}} = client} =
               authenticate(ctx.registration,
                 endpoints: %{
                   Records => records_endpoint(),
                   Calendar => calendar_endpoint()
                 }
               )

      assert client.token.granted_scopes == MapSet.new([@calendar_scope])
    end

    test "multiple endpoints send space-separated scopes", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)
        scope_parts = String.split(params["scope"])

        assert @records_scope in scope_parts
        assert @calendar_scope in scope_parts

        Req.Test.json(conn, %{
          "access_token" => "multi-token",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "#{@records_scope} #{@calendar_scope}"
        })
      end)

      assert {:ok, %Client{} = client} =
               authenticate(ctx.registration,
                 endpoints: %{
                   Records => records_endpoint(),
                   Calendar => calendar_endpoint()
                 }
               )

      assert MapSet.member?(client.token.granted_scopes, @records_scope)
      assert MapSet.member?(client.token.granted_scopes, @calendar_scope)
    end

    test "granted scopes are the scopes in the platform response", ctx do
      # Platform grants only a subset
      Ltix.Test.stub_token_response(scopes: [@records_scope])

      assert {:ok, %Client{} = client} =
               authenticate(ctx.registration,
                 endpoints: %{
                   Records => records_endpoint(),
                   Calendar => calendar_endpoint()
                 }
               )

      assert MapSet.member?(client.token.granted_scopes, @records_scope)
      refute MapSet.member?(client.token.granted_scopes, @calendar_scope)
    end

    test "require_all_scopes returns ScopeMismatch when the platform grants only some", ctx do
      Ltix.Test.stub_token_response(scopes: [@records_scope])

      assert {:error, %ScopeMismatch{scopes: [@calendar_scope]}} =
               authenticate(ctx.registration,
                 endpoints: %{Records => records_endpoint(), Calendar => calendar_endpoint()},
                 require_all_scopes: true
               )
    end

    test "accepts mixed-case bearer with optional fields absent and ignores extensions", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        Req.Test.json(conn, %{
          "access_token" => "extension-token",
          "token_type" => "bEaReR",
          "platform_extension" => %{"arbitrary" => [1, nil, false]}
        })
      end)

      before_request = DateTime.utc_now()

      assert {:ok, %Client{token: %{access_token: "extension-token"}} = client} =
               authenticate(ctx.registration,
                 endpoints: %{Records => records_endpoint()}
               )

      after_request = DateTime.utc_now()
      assert client.token.granted_scopes == MapSet.new([@records_scope])
      assert DateTime.compare(client.token.expires_at, DateTime.add(before_request, 3600)) != :lt
      assert DateTime.compare(client.token.expires_at, DateTime.add(after_request, 3600)) != :gt
    end

    test "accepts a compliant response and applies a zero lifetime", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        Req.Test.json(conn, %{
          "access_token" => "expired-token",
          "token_type" => "BEARER",
          "expires_in" => 0,
          "scope" => @records_scope
        })
      end)

      before_request = System.system_time(:microsecond)

      assert {:ok, %Client{token: %{access_token: "expired-token"}} = client} =
               authenticate(ctx.registration,
                 endpoints: %{Records => records_endpoint()}
               )

      after_request = System.system_time(:microsecond)
      expires_at = DateTime.to_unix(client.token.expires_at, :microsecond)
      assert expires_at >= before_request
      assert expires_at <= after_request
      assert Client.expired?(client)
      assert client.token.granted_scopes == MapSet.new([@records_scope])
    end

    test "a token with a lifetime under a minute is usable for half its lifetime", ctx do
      Ltix.Test.stub_token_response(expires_in: 30)

      assert {:ok, client} =
               authenticate(ctx.registration,
                 endpoints: %{Records => records_endpoint()}
               )

      refute Client.expired?(client)
      assert {:ok, ^client} = Client.refresh(client)

      issued_16_seconds_ago = %{
        client.token
        | issued_at: DateTime.add(client.token.issued_at, -16),
          expires_at: DateTime.add(client.token.expires_at, -16)
      }

      assert Client.expired?(%{client | token: issued_16_seconds_ago})
    end

    for {field, value} <- [
          {"access_token", 123},
          {"access_token", "token\r\nInjected"},
          {"token_type", 123},
          {"token_type", "MAC"},
          {"expires_in", nil},
          {"expires_in", -1},
          {"expires_in", 999_999_999_999_999_999_999},
          {"scope", nil},
          {"scope", ""},
          {"scope", "scope.read\tscope.write"},
          {"scope", " scope.read"},
          {"scope", "scope.\"read"},
          {"scope", "scope.é"}
        ] do
      test "returns MalformedResponse for #{field} value #{inspect(value)}", ctx do
        body =
          Map.put(
            %{
              "access_token" => "test-token",
              "token_type" => "Bearer",
              "expires_in" => 3600,
              "scope" => @records_scope
            },
            unquote(field),
            unquote(Macro.escape(value))
          )

        Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
          Req.Test.json(conn, body)
        end)

        assert {:error, %MalformedResponse{service: :oauth}} =
                 authenticate(ctx.registration,
                   endpoints: %{Records => records_endpoint()}
                 )
      end
    end

    for field <- ["access_token", "token_type"] do
      test "returns MalformedResponse when #{field} is missing", ctx do
        body =
          Map.delete(%{"access_token" => "test-token", "token_type" => "Bearer"}, unquote(field))

        Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
          Req.Test.json(conn, body)
        end)

        assert {:error, %MalformedResponse{service: :oauth}} =
                 authenticate(ctx.registration,
                   endpoints: %{Records => records_endpoint()}
                 )
      end
    end

    test "returns MalformedResponse for JSON body []", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        Req.Test.json(conn, [])
      end)

      assert {:error, %MalformedResponse{service: :oauth}} =
               authenticate(ctx.registration,
                 endpoints: %{Records => records_endpoint()}
               )
    end

    test "returns MalformedResponse for invalid JSON", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, "{not-json}")
      end)

      assert {:error, %MalformedResponse{service: :oauth}} =
               authenticate(ctx.registration,
                 endpoints: %{Records => records_endpoint()}
               )
    end

    test "preserves HTTP 400 and body when the advertised JSON is invalid", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, "{not-json}")
      end)

      assert {:error, %TokenRequestFailed{status: 400, body: "{not-json}"}} =
               authenticate(ctx.registration,
                 endpoints: %{Records => records_endpoint()}
               )
    end

    test "accepts bearer credential punctuation and OAuth scope punctuation", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        Req.Test.json(conn, %{
          "access_token" => "aZ09-._~+/==",
          "token_type" => "Bearer",
          "scope" => "!#[scope]~ other.scope"
        })
      end)

      assert {:ok, %Client{token: %{access_token: "aZ09-._~+/=="}} = client} =
               authenticate(ctx.registration,
                 endpoints: %{Records => records_endpoint()}
               )

      assert client.token.granted_scopes == MapSet.new(["!#[scope]~", "other.scope"])
    end

    test "accepts JSON media type parameters and whitespace", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json ; charset=utf-8")
        |> Plug.Conn.send_resp(200, ~s({"access_token":"media-type-token","token_type":"Bearer"}))
      end)

      assert {:ok, %Client{token: %{access_token: "media-type-token"}}} =
               authenticate(ctx.registration,
                 endpoints: %{Records => records_endpoint()}
               )
    end

    for status <- [201, 400] do
      test "rejects token-shaped HTTP #{status} responses", ctx do
        status = unquote(status)
        body = %{"access_token" => "must-not-be-used", "token_type" => "Bearer"}

        Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
          conn
          |> Plug.Conn.put_status(status)
          |> Req.Test.json(body)
        end)

        assert {:error, %TokenRequestFailed{status: ^status, body: ^body}} =
                 authenticate(ctx.registration,
                   endpoints: %{Records => records_endpoint()}
                 )
      end
    end

    test "preserves OAuth error details and HTTP 400", ctx do
      body = %{"error" => "invalid_client", "error_description" => "Unknown client"}

      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(body)
      end)

      assert {:error,
              %TokenRequestFailed{
                status: 400,
                error: "invalid_client",
                error_description: "Unknown client",
                body: ^body
              }} =
               authenticate(ctx.registration,
                 endpoints: %{Records => records_endpoint()}
               )
    end

    test "preserves a non-JSON error response", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        Plug.Conn.send_resp(conn, 502, "Bad Gateway")
      end)

      assert {:error, %TokenRequestFailed{status: 502, body: "Bad Gateway"}} =
               authenticate(ctx.registration,
                 endpoints: %{Records => records_endpoint()}
               )
    end

    test "rejects a non-JSON HTTP 200 response", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        Plug.Conn.send_resp(conn, 200, "<html>Not a token</html>")
      end)

      assert {:error, %MalformedResponse{service: :oauth}} =
               authenticate(ctx.registration,
                 endpoints: %{Records => records_endpoint()}
               )
    end

    test "network failure returns TransportError", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, &Req.Test.transport_error(&1, :econnrefused))

      assert {:error, %TransportError{url: "https://platform.example.com/token", status: nil}} =
               authenticate(ctx.registration,
                 endpoints: %{Records => records_endpoint()},
                 req_options: req_options() ++ [retry: false]
               )
    end

    test "raises on missing, unknown, and invalid options", ctx do
      assert_raise InvalidOption, "Option :endpoints is required", fn ->
        OAuth.authenticate(ctx.registration, [])
      end

      assert_raise InvalidOption, "Option :endpoint is unknown", fn ->
        authenticate(ctx.registration,
          endpoints: %{Records => records_endpoint()},
          endpoint: records_endpoint()
        )
      end

      assert_raise InvalidOption, ~r/Option :endpoints is invalid/, fn ->
        authenticate(ctx.registration, endpoints: [Records])
      end
    end
  end

  describe "authenticate/2 endpoints" do
    test "checks each endpoint with its endpoint claim before any token request", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn _conn -> flunk("token request was sent") end)

      assert {:error, %InvalidField{struct: Records.Endpoint, field: :url}} =
               authenticate(ctx.registration,
                 endpoints: %{Records => %Records.Endpoint{url: "http://platform.example.com"}}
               )

      assert {:error, %InvalidEndpoint{service: Records} = error} =
               authenticate(ctx.registration, endpoints: %{Records => calendar_endpoint()})

      assert Exception.message(error) == "Invalid endpoint for TestPlugins.Records"
    end

    test "returns ServiceNotAvailable for a service no plugin declares an endpoint claim for",
         ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn _conn -> flunk("token request was sent") end)

      assert {:error, %ServiceNotAvailable{service: Calendar} = error} =
               authenticate(ctx.registration,
                 endpoints: %{Calendar => calendar_endpoint()},
                 plugins: [Records]
               )

      assert Exception.message(error) =~ "No plugin declares the endpoint claim of this service"
    end

    test "a plugin set with an endpoint claim that can't check endpoints doesn't resolve",
         ctx do
      unchecked = {Modules, add: [TestPlugins.UncheckedEndpoint]}

      assert {:error, %InvalidPluginSet{conflicts: [conflict]}} =
               authenticate(ctx.registration, endpoints: %{}, plugins: [unchecked])

      assert %Conflict{
               parties: [%Entry{module: TestPlugins.UncheckedEndpoint}],
               reason:
                 "declares the endpoint of TestPlugins.Unchecked, which needs the fields option and new/1"
             } = conflict
    end

    test "requests the scopes Ltix's services need, as a launch does" do
      capture_token_requests()

      launch =
        build_launch(
          plugins: [],
          memberships_endpoint: "https://platform.example.com/memberships",
          ags_endpoint: %{
            line_items: "https://platform.example.com/lineitems",
            scopes: @ags_scopes
          }
        )

      services = [Ltix.MembershipsService, Ltix.GradeService]

      assert {:ok, _client} = authenticate(launch, services: services, plugins: [])
      assert_received {:token_request, launch_scopes, _claims}
      assert Enum.sort(launch_scopes) == Enum.sort([@nrps_scope | @ags_scopes])

      assert {:ok, _client} =
               authenticate(launch.source_registration,
                 endpoints: Map.new(services, &{&1, Launch.get_endpoint(launch, &1)}),
                 plugins: []
               )

      assert_received {:token_request, registration_scopes, _claims}
      assert Enum.sort(registration_scopes) == Enum.sort(launch_scopes)
    end

    test "requests each scope once", ctx do
      capture_token_requests()

      assert {:ok, _client} =
               authenticate(ctx.registration,
                 endpoints: %{Records => records_endpoint()},
                 plugins: [Records, Records]
               )

      assert_received {:token_request, [@records_scope], _claims}
    end
  end

  describe "authenticate/2 client assertion" do
    test "has the claims the client credentials grant requires, and a new jti each time", ctx do
      capture_token_requests()

      for _ <- 1..2 do
        assert {:ok, _client} = authenticate(ctx.registration, endpoints: %{})
      end

      jtis =
        for _ <- 1..2 do
          assert_received {:token_request, [],
                           %{
                             "iss" => "tool-client-id",
                             "sub" => "tool-client-id",
                             "aud" => "https://platform.example.com/token",
                             "iat" => iat,
                             "exp" => exp,
                             "jti" => jti
                           }}

          assert_in_delta iat, System.system_time(:second), 5
          assert exp - iat == 300
          jti
        end

      assert Enum.uniq(jtis) == jtis
    end

    test "is sent as a client credentials grant form", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)

        assert params["grant_type"] == "client_credentials"

        assert params["client_assertion_type"] ==
                 "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

        assert params["scope"] == @records_scope
        assert [content_type] = Plug.Conn.get_req_header(conn, "content-type")
        assert content_type =~ "application/x-www-form-urlencoded"

        Req.Test.json(conn, %{"access_token" => "form-test", "token_type" => "Bearer"})
      end)

      assert {:ok, _client} =
               authenticate(ctx.registration, endpoints: %{Records => records_endpoint()})
    end

    test "returns ServiceNotAvailable for a registration without a token endpoint", ctx do
      registration = %{ctx.registration | token_endpoint: nil}

      assert {:error, %ServiceNotAvailable{service: :oauth} = error} =
               authenticate(registration, endpoints: %{})

      assert Exception.message(error) =~ "The registration has no token endpoint"
    end

    test "a step's claims are in the first token, a refresh, and the registration form" do
      capture_token_requests()

      tenant =
        {Modules, add: [{TestPlugins.AssertionClaims, claims: %{@tenant_claim => "acme"}}]}

      launch = build_launch(plugins: [Records, tenant])

      assert {:ok, client} =
               OAuth.authenticate(launch, services: [Records], req_options: req_options())

      assert_received {:token_request, [@records_scope], %{@tenant_claim => "acme"}}

      assert {:ok, _client} = Client.force_refresh(client)
      assert_received {:token_request, [@records_scope], %{@tenant_claim => "acme"}}

      assert {:ok, _client} =
               authenticate(launch.source_registration,
                 endpoints: %{Records => records_endpoint()},
                 plugins: [Records, tenant]
               )

      assert_received {:token_request, [@records_scope], %{@tenant_claim => "acme"}}
    end

    test "an anonymous step a plugin adds with add_step/2 adds claims", ctx do
      capture_token_requests()

      build = fn plugin ->
        Ltix.ClientAssertion.add_step(plugin, fn assertion ->
          {:ok, put_in(assertion.claims[@tenant_claim], "acme")}
        end)
      end

      assert {:ok, _client} =
               authenticate(ctx.registration,
                 endpoints: %{Records => records_endpoint()},
                 plugins: [Records, {Modules, build: build}]
               )

      assert_received {:token_request, [@records_scope], %{@tenant_claim => "acme"}}
    end

    test "steps start with the requested endpoints and no scopes or claims" do
      capture_token_requests()
      tenant = {Modules, add: [{TestPlugins.AssertionClaims, claims: %{}}]}
      launch = build_launch(plugins: [tenant, Records, Calendar])

      assert {:ok, _client} =
               OAuth.authenticate(launch, services: [Calendar], req_options: req_options())

      assert_received {:client_assertion,
                       %Ltix.ClientAssertion{
                         endpoints: %{Calendar => %Calendar.Endpoint{}} = endpoints,
                         scopes: [],
                         claims: claims
                       }}

      assert map_size(endpoints) == 1
      assert claims == %{}
      assert_received {:token_request, [@calendar_scope], _claims}
    end

    test "the claims the client assertion requires replace a step's claims of the same name",
         ctx do
      capture_token_requests()

      steps = [
        {TestPlugins.AssertionClaims, claims: %{"iss" => "someone-else", "aud" => "elsewhere"}}
      ]

      assert {:ok, _client} =
               authenticate(ctx.registration,
                 endpoints: %{Records => records_endpoint()},
                 plugins: [Records, {Modules, add: steps}]
               )

      assert_received {:token_request, _scopes,
                       %{"iss" => "tool-client-id", "aud" => "https://platform.example.com/token"}}
    end

    test "steps read the plugin set the token is requested with", ctx do
      capture_token_requests()
      plugins = [Records, {Modules, add: [TestPlugins.AssertionPlugins]}]

      assert {:ok, _client} =
               authenticate(ctx.registration,
                 endpoints: %{Records => records_endpoint()},
                 plugins: plugins
               )

      {:ok, plugin_set} = Ltix.PluginSet.resolve(plugins)
      assert_received {:assertion_plugins, ^plugin_set}
    end

    test "a step's errors are returned before anything is signed", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn _conn -> flunk("token request was sent") end)
      error = Unknown.exception(error: :tenant_unknown)

      assert {:error, ^error} =
               authenticate(ctx.registration,
                 endpoints: %{Records => records_endpoint()},
                 plugins: [
                   Records,
                   {Modules, add: [{TestPlugins.AssertionError, error: error}]}
                 ]
               )
    end
  end

  describe "authenticate/2 from a launch" do
    test "requests the scopes of each service's endpoint from the launch" do
      Ltix.Test.stub_token_response(scopes: [@records_scope, @calendar_scope])
      launch = build_launch()

      assert {:ok, %Client{} = client} = authenticate(launch, services: [Records, Calendar])

      assert client.endpoints == %{
               Records => records_endpoint(),
               Calendar => calendar_endpoint()
             }

      assert client.token.granted_scopes == MapSet.new([@records_scope, @calendar_scope])
      assert client.registration == launch.source_registration
    end

    test "requests the memberships service's scope" do
      capture_token_requests()
      launch = build_launch(memberships_endpoint: "https://platform.example.com/memberships")

      assert {:ok, _client} = authenticate(launch, services: [Ltix.MembershipsService])
      assert_received {:token_request, [@nrps_scope], _claims}
    end

    test "returns ServiceNotAvailable for each service missing from the launch, before the client assertion runs" do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn _conn -> flunk("token request was sent") end)
      tenant = {Modules, add: [{TestPlugins.AssertionClaims, claims: %{}}]}
      launch = build_launch(plugins: [Records, Calendar, tenant], claims: %{})

      assert {:error, %ServiceNotAvailable{service: Records} = error} =
               OAuth.authenticate(launch, services: [Records])

      assert Exception.message(error) =~ "The launch has no endpoint claim for this service"

      assert {:error,
              %Invalid{
                errors: [
                  %ServiceNotAvailable{service: Records},
                  %ServiceNotAvailable{service: Ltix.MembershipsService}
                ]
              }} =
               OAuth.authenticate(launch, services: [Records, Ltix.MembershipsService])

      refute_received {:client_assertion, _assertion}
    end

    test "the client keeps the launch's plugin set, and plugins: replaces it" do
      capture_token_requests()

      tenant =
        {Modules, add: [{TestPlugins.AssertionClaims, claims: %{@tenant_claim => "acme"}}]}

      launch = build_launch(plugins: [Records, tenant])

      assert {:ok, client} =
               OAuth.authenticate(launch, services: [Records], req_options: req_options())

      assert client.plugins == launch.plugins
      assert_received {:token_request, _scopes, %{@tenant_claim => "acme"}}

      assert {:ok, client} =
               authenticate(launch, services: [Records], plugins: [Records])

      assert {:ok, plugins} = Ltix.PluginSet.resolve([Records])
      assert client.plugins == plugins
      assert_received {:token_request, _scopes, claims}
      refute Map.has_key?(claims, @tenant_claim)

      assert {:ok, _client} = Client.force_refresh(client)
      assert_received {:token_request, _scopes, claims}
      refute Map.has_key?(claims, @tenant_claim)
    end

    test "require_all_scopes returns ScopeMismatch when the platform grants only some" do
      Ltix.Test.stub_token_response(scopes: [@records_scope])
      launch = build_launch()

      assert {:error, %ScopeMismatch{scopes: [@calendar_scope]}} =
               authenticate(launch, services: [Records, Calendar], require_all_scopes: true)
    end

    test "raises on missing, unknown, and invalid options" do
      launch = build_launch()

      assert_raise InvalidOption, "Option :services is required", fn ->
        OAuth.authenticate(launch)
      end

      assert_raise InvalidOption, "Option :endpoints is unknown", fn ->
        authenticate(launch, services: [Records], endpoints: %{})
      end

      assert_raise InvalidOption, ~r/Option :services is invalid/, fn ->
        authenticate(launch, services: Records)
      end
    end
  end

  describe "authenticate!/2" do
    test "returns unwrapped client on success", ctx do
      Ltix.Test.stub_token_response(scopes: [@records_scope])

      assert %Client{} =
               authenticate!(ctx.registration, endpoints: %{Records => records_endpoint()})
    end

    test "raises on error", ctx do
      assert_raise InvalidEndpoint, fn ->
        authenticate!(ctx.registration, endpoints: %{Records => calendar_endpoint()})
      end
    end
  end
end
