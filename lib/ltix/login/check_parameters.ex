defmodule Ltix.Login.CheckParameters do
  @moduledoc false
  use Ltix.Login

  alias Ltix.Errors.Invalid.MissingParameter

  @required ~w(iss login_hint target_link_uri)
  @optional ~w(client_id lti_message_hint lti_deployment_id)
  @parameters @required ++ @optional

  # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
  @impl Ltix.Step
  def call(%Ltix.Login{params: params} = login, _opts) do
    case Enum.find(@parameters, &(!valid?(params, &1))) do
      nil ->
        {:ok, login}

      parameter ->
        {:halt, MissingParameter.exception(parameter: parameter)}
    end
  end

  @impl Ltix.Ordered
  def before?(Ltix.Login.RegistrationFound), do: true
  def before?(_module), do: false

  defp valid?(params, parameter) do
    case Map.fetch(params, parameter) do
      {:ok, value} when parameter in @required -> is_binary(value) && value != ""
      {:ok, value} -> is_binary(value)
      :error -> parameter in @optional
    end
  end
end
