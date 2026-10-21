defmodule Ltix.Launch.VerifyNonceBinding do
  @moduledoc false
  use Ltix.Launch

  alias Ltix.Errors.Security.NonceNotFound
  alias Ltix.OIDC.State

  # [OIDC §3.2.2.11](https://openid.net/specs/openid-connect-core-1_0.html#ImplicitIDTValidation)
  @impl Ltix.Step
  def call(%Ltix.Launch{raw: raw, private: private} = launch, _opts) do
    if State.nonce_matches?(raw["nonce"], private.ltix_state, launch.registration),
      do: {:ok, launch},
      else: {:halt, NonceNotFound.exception()}
  end

  @impl Ltix.Ordered
  def before?(Ltix.Launch.Verified), do: true
  def before?(_module), do: false

  @impl Ltix.Ordered
  def after?(Ltix.Launch.VerifyIdToken), do: true
  def after?(_module), do: false
end
