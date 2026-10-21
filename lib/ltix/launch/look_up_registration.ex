defmodule Ltix.Launch.LookUpRegistration do
  @moduledoc false
  use Ltix.Launch

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.JWT.Token
  alias Ltix.StorageAdapter

  @deployment_id "https://purl.imsglobal.org/spec/lti/claim/deployment_id"

  # Reading the claims before verifying them is safe, because
  # `Ltix.Launch.VerifyIdToken` checks the issuer and audience against the
  # registration, and the deployment is looked up from the verified claims.
  @impl Ltix.Step
  def call(%Ltix.Launch{private: private} = launch, _opts) do
    with {:ok, claims} <- Token.peek_claims(private.ltix_id_token),
         {:ok, issuer} <- issuer(claims),
         {:ok, source_registration, registration} <-
           StorageAdapter.get_registration(
             private.ltix_storage_adapter,
             issuer,
             audience(claims["aud"]),
             StorageAdapter.registration_options(
               private.ltix_storage_adapter_options,
               deployment_id(claims[@deployment_id])
             )
           ) do
      {:ok, %{launch | registration: registration, source_registration: source_registration}}
    else
      {:error, error} -> {:halt, error}
    end
  end

  @impl Ltix.Ordered
  def before?(Ltix.Launch.Verified), do: true
  def before?(_module), do: false

  @impl Ltix.Ordered
  def after?(Ltix.Launch.VerifyState), do: true
  def after?(_module), do: false

  # [Sec §5.1.2](https://www.imsglobal.org/spec/security/v1p0/#id-token)
  defp issuer(%{"iss" => issuer}) when is_binary(issuer), do: {:ok, issuer}

  defp issuer(%{"iss" => issuer}) when not is_nil(issuer) do
    {:error, InvalidClaim.exception(claim: "iss", value: issuer, message: "must be a string")}
  end

  defp issuer(_claims), do: {:error, MissingClaim.exception(claim: "iss")}

  defp audience(client_id) when is_binary(client_id), do: client_id
  defp audience([client_id | _]) when is_binary(client_id), do: client_id
  defp audience(_audience), do: nil

  defp deployment_id(deployment_id) when is_binary(deployment_id) and deployment_id != "",
    do: deployment_id

  defp deployment_id(_deployment_id), do: nil
end
