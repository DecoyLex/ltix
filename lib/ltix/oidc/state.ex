defmodule Ltix.OIDC.State do
  @moduledoc false

  alias Ltix.Registration

  # The nonce is derived from the state and the registration the login
  # started with, so a token is accepted only for that browser and that
  # registration.
  @spec generate(Registration.t()) :: {String.t(), String.t()}
  def generate(%Registration{} = registration) do
    state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    {state, nonce(state, registration)}
  end

  @spec matches?(term(), term()) :: boolean()
  def matches?(returned, expected)
      when is_binary(returned) and is_binary(expected) and byte_size(expected) > 0 and
             byte_size(returned) == byte_size(expected) do
    :crypto.hash_equals(returned, expected)
  end

  def matches?(_returned, _expected), do: false

  # [OIDC §3.2.2.11](https://openid.net/specs/openid-connect-core-1_0.html#ImplicitIDTValidation)
  # [RFC 9700 §2.1](https://www.rfc-editor.org/rfc/rfc9700.html#section-2.1)
  @spec nonce_matches?(term(), term(), Registration.t()) :: boolean()
  def nonce_matches?(returned_nonce, expected_state, %Registration{} = registration)
      when is_binary(expected_state) and byte_size(expected_state) > 0 do
    matches?(returned_nonce, nonce(expected_state, registration))
  end

  def nonce_matches?(_returned_nonce, _expected_state, _registration), do: false

  # [OIDC §15.5.2](https://openid.net/specs/openid-connect-core-1_0.html#NonceNotes)
  defp nonce(state, %Registration{issuer: issuer, client_id: client_id}) do
    digest = :crypto.hash(:sha256, ["Ltix.OIDC.nonce\0", state, 0, issuer, 0, client_id])
    Base.url_encode64(digest, padding: false)
  end
end
