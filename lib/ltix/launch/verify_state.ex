defmodule Ltix.Launch.VerifyState do
  @moduledoc false
  use Ltix.Launch

  alias Ltix.Errors.Security.StateMismatch
  alias Ltix.OIDC.State

  # [Sec §7.3.1](https://www.imsglobal.org/spec/security/v1p0/#prohibiting-the-login-csrf-vulnerability)
  @impl Ltix.Step
  def call(%Ltix.Launch{private: private} = launch, _opts) do
    if State.matches?(private.ltix_params["state"], private.ltix_state),
      do: {:ok, launch},
      else: {:halt, StateMismatch.exception()}
  end

  @impl Ltix.Ordered
  def before?(Ltix.Launch.Verified), do: true
  def before?(_module), do: false

  @impl Ltix.Ordered
  def after?(Ltix.Launch.ExtractIdToken), do: true
  def after?(_module), do: false
end
