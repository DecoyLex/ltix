defmodule Ltix.OIDC.LoginInitiation do
  @moduledoc false

  alias Ltix.Errors.Invalid.MissingParameter
  alias Ltix.Errors.Invalid.RegistrationNotFound
  alias Ltix.OIDC.AuthenticationRequest

  @required_params ~w(iss login_hint target_link_uri)

  # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
  @spec call(map(), module(), String.t()) ::
          {:ok, %{redirect_uri: String.t(), state: String.t()}} | {:error, Exception.t()}
  def call(params, callback_module, redirect_uri) do
    with :ok <- validate_required_params(params),
         {:ok, registration} <- lookup_registration(params, callback_module) do
      state = generate_token()
      nonce = generate_token()

      callback_module.store_nonce(nonce, registration)

      auth_redirect =
        AuthenticationRequest.build(registration, %{
          redirect_uri: redirect_uri,
          state: state,
          nonce: nonce,
          login_hint: params["login_hint"],
          lti_message_hint: params["lti_message_hint"]
        })

      {:ok, %{redirect_uri: auth_redirect, state: state}}
    end
  end

  # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
  defp validate_required_params(params) do
    Enum.find_value(@required_params, :ok, fn param ->
      if is_nil(params[param]) or params[param] == "" do
        {:error,
         MissingParameter.exception(
           parameter: param,
           spec_ref: "Sec §5.1.1.1"
         )}
      end
    end)
  end

  defp lookup_registration(params, callback_module) do
    iss = params["iss"]
    client_id = params["client_id"]

    case callback_module.get_registration(iss, client_id) do
      {:ok, registration} ->
        {:ok, registration}

      {:error, :not_found} ->
        {:error,
         RegistrationNotFound.exception(
           issuer: iss,
           client_id: client_id
         )}
    end
  end

  defp generate_token do
    Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  end
end
