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
  alias Ltix.Launch
  alias Ltix.OAuth
  alias Ltix.OAuth.Client

  @test_scope "https://example.com/scope/test.readonly"
  @other_scope "https://example.com/scope/other.write"

  defmodule TestService do
    @behaviour Ltix.AdvantageService

    @impl Ltix.AdvantageService
    def validate_endpoint(:valid_endpoint), do: :ok

    def validate_endpoint(_),
      do: {:error, InvalidEndpoint.exception(service: __MODULE__)}

    @impl Ltix.AdvantageService
    def scopes(:valid_endpoint),
      do: ["https://example.com/scope/test.readonly"]
  end

  defmodule OtherService do
    @behaviour Ltix.AdvantageService

    @impl Ltix.AdvantageService
    def validate_endpoint(:other_endpoint), do: :ok

    def validate_endpoint(_),
      do: {:error, InvalidEndpoint.exception(service: __MODULE__)}

    @impl Ltix.AdvantageService
    def scopes(:other_endpoint),
      do: ["https://example.com/scope/other.write"]
  end

  @launch_endpoints %{TestService => :valid_endpoint, OtherService => :other_endpoint}

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

  defp launch_with_endpoints(registration, endpoints) do
    %Launch{endpoints: endpoints, registration: registration, source_registration: registration}
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
    test "raises ArgumentError for a registration that doesn't convert", ctx do
      assert_raise ArgumentError, ~r/Ltix.Registerable/, fn ->
        OAuth.authenticate(%BareRegistration{registration: ctx.registration},
          endpoints: %{TestService => :valid_endpoint},
          req_options: req_options()
        )
      end
    end

    test "acquires token with single-service endpoint", ctx do
      stub_token_response(@test_scope)

      assert {:ok, %Client{} = client} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
               )

      assert client.token.access_token == "test-token"
      assert MapSet.member?(client.token.granted_scopes, @test_scope)
      assert client.endpoints == %{TestService => :valid_endpoint}
      assert client.registration == ctx.registration
    end

    test "configured token response helper grants only its configured scopes", ctx do
      Ltix.Test.stub_token_response(scopes: [@other_scope], access_token: "configured-token")

      assert {:ok, %Client{token: %{access_token: "configured-token"}} = client} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{
                   TestService => :valid_endpoint,
                   OtherService => :other_endpoint
                 },
                 req_options: req_options()
               )

      assert client.token.granted_scopes == MapSet.new([@other_scope])
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

      assert MapSet.member?(client.token.granted_scopes, @test_scope)
      assert MapSet.member?(client.token.granted_scopes, @other_scope)
    end

    test "granted scopes are the scopes in the platform response", ctx do
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

      assert MapSet.member?(client.token.granted_scopes, @test_scope)
      refute MapSet.member?(client.token.granted_scopes, @other_scope)
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

      assert {:ok, %Client{token: %{access_token: "extension-token"}} = client} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
               )

      after_request = DateTime.utc_now()
      assert client.token.granted_scopes == MapSet.new([@test_scope])
      assert DateTime.compare(client.token.expires_at, DateTime.add(before_request, 3600)) != :lt
      assert DateTime.compare(client.token.expires_at, DateTime.add(after_request, 3600)) != :gt
    end

    test "accepts a compliant response and applies a zero lifetime", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        Req.Test.json(conn, %{
          "access_token" => "expired-token",
          "token_type" => "BEARER",
          "expires_in" => 0,
          "scope" => @test_scope
        })
      end)

      before_request = System.system_time(:microsecond)

      assert {:ok, %Client{token: %{access_token: "expired-token"}} = client} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
               )

      after_request = System.system_time(:microsecond)
      expires_at = DateTime.to_unix(client.token.expires_at, :microsecond)
      assert expires_at >= before_request
      assert expires_at <= after_request
      assert Client.expired?(client)
      assert client.token.granted_scopes == MapSet.new([@test_scope])
    end

    test "a token with a lifetime under a minute is usable for half its lifetime", ctx do
      Ltix.Test.stub_token_response(expires_in: 30)

      assert {:ok, client} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
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

      assert {:ok, %Client{token: %{access_token: "aZ09-._~+/=="}} = client} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
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
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
               )
    end

    test "invalid endpoint returns error before any HTTP call", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn _conn -> flunk("token request was sent") end)

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

    test "network failure returns TransportError", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, &Req.Test.transport_error(&1, :econnrefused))

      assert {:error, %TransportError{url: "https://platform.example.com/token", status: nil}} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options() ++ [retry: false]
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
  end

  describe "authenticate/2 from a launch" do
    test "requests the scopes of each service's endpoint from the launch", ctx do
      stub_token_response("#{@test_scope} #{@other_scope}")
      launch = launch_with_endpoints(ctx.registration, @launch_endpoints)

      assert {:ok, %Client{} = client} =
               OAuth.authenticate(launch,
                 services: [TestService, OtherService],
                 req_options: req_options()
               )

      assert client.endpoints == %{
               TestService => :valid_endpoint,
               OtherService => :other_endpoint
             }

      assert client.token.granted_scopes == MapSet.new([@test_scope, @other_scope])
      assert client.registration == ctx.registration
    end

    test "returns ServiceNotAvailable for each service missing from the launch", ctx do
      launch = launch_with_endpoints(ctx.registration, %{})

      assert {:error, %ServiceNotAvailable{service: TestService} = error} =
               OAuth.authenticate(launch, services: [TestService])

      assert Exception.message(error) =~ "The launch has no endpoint claim for this service"

      assert {:error,
              %Invalid{
                errors: [
                  %ServiceNotAvailable{service: TestService},
                  %ServiceNotAvailable{service: OtherService}
                ]
              }} =
               OAuth.authenticate(launch, services: [TestService, OtherService])
    end

    test "require_all_scopes returns ScopeMismatch when the platform grants only some", ctx do
      stub_token_response(@test_scope)
      launch = launch_with_endpoints(ctx.registration, @launch_endpoints)

      assert {:error, %ScopeMismatch{scopes: [@other_scope]}} =
               OAuth.authenticate(launch,
                 services: [TestService, OtherService],
                 req_options: req_options(),
                 require_all_scopes: true
               )
    end

    test "raises on missing, unknown, and invalid options", ctx do
      launch = launch_with_endpoints(ctx.registration, @launch_endpoints)

      assert_raise InvalidOption, "Option :services is required", fn ->
        OAuth.authenticate(launch)
      end

      assert_raise InvalidOption, "Option :endpoints is unknown", fn ->
        OAuth.authenticate(launch, services: [TestService], endpoints: %{})
      end

      assert_raise InvalidOption, ~r/Option :services is invalid/, fn ->
        OAuth.authenticate(launch, services: TestService)
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
