defmodule Ltix.OIDC.State do
  @moduledoc false

  @spec generate() :: {String.t(), String.t()}
  def generate do
    state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    {state, nonce(state)}
  end

  @spec matches?(term(), term()) :: boolean()
  def matches?(returned, expected)
      when is_binary(returned) and is_binary(expected) and byte_size(expected) > 0 and
             byte_size(returned) == byte_size(expected) do
    :crypto.hash_equals(returned, expected)
  end

  def matches?(_returned, _expected), do: false

  # [nonce-validation]:
  # https://openid.net/specs/openid-connect-core-1_0.html#ImplicitIDTValidation
  #
  # [OIDC §3.2.2.11][nonce-validation]
  @spec nonce_matches?(term(), term()) :: boolean()
  def nonce_matches?(returned_nonce, expected_state)
      when is_binary(expected_state) and byte_size(expected_state) > 0 do
    matches?(returned_nonce, nonce(expected_state))
  end

  def nonce_matches?(_returned_nonce, _expected_state), do: false

  # [nonce-notes]:
  # https://openid.net/specs/openid-connect-core-1_0.html#NonceNotes
  #
  # [OIDC §15.5.2][nonce-notes]
  defp nonce(state) do
    digest = :crypto.hash(:sha256, ["Ltix.OIDC.nonce\0", state])
    Base.url_encode64(digest, padding: false)
  end
end
