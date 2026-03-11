defmodule Ltix.Test.JWTHelper do
  @moduledoc """
  Generate RSA keys and sign JWTs for testing.

  Delegates to `Ltix.Test` — kept as a convenience alias used throughout
  the internal test suite.
  """

  defdelegate generate_rsa_key_pair(), to: Ltix.Test
  defdelegate build_jwks(public_keys), to: Ltix.Test

  def mint_id_token(claims, private_jwk, opts \\ []),
    do: Ltix.Test.mint_id_token(claims, private_jwk, opts)

  def valid_lti_claims(overrides \\ %{}),
    do: Ltix.Test.valid_lti_claims(overrides)
end
