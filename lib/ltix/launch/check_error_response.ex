defmodule Ltix.Launch.CheckErrorResponse do
  @moduledoc false
  use Ltix.Launch

  alias Ltix.Errors.Security.AuthenticationFailed

  # [Sec §5.1.1.5](https://www.imsglobal.org/spec/security/v1p0/#authentication-error-response)
  @impl Ltix.Step
  def call(%Ltix.Launch{private: %{ltix_params: %{"error" => error} = params}}, _opts) do
    {:halt,
     AuthenticationFailed.exception(
       error: error,
       error_description: params["error_description"],
       error_uri: params["error_uri"]
     )}
  end

  def call(%Ltix.Launch{} = launch, _opts), do: {:ok, launch}

  @impl Ltix.Ordered
  def before?(Ltix.Launch.Verified), do: true
  def before?(_module), do: false
end
