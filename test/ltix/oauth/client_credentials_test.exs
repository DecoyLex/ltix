defmodule Ltix.OAuth.ClientCredentialsTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.Errors.Invalid.TokenRequestFailed
  alias Ltix.OAuth.AccessToken
  alias Ltix.OAuth.ClientCredentials

  @scopes ["https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"]

  setup do
    tool_jwk = Ltix.JWK.generate()

    public_jwk =
      tool_jwk
      |> Ltix.JWK.to_jose()
      |> JOSE.JWK.to_public()

    {:ok, registration} =
      Ltix.Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri: "https://platform.example.com/.well-known/jwks.json",
        token_endpoint: "https://platform.example.com/token",
        tool_jwk: tool_jwk
      })

    %{registration: registration, tool_jwk: tool_jwk, public_jwk: public_jwk}
  end

  defp req_options, do: [plug: {Req.Test, __MODULE__}, retry: false]

  defp stub_token_response(body, status \\ 200) do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(body))
    end)
  end

  describe "request_token/3" do
    test "returns AccessToken on successful response", ctx do
      stub_token_response(%{
        "access_token" => "test-token",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => Enum.join(@scopes, " ")
      })

      assert {:ok, %AccessToken{} = token} =
               ClientCredentials.request_token(ctx.registration, @scopes,
                 req_options: req_options()
               )

      assert token.access_token == "test-token"
      assert token.token_type == "bearer"
      assert token.granted_scopes == @scopes
    end

    test "JWT assertion contains all MUST claims", ctx do
      public_jwk = ctx.public_jwk
      registration = ctx.registration

      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)

        # Verify the assertion is a valid JWT signed with the tool key
        {true, %JOSE.JWT{fields: claims}, _jws} =
          JOSE.JWT.verify(public_jwk, params["client_assertion"])

        # All 6 MUST claims present
        assert claims["iss"] == registration.client_id
        assert claims["sub"] == registration.client_id
        assert claims["aud"] == registration.token_endpoint
        assert is_integer(claims["iat"])
        assert is_integer(claims["exp"])
        assert is_binary(claims["jti"])

        # exp is ~5 minutes from iat
        assert claims["exp"] - claims["iat"] == 300

        Req.Test.json(conn, %{
          "access_token" => "verified-token",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => Enum.join(@scopes, " ")
        })
      end)

      assert {:ok, %AccessToken{access_token: "verified-token"}} =
               ClientCredentials.request_token(ctx.registration, @scopes,
                 req_options: req_options()
               )
    end

    test "JWT header includes typ, alg, and kid", ctx do
      public_jwk = ctx.public_jwk

      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)

        # Decode header without verification to inspect it
        [header_b64 | _] = String.split(params["client_assertion"], ".")

        header =
          header_b64
          |> Base.url_decode64!(padding: false)
          |> Ltix.AppConfig.json_library!().decode!()

        assert header["typ"] == "JWT"
        assert header["alg"] == "RS256"
        assert header["kid"] == ctx.tool_jwk.kid

        # Still verify the signature
        {true, _jwt, _jws} = JOSE.JWT.verify(public_jwk, params["client_assertion"])

        Req.Test.json(conn, %{
          "access_token" => "header-test",
          "token_type" => "Bearer"
        })
      end)

      assert {:ok, _token} =
               ClientCredentials.request_token(ctx.registration, @scopes,
                 req_options: req_options()
               )
    end

    test "POST body contains correct form params", ctx do
      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)

        assert params["grant_type"] == "client_credentials"

        assert params["client_assertion_type"] ==
                 "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

        assert is_binary(params["client_assertion"])
        assert params["scope"] == Enum.join(@scopes, " ")

        [content_type] = Plug.Conn.get_req_header(conn, "content-type")
        assert content_type =~ "application/x-www-form-urlencoded"

        Req.Test.json(conn, %{
          "access_token" => "form-test",
          "token_type" => "Bearer"
        })
      end)

      assert {:ok, _token} =
               ClientCredentials.request_token(ctx.registration, @scopes,
                 req_options: req_options()
               )
    end

    test "multiple scopes are space-separated", ctx do
      scopes = ["scope:read", "scope:write", "scope:admin"]

      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)

        assert params["scope"] == "scope:read scope:write scope:admin"

        Req.Test.json(conn, %{
          "access_token" => "multi-scope",
          "token_type" => "Bearer",
          "scope" => "scope:read scope:write"
        })
      end)

      assert {:ok, token} =
               ClientCredentials.request_token(ctx.registration, scopes,
                 req_options: req_options()
               )

      assert token.granted_scopes == ["scope:read", "scope:write"]
    end

    test "jti is unique across calls", ctx do
      jtis = :ets.new(:jtis, [:set, :public])

      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)

        {true, %JOSE.JWT{fields: claims}, _jws} =
          JOSE.JWT.verify(ctx.public_jwk, params["client_assertion"])

        :ets.insert(jtis, {claims["jti"]})

        Req.Test.json(conn, %{
          "access_token" => "jti-test",
          "token_type" => "Bearer"
        })
      end)

      for _ <- 1..3 do
        ClientCredentials.request_token(ctx.registration, @scopes, req_options: req_options())
      end

      # All 3 JTIs should be unique
      assert :ets.info(jtis, :size) == 3
    end

    test "RFC 6749 error response parsed into TokenRequestFailed", ctx do
      stub_token_response(
        %{
          "error" => "invalid_scope",
          "error_description" => "The requested scope is invalid"
        },
        400
      )

      assert {:error, %TokenRequestFailed{} = error} =
               ClientCredentials.request_token(ctx.registration, @scopes,
                 req_options: req_options()
               )

      assert error.error == "invalid_scope"
      assert error.error_description == "The requested scope is invalid"
    end

    test "non-JSON error response preserves status and body", ctx do
      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 502, "Bad Gateway")
      end)

      assert {:error, %TokenRequestFailed{} = error} =
               ClientCredentials.request_token(ctx.registration, @scopes,
                 req_options: req_options()
               )

      assert error.status == 502
      assert error.body == "Bad Gateway"
    end

    test "nil token_endpoint returns ServiceNotAvailable" do
      tool_jwk = Ltix.JWK.generate()

      {:ok, registration} =
        Ltix.Registration.new(%{
          issuer: "https://platform.example.com",
          client_id: "tool-client-id",
          auth_endpoint: "https://platform.example.com/auth",
          jwks_uri: "https://platform.example.com/.well-known/jwks.json",
          tool_jwk: tool_jwk
        })

      assert {:error, %ServiceNotAvailable{}} =
               ClientCredentials.request_token(registration, @scopes)
    end

    test "falls back to requested scopes when response omits scope", ctx do
      stub_token_response(%{
        "access_token" => "no-scope-token",
        "token_type" => "Bearer",
        "expires_in" => 3600
      })

      assert {:ok, token} =
               ClientCredentials.request_token(ctx.registration, @scopes,
                 req_options: req_options()
               )

      assert token.granted_scopes == @scopes
    end
  end
end
