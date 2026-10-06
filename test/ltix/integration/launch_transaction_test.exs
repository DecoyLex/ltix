defmodule Ltix.Integration.LaunchTransactionTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Security
  alias Ltix.LaunchContext
  alias Ltix.Test.StorageAdapter

  @launch_url "https://tool.example.com/launch"

  setup do
    platform = Ltix.Test.setup_platform!()

    other_platform = %{
      platform
      | registration: %{platform.registration | client_id: "other-tool-client-id"}
    }

    {:ok, pid} =
      StorageAdapter.start_link(platforms: [platform, other_platform])

    StorageAdapter.set_pid(pid)
    %{platform: platform, other_platform: other_platform}
  end

  # [OIDC §3.2.2.11](https://openid.net/specs/openid-connect-core-1_0.html#ImplicitIDTValidation)
  describe "pending browser transactions" do
    test "rejects swapped tokens for the same registration without consuming either nonce", ctx do
      assert_transaction_binding(ctx.platform, ctx.platform)
    end

    test "rejects swapped tokens for different registrations without consuming either nonce",
         ctx do
      assert_transaction_binding(ctx.platform, ctx.other_platform)
    end

    # [RFC 9700 §2.1](https://www.rfc-editor.org/rfc/rfc9700.html#section-2.1)
    test "rejects a token from another registration that carries the login's nonce", ctx do
      {login, params} = begin_launch(ctx.platform, "original-user")

      other_registration_params =
        Ltix.Test.launch_params(ctx.other_platform,
          nonce: Ltix.Test.extract_nonce(login.redirect_uri),
          state: login.state
        )

      assert {:error, %Security.NonceNotFound{}} =
               callback(other_registration_params, login.state)

      assert {:ok, %LaunchContext{claims: %{subject: "original-user"}}} =
               callback(params, login.state)
    end

    test "verifies the signature before checking nonce binding without consuming valid nonces",
         ctx do
      {login, params} = begin_launch(ctx.platform, "original-user")
      other_jwk = Ltix.JWK.generate()

      claims = Ltix.Test.valid_lti_claims(ctx.platform, %{"nonce" => "unrelated-nonce"})

      invalid_token =
        Ltix.Test.sign_id_token(claims, other_jwk, kid: ctx.platform.jwk.kid)

      invalid_params = Map.put(params, "id_token", invalid_token)

      assert {:error, %Security.SignatureInvalid{}} = callback(invalid_params, login.state)
      assert {:ok, %LaunchContext{}} = callback(params, login.state)
    end

    test "rejects a nonce that the login didn't issue", ctx do
      {login, params} = begin_launch(ctx.platform, "original-user")

      unrelated_params =
        Ltix.Test.launch_params(ctx.platform, nonce: "unrelated-nonce", state: login.state)

      assert {:error, %Security.NonceNotFound{}} = callback(unrelated_params, login.state)

      assert {:ok, %LaunchContext{claims: %{subject: "original-user"}}} =
               callback(params, login.state)
    end
  end

  describe "nonce storage" do
    test "records a nonce only after the ID token is verified, until the token expires",
         ctx do
      login = login(ctx.platform, LaunchStorageAdapter)

      refute_received {:validate_nonce, _nonce, _expires_at}

      nonce = Ltix.Test.extract_nonce(login.redirect_uri)
      exp = System.system_time(:second) + 600
      claims = Ltix.Test.valid_lti_claims(ctx.platform, %{"nonce" => nonce, "exp" => exp})

      launch = %{
        "id_token" => Ltix.Test.sign_id_token(claims, ctx.platform.jwk),
        "state" => login.state
      }

      assert {:ok, %LaunchContext{}} =
               callback(launch, login.state, LaunchStorageAdapter)

      assert_received {:validate_nonce, ^nonce, expires_at}
      assert expires_at == DateTime.from_unix!(exp + 5)

      assert {:error, %Security.NonceReused{}} =
               callback(launch, login.state, LaunchStorageAdapter)
    end
  end

  describe "malformed browser state" do
    test "rejects missing, empty, and nonbinary expected state even when returned state matches",
         ctx do
      {login, params} = begin_launch(ctx.platform, "original-user")

      for state <- [nil, "", 123, [], %{}] do
        assert {:error, %Security.StateMismatch{}} =
                 callback(Map.put(params, "state", state), state)
      end

      assert {:error, %Security.StateMismatch{}} = callback(Map.delete(params, "state"), nil)
      assert {:ok, %LaunchContext{}} = callback(params, login.state)
    end

    test "rejects missing, empty, and nonbinary returned state without consuming the nonce",
         ctx do
      {login, params} = begin_launch(ctx.platform, "original-user")

      for state <- [nil, "", 123, [], %{}] do
        assert {:error, %Security.StateMismatch{}} =
                 callback(Map.put(params, "state", state), login.state)
      end

      assert {:error, %Security.StateMismatch{}} =
               callback(Map.delete(params, "state"), login.state)

      assert {:ok, %LaunchContext{}} = callback(params, login.state)
    end
  end

  defp assert_transaction_binding(first_platform, second_platform) do
    {first_login, first_params} = begin_launch(first_platform, "first-user")
    {second_login, second_params} = begin_launch(second_platform, "second-user")

    assert {:error, %Security.NonceNotFound{}} =
             callback(Map.put(first_params, "state", second_login.state), second_login.state)

    assert {:error, %Security.NonceNotFound{}} =
             callback(Map.put(second_params, "state", first_login.state), first_login.state)

    assert {:error, %Security.StateMismatch{}} = callback(first_params, second_login.state)

    assert {:ok, %LaunchContext{} = first_launch} = callback(first_params, first_login.state)
    assert first_launch.claims.subject == "first-user"
    assert first_launch.registration == first_platform.registration

    assert {:ok, %LaunchContext{} = second_launch} = callback(second_params, second_login.state)
    assert second_launch.claims.subject == "second-user"
    assert second_launch.registration == second_platform.registration

    assert {:error, %Security.NonceReused{}} = callback(first_params, first_login.state)
    assert {:error, %Security.NonceReused{}} = callback(second_params, second_login.state)
  end

  defp login(platform, storage_adapter) do
    params =
      Map.put(Ltix.Test.login_params(platform), "client_id", platform.registration.client_id)

    {:ok, login} = Ltix.handle_login(params, @launch_url, storage_adapter: storage_adapter)
    login
  end

  defp begin_launch(platform, subject) do
    login = login(platform, StorageAdapter)

    launch_params =
      Ltix.Test.launch_params(platform,
        nonce: Ltix.Test.extract_nonce(login.redirect_uri),
        state: login.state,
        subject: subject
      )

    {login, launch_params}
  end

  defp callback(params, expected_state, storage_adapter \\ StorageAdapter) do
    Ltix.handle_callback(params, expected_state,
      storage_adapter: storage_adapter,
      req_options: [plug: {Req.Test, Ltix.JWT.KeySet}]
    )
  end
end
