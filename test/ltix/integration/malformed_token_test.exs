defmodule Ltix.Integration.MalformedTokenTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.InvalidJSON
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.Errors.Security.AudienceMismatch
  alias Ltix.Errors.Security.KidMissing
  alias Ltix.Errors.Security.KidNotFound
  alias Ltix.Errors.Security.SignatureInvalid
  alias Ltix.JWT.Token
  alias Ltix.LaunchContext
  alias Ltix.Test.StorageAdapter

  setup do
    identifier = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    platform = Ltix.Test.setup_platform!(issuer: "https://platform.example.com/#{identifier}")

    pid =
      start_supervised!({StorageAdapter, platforms: [platform]})

    StorageAdapter.set_pid(pid)

    {:ok, login} =
      Ltix.handle_login(Ltix.Test.login_params(platform), "https://tool.example.com/launch",
        storage_adapter: StorageAdapter
      )

    claims =
      Ltix.Test.valid_lti_claims(platform, %{
        "nonce" => Ltix.Test.extract_nonce(login.redirect_uri)
      })

    query = URI.decode_query(URI.parse(login.redirect_uri).query)

    %{
      platform: platform,
      login: login,
      request_state: Map.fetch!(query, "state"),
      claims: claims
    }
  end

  test "callback rejects nonstring key identifier", context do
    token =
      sign(context.claims, %{"alg" => "RS256", "kid" => 123}, context)

    assert {:error, %SignatureInvalid{class: :security}} = callback(token, context)
  end

  test "callback retains null key identifier errors", context do
    token = sign(context.claims, %{"alg" => "RS256", "kid" => nil}, context)
    assert {:error, %KidMissing{class: :security}} = callback(token, context)
  end

  test "callback matches string key identifiers case sensitively", context do
    jwks = Ltix.JWK.to_jwks(%{context.platform.jwk | kid: "CaseSensitiveKey"})
    Req.Test.stub(Ltix.JWT.KeySet, fn connection -> Req.Test.json(connection, jwks) end)

    token = sign(context.claims, %{"alg" => "RS256", "kid" => "casesensitivekey"}, context)
    assert {:error, %KidNotFound{kid: "casesensitivekey"}} = callback(token, context)

    token = sign(context.claims, %{"alg" => "RS256", "kid" => "CaseSensitiveKey"}, context)
    assert {:ok, %LaunchContext{}} = callback(token, context)
  end

  test "callback rejects malformed signature", context do
    [protected, payload, _signature] =
      String.split(sign(context.claims, header(context), context), ".")

    token = Enum.join([protected, payload, "!"], ".")
    assert {:error, %SignatureInvalid{class: :security}} = callback(token, context)
  end

  # Not base64url and `[]`.
  for malformed_header <- ["!", "W10"] do
    test "verifier and callback reject a header that is not a JSON object #{malformed_header}",
         context do
      [_protected, payload, signature] =
        String.split(sign(context.claims, header(context), context), ".")

      token = Enum.join([unquote(malformed_header), payload, signature], ".")

      assert {:error, %InvalidJSON{class: :invalid}} =
               Token.verify(token, context.platform.registration, verifier_options())

      assert {:error, %InvalidJSON{class: :invalid}} = callback(token, context)
    end
  end

  # `{}` and `{"alg":123}`.
  for header_without_algorithm <- ["e30", "eyJhbGciOjEyM30"] do
    test "callback rejects a header without a string algorithm #{header_without_algorithm}",
         context do
      [_protected, payload, signature] =
        String.split(sign(context.claims, header(context), context), ".")

      token = Enum.join([unquote(header_without_algorithm), payload, signature], ".")
      assert {:error, %SignatureInvalid{class: :security}} = callback(token, context)
    end
  end

  for payload <- ["not-json", "[]"] do
    test "public verifier rejects signed nonobject claims #{payload}", context do
      token = sign_payload(unquote(payload), header(context), context)

      assert {:error, %InvalidJSON{class: :invalid}} =
               Token.verify(token, context.platform.registration, verifier_options())

      assert {:error, %InvalidJSON{class: :invalid}} = callback(token, context)
    end
  end

  test "public verifier rejects a signed token without an issuer", context do
    claims = Map.delete(context.claims, "iss")
    token = sign(claims, header(context), context)

    assert {:error, %MissingClaim{claim: "iss", class: :invalid}} =
             Token.verify(token, context.platform.registration, verifier_options())
  end

  test "callback looks up the registration by issuer alone when the first audience is not a string",
       context do
    token = sign(Map.put(context.claims, "aud", [123]), header(context), context)

    assert {:error, %AudienceMismatch{claim: "aud", actual: [123]}} =
             callback(token, context)
  end

  test "callback rejects a token without an issuer before looking up its registration",
       context do
    token = sign(Map.delete(context.claims, "iss"), header(context), context)
    assert {:error, %MissingClaim{claim: "iss", class: :invalid}} = callback(token, context)
  end

  test "callback rejects nonstring issuer", context do
    issuer = 123
    token = sign(Map.put(context.claims, "iss", issuer), header(context), context)

    assert {:error, %InvalidClaim{claim: "iss", value: ^issuer, class: :invalid}} =
             callback(token, context)
  end

  test "callback rejects a signed token without an issue time", context do
    token = sign(Map.delete(context.claims, "iat"), header(context), context)
    assert {:error, %MissingClaim{claim: "iat", class: :invalid}} = callback(token, context)
  end

  test "callback rejects an unsupported critical extension", context do
    protected =
      context
      |> header()
      |> Map.merge(%{
        "crit" => ["https://platform.example.com/extension"],
        "https://platform.example.com/extension" => true
      })

    token = sign(context.claims, protected, context)
    assert {:error, %SignatureInvalid{class: :security}} = callback(token, context)
  end

  test "callback permits an unknown noncritical header", context do
    protected = Map.put(header(context), "https://platform.example.com/extension", true)
    token = sign(context.claims, protected, context)
    assert {:ok, %LaunchContext{claims: %{subject: "user-12345"}}} = callback(token, context)
  end

  defp header(context), do: %{"alg" => "RS256", "kid" => context.platform.jwk.kid}

  defp sign(claims, protected, context) do
    sign_payload(Ltix.AppConfig.json_library!().encode!(claims), protected, context)
  end

  defp sign_payload(payload, protected, context) do
    signed =
      JOSE.JWS.sign(JOSE.JWK.from_pem(context.platform.jwk.private_key_pem), payload, protected)

    {_metadata, token} = JOSE.JWS.compact(signed)
    token
  end

  defp callback(token, context) do
    params = %{"id_token" => token, "state" => context.request_state}
    opts = [storage_adapter: StorageAdapter] ++ verifier_options()
    Ltix.handle_callback(params, context.login.state, opts)
  end

  defp verifier_options, do: [req_options: [plug: {Req.Test, Ltix.JWT.KeySet}]]
end
