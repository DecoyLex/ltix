defmodule Ltix.JWT.TokenTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Security.AlgorithmNotAllowed
  alias Ltix.Errors.Security.AudienceMismatch
  alias Ltix.Errors.Security.IssuerMismatch
  alias Ltix.Errors.Security.NonceMissing

  alias Ltix.JWT.Token

  setup do
    platform_jwk = Ltix.JWK.generate()
    jwks = Ltix.JWK.to_jwks(platform_jwk)

    unique_id = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)

    {:ok, registration} =
      Ltix.Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri: "https://platform.example.com/.well-known/jwks-#{unique_id}.json"
      })

    stub_jwks(jwks)

    %{
      platform: %Ltix.Test.Platform{
        registration: registration,
        deployment: Ltix.Deployment.new!("deployment-001"),
        jwk: platform_jwk
      },
      registration: registration,
      platform_jwk: platform_jwk,
      jwks: jwks
    }
  end

  describe "verify/3" do
    test "raises on unknown and invalid options", ctx do
      token = mint_valid_token(ctx)

      assert_raise ArgumentError, "Option :skew is unknown", fn ->
        Token.verify(token, ctx.registration, skew: 10)
      end

      assert_raise ArgumentError, ~r/Option :now is invalid/, fn ->
        Token.verify(token, ctx.registration, now: DateTime.utc_now())
      end
    end

    # Algorithm validation [Sec §5.1.3 step 6, Cert §4.2]

    # [Sec §5.4](https://www.imsglobal.org/spec/security/v1p0/#message-signing)
    test "rejects alg=none", ctx do
      token = forge_token_with_alg("none", ctx)

      assert {:error, %AlgorithmNotAllowed{algorithm: "none"}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # Claims validation [Sec §5.1.3 steps 2-9]

    # [Sec §5.1.3 step 2](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
    test "rejects iss mismatch", ctx do
      claims =
        Ltix.Test.valid_lti_claims(ctx.platform, %{"iss" => "https://wrong-issuer.example.com"})

      token = Ltix.Test.sign_id_token(claims, ctx.platform_jwk)

      assert {:error, %IssuerMismatch{expected: "https://platform.example.com"}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # [Sec §5.1.3 step 3](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
    test "rejects aud mismatch as string", ctx do
      claims = Ltix.Test.valid_lti_claims(ctx.platform, %{"aud" => "wrong-client-id"})
      token = Ltix.Test.sign_id_token(claims, ctx.platform_jwk)

      assert {:error, %AudienceMismatch{claim: "aud", expected: "tool-client-id"}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # [Sec §5.1.3 step 5](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
    test "rejects wrong azp with single string aud", ctx do
      claims =
        Ltix.Test.valid_lti_claims(ctx.platform, %{
          "aud" => "tool-client-id",
          "azp" => "other-client"
        })

      token = Ltix.Test.sign_id_token(claims, ctx.platform_jwk)

      assert {:error, %AudienceMismatch{claim: "azp", actual: "other-client"}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # [Sec §5.1.3 step 3](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
    test "rejects aud array with untrusted additional audience", ctx do
      claims =
        Ltix.Test.valid_lti_claims(ctx.platform, %{
          "aud" => ["tool-client-id", "other-client"],
          "azp" => "tool-client-id"
        })

      token = Ltix.Test.sign_id_token(claims, ctx.platform_jwk)

      assert {:error, %AudienceMismatch{claim: "aud", actual: ["tool-client-id", "other-client"]}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    test "reports a missing or non-numeric expiry as a claim error", ctx do
      claims = Ltix.Test.valid_lti_claims(ctx.platform)

      verify =
        &Token.verify(Ltix.Test.sign_id_token(&1, ctx.platform_jwk), ctx.registration,
          req_options: req_options()
        )

      assert {:error, %Ltix.Errors.Invalid.MissingClaim{claim: "exp"}} =
               verify.(Map.delete(claims, "exp"))

      assert {:error, %Ltix.Errors.Invalid.InvalidClaim{claim: "exp", value: "tomorrow"}} =
               verify.(Map.put(claims, "exp", "tomorrow"))
    end

    # [Sec §5.1.3 step 7](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
    test "accepts token within clock skew tolerance", ctx do
      # Token expired 3 seconds ago, but default clock skew is 5 seconds
      claims =
        Ltix.Test.valid_lti_claims(ctx.platform, %{"exp" => System.system_time(:second) - 3})

      token = Ltix.Test.sign_id_token(claims, ctx.platform_jwk)

      assert {:ok, _claims} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # [Sec §5.1.3 step 9](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
    test "rejects missing nonce", ctx do
      claims = Map.delete(Ltix.Test.valid_lti_claims(ctx.platform), "nonce")

      token = Ltix.Test.sign_id_token(claims, ctx.platform_jwk)

      assert {:error, %NonceMissing{}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end
  end

  # Build a JWT with a specific alg in the header (without actually signing
  # with that algorithm). Used to test algorithm rejection before signature
  # verification.
  defp forge_token_with_alg(alg, ctx) do
    header =
      %{"alg" => alg, "kid" => ctx.platform_jwk.kid}
      |> Jason.encode!()
      |> Base.url_encode64(padding: false)

    payload =
      Ltix.Test.valid_lti_claims(ctx.platform)
      |> Jason.encode!()
      |> Base.url_encode64(padding: false)

    signature = Base.url_encode64("fake-signature", padding: false)
    "#{header}.#{payload}.#{signature}"
  end

  defp mint_valid_token(ctx) do
    claims = Ltix.Test.valid_lti_claims(ctx.platform)
    Ltix.Test.sign_id_token(claims, ctx.platform_jwk)
  end

  defp stub_jwks(jwks) do
    Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("cache-control", "max-age=300")
      |> Req.Test.json(jwks)
    end)
  end

  defp req_options do
    [plug: {Req.Test, Ltix.JWT.KeySet}]
  end
end
