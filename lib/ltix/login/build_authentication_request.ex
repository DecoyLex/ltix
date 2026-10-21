defmodule Ltix.Login.BuildAuthenticationRequest do
  @moduledoc false
  use Ltix.Login

  alias Ltix.OIDC.AuthenticationRequest
  alias Ltix.OIDC.State

  # [Sec §5.1.1.2](https://www.imsglobal.org/spec/security/v1p0/#step-2-authentication-request)
  @impl Ltix.Step
  def call(
        %Ltix.Login{params: params, registration: registration, private: private} = login,
        _opts
      ) do
    {state, nonce} = State.generate(registration)

    request =
      AuthenticationRequest.build(registration, %{
        redirect_uri: private.ltix_redirect_uri,
        state: state,
        nonce: nonce,
        login_hint: params["login_hint"],
        lti_message_hint: params["lti_message_hint"]
      })

    private = Map.merge(private, %{ltix_state: state, ltix_authentication_request: request})
    {:ok, %{login | private: private}}
  end

  @impl Ltix.Ordered
  def after?(Ltix.Login.RegistrationFound), do: true
  def after?(_module), do: false
end
