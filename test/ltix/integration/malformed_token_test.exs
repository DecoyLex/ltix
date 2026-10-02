defmodule Ltix.Integration.MalformedTokenTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.MissingParameter
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
      start_supervised!(
        {StorageAdapter,
         registrations: [platform.registration], deployments: [platform.deployment]}
      )

    StorageAdapter.set_pid(pid)

    {:ok, login} =
      Ltix.handle_login(Ltix.Test.login_params(platform), "https://tool.example.com/launch",
        storage_adapter: StorageAdapter
      )

    claims =
      Ltix.Test.valid_lti_claims(%{
        "iss" => platform.registration.issuer,
        "nonce" => Ltix.Test.extract_nonce(login.redirect_uri)
      })

    %{platform: platform, login: login, claims: claims}
  end

  for kid <- [123, 1.5, true, false, [], ["key"], %{"key" => "value"}] do
    test "callback rejects nonstring key identifier #{inspect(kid)}", context do
      token =
        sign(context.claims, %{"alg" => "RS256", "kid" => unquote(Macro.escape(kid))}, context)

      assert {:error, %SignatureInvalid{class: :security}} = callback(token, context)
    end
  end

  test "callback retains null key identifier errors", context do
    token = sign(context.claims, %{"alg" => "RS256", "kid" => nil}, context)
    assert {:error, %KidMissing{class: :security}} = callback(token, context)
  end

  test "callback matches string key identifiers case sensitively", context do
    public_key = JOSE.JWK.merge(context.platform.public_key, %{"kid" => "CaseSensitiveKey"})
    jwks = Ltix.Test.build_jwks([public_key])
    Req.Test.stub(Ltix.JWT.KeySet, fn connection -> Req.Test.json(connection, jwks) end)

    token = sign(context.claims, %{"alg" => "RS256", "kid" => "casesensitivekey"}, context)
    assert {:error, %KidNotFound{kid: "casesensitivekey"}} = callback(token, context)

    token = sign(context.claims, %{"alg" => "RS256", "kid" => "CaseSensitiveKey"}, context)
    assert {:ok, %LaunchContext{}} = callback(token, context)
  end

  for signature <- ["!", "a", ""] do
    test "callback rejects malformed signature #{inspect(signature)}", context do
      [protected, payload, _signature] =
        String.split(sign(context.claims, header(context), context), ".")

      token = Enum.join([protected, payload, unquote(signature)], ".")
      assert {:error, %SignatureInvalid{class: :security}} = callback(token, context)
    end
  end

  for malformed_header <- ["!", "e30", "W10", "bnVsbA", "eyJhbGciOjEyM30"] do
    test "callback rejects malformed header #{malformed_header}", context do
      [_protected, payload, signature] =
        String.split(sign(context.claims, header(context), context), ".")

      token = Enum.join([unquote(malformed_header), payload, signature], ".")
      assert {:error, %SignatureInvalid{class: :security}} = callback(token, context)
    end
  end

  for payload <- ["not-json", "[]", "null", "123", "\"claims\""] do
    test "public verifier rejects signed nonobject claims #{payload}", context do
      token = sign_payload(unquote(payload), header(context), context)

      assert {:error, %SignatureInvalid{class: :security}} =
               Token.verify(token, context.platform.registration, verifier_options())

      assert {:error, %MissingParameter{parameter: "id_token"}} = callback(token, context)
    end
  end

  defp header(context), do: %{"alg" => "RS256", "kid" => context.platform.kid}

  defp sign(claims, protected, context) do
    sign_payload(Ltix.AppConfig.json_library!().encode!(claims), protected, context)
  end

  defp sign_payload(payload, protected, context) do
    signed = JOSE.JWS.sign(context.platform.private_key, payload, protected)
    {_metadata, token} = JOSE.JWS.compact(signed)
    token
  end

  defp callback(token, context, opts \\ []) do
    params = %{"id_token" => token, "state" => context.login.state}
    opts = Keyword.merge([storage_adapter: StorageAdapter] ++ verifier_options(), opts)
    Ltix.handle_callback(params, context.login.state, opts)
  end

  defp verifier_options, do: [req_options: [plug: {Req.Test, Ltix.JWT.KeySet}]]
end
