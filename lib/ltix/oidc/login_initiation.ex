defmodule Ltix.OIDC.LoginInitiation do
  @moduledoc false

  alias Ltix.OIDC.AuthenticationRequest
  alias Ltix.OIDC.State
  alias Ltix.StorageAdapter

  alias Ltix.Errors.Invalid.MissingParameter

  @required_params ~w(iss login_hint target_link_uri)
  @optional_params ~w(client_id lti_message_hint)

  # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
  @spec call(map(), module(), String.t()) ::
          {:ok, %{redirect_uri: String.t(), state: String.t()}} | {:error, Exception.t()}
  def call(params, callback_module, redirect_uri) do
    with :ok <- validate_login_params(params),
         {:ok, _user_registration, registration} <-
           StorageAdapter.get_registration(callback_module, params["iss"], client_id(params)),
         {state, nonce} = State.generate(registration),
         :ok <- StorageAdapter.store_nonce(callback_module, nonce, registration) do
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

  # An empty client_id is treated as absent.
  # [Core §4.1.3](https://www.imsglobal.org/spec/lti/v1p3/#client_id-login-parameter)
  defp client_id(%{"client_id" => ""}), do: nil
  defp client_id(params), do: params["client_id"]

  # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
  defp validate_login_params(params) do
    Enum.find_value(@required_params ++ @optional_params, :ok, fn parameter ->
      case Map.fetch(params, parameter) do
        {:ok, value} when is_binary(value) and (value != "" or parameter in @optional_params) ->
          nil

        :error when parameter in @optional_params ->
          nil

        _ ->
          {:error,
           MissingParameter.exception(
             parameter: parameter,
             spec_ref: "Sec §5.1.1.1"
           )}
      end
    end)
  end
end
