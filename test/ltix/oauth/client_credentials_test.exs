defmodule Ltix.OAuth.ClientCredentialsTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.OAuth.AccessToken
  alias Ltix.OAuth.ClientCredentials
  alias Ltix.Test.StorageAdapter

  @scopes ["https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"]

  setup do
    tool_jwk = StorageAdapter.tool_jwk()

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
        token_endpoint: "https://platform.example.com/token"
      })

    %{registration: registration, public_jwk: public_jwk}
  end

  defp req_options, do: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}, retry: false]

  describe "request_token/3" do
    test "JWT assertion contains all MUST claims", ctx do
      public_jwk = ctx.public_jwk
      registration = ctx.registration

      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
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

    test "POST body contains correct form params", ctx do
      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
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

    test "jti is unique across calls", ctx do
      jtis = :ets.new(:jtis, [:set, :public])

      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
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

    test "nil token_endpoint returns ServiceNotAvailable" do
      {:ok, registration} =
        Ltix.Registration.new(%{
          issuer: "https://platform.example.com",
          client_id: "tool-client-id",
          auth_endpoint: "https://platform.example.com/auth",
          jwks_uri: "https://platform.example.com/.well-known/jwks.json"
        })

      assert {:error, %ServiceNotAvailable{} = error} =
               ClientCredentials.request_token(registration, @scopes)

      assert Exception.message(error) =~ "The registration has no token endpoint"
    end
  end
end
