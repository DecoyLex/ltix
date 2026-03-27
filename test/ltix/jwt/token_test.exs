defmodule Ltix.JWT.TokenTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Security.AlgorithmNotAllowed
  alias Ltix.Errors.Security.AudienceMismatch
  alias Ltix.Errors.Security.IssuerMismatch
  alias Ltix.Errors.Security.KidMissing
  alias Ltix.Errors.Security.KidNotFound
  alias Ltix.Errors.Security.NonceMissing
  alias Ltix.Errors.Security.SignatureInvalid
  alias Ltix.Errors.Security.TokenExpired

  alias Ltix.JWT.Token
  alias Ltix.Test.JWTHelper

  setup do
    {private, public, kid} = JWTHelper.generate_rsa_key_pair()
    jwks = JWTHelper.build_jwks([public])

    unique_id = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)

    {:ok, registration} =
      Ltix.Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri: "https://platform.example.com/.well-known/jwks-#{unique_id}.json",
        tool_jwk: Ltix.JWK.generate()
      })

    stub_jwks(jwks)

    %{
      registration: registration,
      private: private,
      public: public,
      kid: kid,
      jwks: jwks
    }
  end

  describe "verify/3" do
    # Happy path
    test "valid JWT passes all checks", ctx do
      token = mint_valid_token(ctx)

      assert {:ok, claims} = Token.verify(token, ctx.registration, req_options: req_options())
      assert claims["iss"] == "https://platform.example.com"
      assert claims["aud"] == "tool-client-id"
    end

    # [Sec §5.1.2](https://www.imsglobal.org/spec/security/v1p0/#id-token)
    test "valid JWT with aud as single string", ctx do
      claims = JWTHelper.valid_lti_claims(%{"aud" => "tool-client-id"})
      token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)

      assert {:ok, _claims} = Token.verify(token, ctx.registration, req_options: req_options())
    end

    # [Sec §5.1.2](https://www.imsglobal.org/spec/security/v1p0/#id-token)
    test "valid JWT with aud as single-element array", ctx do
      claims = JWTHelper.valid_lti_claims(%{"aud" => ["tool-client-id"]})
      token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)

      assert {:ok, _claims} = Token.verify(token, ctx.registration, req_options: req_options())
    end

    # Algorithm validation [Sec §5.1.3 step 6; Cert §4.2]

    # [Sec §5.4](https://www.imsglobal.org/spec/security/v1p0/#message-signing)
    test "rejects alg=none", ctx do
      token = forge_token_with_alg("none", ctx.kid)

      assert {:error, %AlgorithmNotAllowed{algorithm: "none"}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # [Cert §4.2] Symmetric cryptosystems forbidden
    test "rejects alg=HS256", ctx do
      token = forge_token_with_alg("HS256", ctx.kid)

      assert {:error, %AlgorithmNotAllowed{algorithm: "HS256"}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # [Sec §5.1.3 step 6](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
    test "rejects non-RS256 alg", ctx do
      token = forge_token_with_alg("RS384", ctx.kid)

      assert {:error, %AlgorithmNotAllowed{algorithm: "RS384"}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # kid validation [Cert §6.1.1]

    # [Cert §6.1.1] "No KID Sent in JWT header"
    test "rejects JWT with no kid in header", ctx do
      claims = JWTHelper.valid_lti_claims()
      token = JWTHelper.mint_id_token(claims, ctx.private)

      assert {:error, %KidMissing{}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # [Cert §6.1.1] "Incorrect KID in JWT header"
    test "rejects JWT with incorrect kid", ctx do
      claims = JWTHelper.valid_lti_claims()
      token = JWTHelper.mint_id_token(claims, ctx.private, kid: "wrong-kid")

      assert {:error, %KidNotFound{kid: "wrong-kid"}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # Signature validation [Sec §5.1.3 step 1]

    test "rejects tampered payload", ctx do
      token = mint_valid_token(ctx)

      # Tamper with the payload by modifying the middle segment
      [header, _payload, signature] = String.split(token, ".")
      tampered_payload = Base.url_encode64(~s({"iss":"tampered"}), padding: false)
      tampered_token = Enum.join([header, tampered_payload, signature], ".")

      assert {:error, %SignatureInvalid{}} =
               Token.verify(tampered_token, ctx.registration, req_options: req_options())
    end

    test "rejects JWT signed with wrong key", ctx do
      {wrong_private, _wrong_public, _wrong_kid} = JWTHelper.generate_rsa_key_pair()
      claims = JWTHelper.valid_lti_claims()
      # Sign with wrong key but use the correct kid
      token = JWTHelper.mint_id_token(claims, wrong_private, kid: ctx.kid)

      assert {:error, %SignatureInvalid{}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # Claims validation [Sec §5.1.3 steps 2-9]

    # [Sec §5.1.3 step 2](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
    test "rejects iss mismatch", ctx do
      claims = JWTHelper.valid_lti_claims(%{"iss" => "https://wrong-issuer.example.com"})
      token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)

      assert {:error, %IssuerMismatch{expected: "https://platform.example.com"}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # [Sec §5.1.3 step 3](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
    test "rejects aud mismatch as string", ctx do
      claims = JWTHelper.valid_lti_claims(%{"aud" => "wrong-client-id"})
      token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)

      assert {:error, %AudienceMismatch{expected: "tool-client-id"}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # [Sec §5.1.3 step 3](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
    test "rejects aud mismatch as array", ctx do
      claims = JWTHelper.valid_lti_claims(%{"aud" => ["wrong-1", "wrong-2"]})
      token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)

      assert {:error, %AudienceMismatch{expected: "tool-client-id"}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # [Sec §5.1.3 step 5](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
    test "rejects wrong azp with single string aud", ctx do
      claims =
        JWTHelper.valid_lti_claims(%{
          "aud" => "tool-client-id",
          "azp" => "other-client"
        })

      token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)

      assert {:error, %AudienceMismatch{}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # [Sec §5.1.3 step 3](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
    test "rejects aud array with untrusted additional audience", ctx do
      claims =
        JWTHelper.valid_lti_claims(%{
          "aud" => ["tool-client-id", "other-client"],
          "azp" => "tool-client-id"
        })

      token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)

      assert {:error, %AudienceMismatch{}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # [Sec §5.1.3 step 7](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
    test "rejects expired token", ctx do
      claims = JWTHelper.valid_lti_claims(%{"exp" => System.system_time(:second) - 60})
      token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)

      assert {:error, %TokenExpired{}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # [Sec §5.1.3 step 7](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
    test "accepts token within clock skew tolerance", ctx do
      # Token expired 3 seconds ago, but default clock skew is 5 seconds
      claims = JWTHelper.valid_lti_claims(%{"exp" => System.system_time(:second) - 3})
      token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)

      assert {:ok, _claims} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # [Sec §5.1.3 step 9](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
    test "rejects missing nonce", ctx do
      claims = Map.delete(JWTHelper.valid_lti_claims(), "nonce")

      token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)

      assert {:error, %NonceMissing{}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # Issuer spoofing — attacker sends a near-miss issuer hoping the tool
    # treats it as equivalent to the registered one.

    # [Sec §5.1.3 step 2](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
    test "rejects issuer with trailing slash", ctx do
      claims = JWTHelper.valid_lti_claims(%{"iss" => "https://platform.example.com/"})
      token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)

      assert {:error, %IssuerMismatch{}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # [Sec §5.1.3 step 2](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
    test "rejects issuer with different case", ctx do
      claims = JWTHelper.valid_lti_claims(%{"iss" => "https://PLATFORM.example.com"})
      token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)

      assert {:error, %IssuerMismatch{}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # [Sec §5.1.3 step 2](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
    test "rejects issuer with unicode homoglyph", ctx do
      # Cyrillic 'а' (U+0430) looks identical to Latin 'a'
      claims = JWTHelper.valid_lti_claims(%{"iss" => "https://plаtform.example.com"})
      token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)

      assert {:error, %IssuerMismatch{}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end

    # Audience confusion — attacker includes untrusted client_ids in aud array
    # without setting azp, hoping the tool accepts the token.
    # [Sec §5.1.3 step 3](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
    test "rejects aud array containing untrusted audiences without azp", ctx do
      claims =
        JWTHelper.valid_lti_claims(%{
          "aud" => ["tool-client-id", "evil-client"]
        })

      token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)

      assert {:error, %AudienceMismatch{}} =
               Token.verify(token, ctx.registration, req_options: req_options())
    end
  end

  # Build a JWT with a specific alg in the header (without actually signing
  # with that algorithm). Used to test algorithm rejection before signature
  # verification.
  defp forge_token_with_alg(alg, kid) do
    header =
      %{"alg" => alg, "kid" => kid}
      |> Jason.encode!()
      |> Base.url_encode64(padding: false)

    payload =
      JWTHelper.valid_lti_claims()
      |> Jason.encode!()
      |> Base.url_encode64(padding: false)

    signature = Base.url_encode64("fake-signature", padding: false)
    "#{header}.#{payload}.#{signature}"
  end

  defp mint_valid_token(ctx) do
    claims = JWTHelper.valid_lti_claims()
    JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)
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
