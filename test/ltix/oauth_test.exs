defmodule Ltix.OAuthTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.InvalidEndpoint
  alias Ltix.Errors.Invalid.TokenRequestFailed
  alias Ltix.OAuth
  alias Ltix.OAuth.Client

  @test_scope "https://example.com/scope/test.readonly"
  @other_scope "https://example.com/scope/other.write"

  defmodule TestService do
    @behaviour Ltix.AdvantageService

    @impl Ltix.AdvantageService
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

  defp req_options, do: [plug: {Req.Test, __MODULE__}]

  defp stub_token_response(scope_string) do
    Req.Test.stub(__MODULE__, fn conn ->
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

    test "multiple endpoints send space-separated scopes", ctx do
      Req.Test.stub(__MODULE__, fn conn ->
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

    test "invalid endpoint returns error before any HTTP call", ctx do
      assert {:error, %InvalidEndpoint{}} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :wrong_endpoint},
                 req_options: req_options()
               )
    end

    test "token request failure propagated", ctx do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(%{"error" => "invalid_grant"}))
      end)

      assert {:error, %TokenRequestFailed{}} =
               OAuth.authenticate(ctx.registration,
                 endpoints: %{TestService => :valid_endpoint},
                 req_options: req_options()
               )
    end

    test "req_options passed through to token request", ctx do
      Req.Test.stub(__MODULE__, fn conn ->
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

    test "rejects missing endpoints option", ctx do
      assert_raise Zoi.ParseError, fn ->
        OAuth.authenticate(ctx.registration, [])
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
