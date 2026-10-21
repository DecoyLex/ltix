defmodule Ltix.Launch.ValidateNonce do
  @moduledoc false
  use Ltix.Launch

  alias Ltix.JWT.Token
  alias Ltix.StorageAdapter

  # [Sec §5.1.3 step 9](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
  @impl Ltix.Step
  def call(%Ltix.Launch{raw: raw, private: private} = launch, _opts) do
    case StorageAdapter.validate_nonce(
           private.ltix_storage_adapter,
           raw["nonce"],
           launch.source_registration,
           Token.expires_at(raw, private.ltix_options),
           private.ltix_storage_adapter_options
         ) do
      :ok -> {:ok, launch}
      {:error, error} -> {:halt, error}
    end
  end

  @impl Ltix.Ordered
  def before?(Ltix.Launch.Verified), do: true
  def before?(_module), do: false

  @impl Ltix.Ordered
  def after?(Ltix.Launch.VerifyNonceBinding), do: true
  def after?(_module), do: false
end
