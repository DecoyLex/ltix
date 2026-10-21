defmodule Ltix.Login.LookUpRegistration do
  @moduledoc false
  use Ltix.Login

  alias Ltix.StorageAdapter

  @impl Ltix.Step
  def call(%Ltix.Login{params: params, private: private} = login, _opts) do
    options =
      StorageAdapter.registration_options(
        private.ltix_storage_adapter_options,
        optional(params, "lti_deployment_id")
      )

    case StorageAdapter.get_registration(
           private.ltix_storage_adapter,
           params["iss"],
           optional(params, "client_id"),
           options
         ) do
      {:ok, source_registration, registration} ->
        {:ok, %{login | registration: registration, source_registration: source_registration}}

      {:error, error} ->
        {:halt, error}
    end
  end

  @impl Ltix.Ordered
  def before?(Ltix.Login.RegistrationFound), do: true
  def before?(_module), do: false

  @impl Ltix.Ordered
  def after?(Ltix.Login.CheckParameters), do: true
  def after?(_module), do: false

  # An empty client_id or lti_deployment_id is treated as absent.
  # [Core §4.1.2](https://www.imsglobal.org/spec/lti/v1p3/#lti_deployment_id-login-parameter)
  # [Core §4.1.3](https://www.imsglobal.org/spec/lti/v1p3/#client_id-login-parameter)
  defp optional(params, parameter) do
    case params[parameter] do
      "" -> nil
      value -> value
    end
  end
end
