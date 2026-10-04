defmodule Ltix.OAuthTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid
  alias Ltix.Errors.Invalid.InvalidEndpoint
  alias Ltix.Errors.Invalid.InvalidOption
  alias Ltix.Errors.Invalid.MalformedResponse
  alias Ltix.Errors.Invalid.ScopeMismatch
  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.Errors.Invalid.TokenRequestFailed
  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.LaunchClaims
  alias Ltix.LaunchContext
  alias Ltix.OAuth
  alias Ltix.OAuth.Client

  @test_scope "https://example.com/scope/test.readonly"
  @other_scope "https://example.com/scope/other.write"
  @launch_extensions %{"test" => :valid_endpoint, "other" => :other_endpoint}

  defmodule TestService do
    @behaviour Ltix.AdvantageService

    @impl Ltix.AdvantageService
    def endpoint_from_claims(%{extensions: %{"test" => endpoint}}), do: {:ok, endpoint}
    def endpoint_from_claims(_), do: :error

    @impl Ltix.AdvantageService
    def validate_endpoint(:valid_endpoint), do: :ok

    def validate_endpoint(_),
      do: {:error, InvalidEndpoint.exception(service: __MODULE__, spec_ref: "test")}

    @impl Ltix.AdvantageService
    def scopes(:valid_endpoint),
      do: ["https://example.com/scope/test.readonly"]
  end

  defmodule OtherService do
    @behaviour Ltix.AdvantageService

    @impl Ltix.AdvantageService
    def endpoint_from_claims(%{extensions: %{"other" => endpoint}}), do: {:ok, endpoint}
    def endpoint_from_claims(_), do: :error

    @impl Ltix.AdvantageService
    def validate_endpoint(:other_endpoint), do: :ok

    def validate_endpoint(_),
      do: {:error, InvalidEndpoint.exception(service: __MODULE__, spec_ref: "test")}

    @impl Ltix.AdvantageService
    def scopes(:other_endpoint),
      do: ["https://example.com/scope/other.write"]
  end

  setup do
    tool_jwk = Ltix.JWK.generate()

    {:ok, registration} =
      Ltix.Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri: "https://platform.example.com/.well-known/jwks.json",
        token_endpoint: "https://platform.example.com/token",
        tool_jwk: tool_jwk
      })

    custom_registration = %CustomRegistration{
      id: "reg-001",
      tenant_id: "tenant-1",
      platform_issuer: "https://platform.example.com",
      oauth_client_id: "tool-client-id",
      oidc_auth_url: "https://platform.example.com/auth",
      platform_jwks_url: "https://platform.example.com/.well-known/jwks.json",
      platform_token_url: "https://platform.example.com/token",
      signing_key: tool_jwk
    }

    %{registration: registration, custom_registration: custom_registration}
  end

  defp req_options, do: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]

  defp launch_context(registration, extensions) do
    %LaunchContext{claims: %LaunchClaims{extensions: extensions}, registration: registration}
  end

  defp stub_token_response(scope_string) do
    Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
      Req.Test.json(conn, %{
        "access_token" => "test-token",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => scope_string
      })
    end)
  end

  describe "authenticate/2" do
    test "acquires token with single-service endpoint", ctx do
      stub_token_response(@test_scope)

      assert {:ok, %Client{} = client} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
               )

      assert client.access_token == "test-token"
      assert MapSet.member?(client.scopes, @test_scope)
      assert client.endpoints == %{TestService => :valid_endpoint}
      assert client.registration == ctx.registration
    end

    test "configured token response helper grants only its configured scopes", ctx do
      Ltix.Test.stub_token_response(scopes: [@other_scope], access_token: "configured-token")

      assert {:ok, %Client{access_token: "configured-token"} = client} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{
                   TestService => :valid_endpoint,
                   OtherService => :other_endpoint
                 },
                 req_options: req_options()
               )

      assert client.scopes == MapSet.new([@other_scope])
    end

    test "multiple endpoints send space-separated scopes", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)
        scope_parts = String.split(params["scope"])

        assert @test_scope in scope_parts
        assert @other_scope in scope_parts

        Req.Test.json(conn, %{
          "access_token" => "multi-token",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "#{@test_scope} #{@other_scope}"
        })
      end)

      assert {:ok, %Client{} = client} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{
                   TestService => :valid_endpoint,
                   OtherService => :other_endpoint
                 },
                 req_options: req_options()
               )

      assert MapSet.member?(client.scopes, @test_scope)
      assert MapSet.member?(client.scopes, @other_scope)
    end

    test "granted scopes reflect platform response, not requested", ctx do
      # Platform grants only a subset
      stub_token_response(@test_scope)

      assert {:ok, %Client{} = client} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{
                   TestService => :valid_endpoint,
                   OtherService => :other_endpoint
                 },
                 req_options: req_options()
               )

      assert MapSet.member?(client.scopes, @test_scope)
      refute MapSet.member?(client.scopes, @other_scope)
    end

    test "require_all_scopes returns ScopeMismatch when the platform grants only some", ctx do
      stub_token_response(@test_scope)

      assert {:error, %ScopeMismatch{scopes: [@other_scope]}} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint, OtherService => :other_endpoint},
                 req_options: req_options(),
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

      assert {:ok, %Client{access_token: "extension-token"} = client} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
               )

      after_request = DateTime.utc_now()
      assert client.scopes == MapSet.new([@test_scope])
      assert DateTime.compare(client.expires_at, DateTime.add(before_request, 3600)) != :lt
      assert DateTime.compare(client.expires_at, DateTime.add(after_request, 3600)) != :gt
    end

    test "accepts a compliant response and honors zero lifetime", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        Req.Test.json(conn, %{
          "access_token" => "expired-token",
          "token_type" => "BEARER",
          "expires_in" => 0,
          "scope" => @test_scope
        })
      end)

      before_request = System.system_time(:microsecond)

      assert {:ok, %Client{access_token: "expired-token"} = client} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
               )

      after_request = System.system_time(:microsecond)
      expires_at = DateTime.to_unix(client.expires_at, :microsecond)
      assert expires_at >= before_request
      assert expires_at <= after_request
      assert Client.expired?(client)
      assert client.scopes == MapSet.new([@test_scope])
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
              "scope" => @test_scope
            },
            unquote(field),
            unquote(Macro.escape(value))
          )

        Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
          Req.Test.json(conn, body)
        end)

        assert {:error, %MalformedResponse{service: :oauth}} =
                 OAuth.authenticate(ctx.registration,
                   endpoints: %{TestService => :valid_endpoint},
                   req_options: req_options()
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
                 OAuth.authenticate(ctx.registration,
                   endpoints: %{TestService => :valid_endpoint},
                   req_options: req_options()
                 )
      end
    end

    test "returns MalformedResponse for JSON body []", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        Req.Test.json(conn, [])
      end)

      assert {:error, %MalformedResponse{service: :oauth}} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
               )
    end

    test "returns MalformedResponse for invalid JSON", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, "{not-json}")
      end)

      assert {:error, %MalformedResponse{service: :oauth}} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
               )
    end

    test "preserves HTTP 400 and body when the advertised JSON is invalid", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, "{not-json}")
      end)

      assert {:error, %TokenRequestFailed{status: 400, body: "{not-json}"}} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
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

      assert {:ok, %Client{access_token: "aZ09-._~+/=="} = client} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
               )

      assert client.scopes == MapSet.new(["!#[scope]~", "other.scope"])
    end

    test "accepts JSON media type parameters and whitespace", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json ; charset=utf-8")
        |> Plug.Conn.send_resp(200, ~s({"access_token":"media-type-token","token_type":"Bearer"}))
      end)

      assert {:ok, %Client{access_token: "media-type-token"}} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
               )
    end

    test "invalid endpoint returns error before any HTTP call", ctx do
      assert {:error, %InvalidEndpoint{}} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :wrong_endpoint},
                 req_options: req_options()
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
                 OAuth.authenticate(ctx.registration,
                   endpoints: %{TestService => :valid_endpoint},
                   req_options: req_options()
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
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
               )
    end

    test "preserves a non-JSON error response", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        Plug.Conn.send_resp(conn, 502, "Bad Gateway")
      end)

      assert {:error, %TokenRequestFailed{status: 502, body: "Bad Gateway"}} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
               )
    end

    test "rejects a non-JSON HTTP 200 response", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        Plug.Conn.send_resp(conn, 200, "<html>Not a token</html>")
      end)

      assert {:error, %MalformedResponse{service: :oauth}} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
               )
    end

    test "token request failure propagated", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"error" => "invalid_grant"})
      end)

      assert {:error, %TokenRequestFailed{}} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
               )
    end

    test "network failure returns TransportError", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, &Req.Test.transport_error(&1, :econnrefused))

      assert {:error, %TransportError{url: "https://platform.example.com/token"} = error} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options() ++ [retry: false]
               )

      assert Exception.message(error) =~ "connection refused"
    end

    test "req_options passed through to token request", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        # If we got here, the plug option was passed through correctly
        Req.Test.json(conn, %{
          "access_token" => "plug-test",
          "token_type" => "Bearer"
        })
      end)

      assert {:ok, %Client{access_token: "plug-test"}} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
               )
    end

    test "raises on missing, unknown, and invalid options", ctx do
      assert_raise InvalidOption, "Option :endpoints is required", fn ->
        OAuth.authenticate(ctx.registration, [])
      end

      assert_raise InvalidOption, "Option :endpoint is unknown", fn ->
        OAuth.authenticate(ctx.registration,
          endpoints: %{TestService => :valid_endpoint},
          endpoint: :valid_endpoint
        )
      end

      assert_raise InvalidOption, ~r/Option :endpoints is invalid/, fn ->
        OAuth.authenticate(ctx.registration, endpoints: [TestService])
      end
    end

    test "accepts a custom Registerable struct", ctx do
      stub_token_response(@test_scope)

      assert {:ok, %Client{} = client} =
               OAuth.authenticate(ctx.custom_registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
               )

      assert %Ltix.Registration{} = client.registration
      assert client.registration.issuer == "https://platform.example.com"
      assert client.registration.client_id == "tool-client-id"
    end
  end

  describe "authenticate/2 from a launch context" do
    test "requests the scopes of each service's endpoint from the launch", ctx do
      stub_token_response("#{@test_scope} #{@other_scope}")
      context = launch_context(ctx.registration, @launch_extensions)

      assert {:ok, %Client{} = client} =
               OAuth.authenticate(context,
                 services: [TestService, OtherService],
                 req_options: req_options()
               )

      assert client.endpoints == %{
               TestService => :valid_endpoint,
               OtherService => :other_endpoint
             }

      assert client.scopes == MapSet.new([@test_scope, @other_scope])
      assert client.registration == ctx.registration
    end

    test "returns ServiceNotAvailable for each service missing from the launch", ctx do
      context = launch_context(ctx.registration, %{})

      assert {:error, %ServiceNotAvailable{service: TestService}} =
               OAuth.authenticate(context, services: [TestService])

      assert {:error,
              %Invalid{
                errors: [
                  %ServiceNotAvailable{service: TestService},
                  %ServiceNotAvailable{service: OtherService}
                ]
              }} =
               OAuth.authenticate(context, services: [TestService, OtherService])
    end

    test "require_all_scopes returns ScopeMismatch when the platform grants only some", ctx do
      stub_token_response(@test_scope)
      context = launch_context(ctx.registration, @launch_extensions)

      assert {:error, %ScopeMismatch{scopes: [@other_scope]}} =
               OAuth.authenticate(context,
                 services: [TestService, OtherService],
                 req_options: req_options(),
                 require_all_scopes: true
               )
    end

    test "raises on missing, unknown, and invalid options", ctx do
      context = launch_context(ctx.registration, @launch_extensions)

      assert_raise InvalidOption, "Option :services is required", fn ->
        OAuth.authenticate(context)
      end

      assert_raise InvalidOption, "Option :endpoints is unknown", fn ->
        OAuth.authenticate(context, services: [TestService], endpoints: %{})
      end

      assert_raise InvalidOption, ~r/Option :services is invalid/, fn ->
        OAuth.authenticate(context, services: TestService)
      end
    end
  end

  describe "authenticate!/2" do
    test "returns unwrapped client on success", ctx do
      stub_token_response(@test_scope)

      assert %Client{} =
               OAuth.authenticate!(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
               )
    end

    test "raises on error", ctx do
      assert_raise InvalidEndpoint, fn ->
        OAuth.authenticate!(ctx.registration,
          endpoints: %{TestService => :wrong_endpoint},
          req_options: req_options()
        )
      end
    end
  end
end
