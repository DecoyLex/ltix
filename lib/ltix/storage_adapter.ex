defmodule Ltix.StorageAdapter do
  @moduledoc """
  Defines callbacks for looking up registrations, deployments, and managing nonces.

  Your application implements this behaviour to connect Ltix to your
  persistence layer. See the [Storage Adapters](storage-adapters.md) guide
  for a complete Ecto-backed example.

  ## Returning your own structs

  `c:get_registration/2` and `c:get_deployment/2` can return any struct that
  implements `Ltix.Registerable` or `Ltix.Deployable`. Your struct is
  passed through to the `Ltix.LaunchContext` after a successful launch,
  so you can access your own fields (database IDs, tenant info, etc.)
  without an extra query.

  ## Callback summary

  | Callback | Called during | Purpose |
  |---|---|---|
  | `c:get_registration/2` | Login initiation and launch validation | Look up a platform by issuer and optional client_id |
  | `c:get_deployment/2` | Launch validation | Look up a deployment by registration and deployment_id |
  | `c:validate_nonce/3` | Launch validation | Record a nonce as used, and reject one already used |

  ## Failures

  Return `{:error, reason}` when storage fails. The login or launch then
  returns `Ltix.Errors.Unknown.StorageError` with that value in `result`. Ltix
  errors are returned unchanged. A callback that returns any other
  unexpected value, or a record that does not implement `Ltix.Registerable` or
  `Ltix.Deployable`, also produces a `StorageError`.
  """

  alias Ltix.Deployable
  alias Ltix.Deployment
  alias Ltix.Errors
  alias Ltix.Errors.Invalid.DeploymentNotFound
  alias Ltix.Errors.Invalid.RegistrationNotFound
  alias Ltix.Errors.Security.NonceReused
  alias Ltix.Errors.Unknown.StorageError
  alias Ltix.Records
  alias Ltix.Registerable
  alias Ltix.Registration

  @doc """
  Look up a platform registration by issuer and client_id.

  Called during login initiation with the login request's issuer and
  client_id, and again during launch validation with the ID Token's issuer
  and audience. The `client_id` may be `nil` when the platform doesn't
  include it in the login request. Your adapter must handle both cases.

  Return any struct that implements `Ltix.Registerable`. The library
  extracts the `Ltix.Registration` it needs via the protocol and
  preserves your original struct in the `Ltix.LaunchContext`.

  Return `{:error, :not_found}` when no registration matches, and the login
  or launch returns `Ltix.Errors.Invalid.RegistrationNotFound`.
  """
  # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
  # [Core §4.1.3](https://www.imsglobal.org/spec/lti/v1p3/#client_id-login-parameter)
  @callback get_registration(issuer :: String.t(), client_id :: String.t() | nil) ::
              {:ok, Registerable.t()} | {:error, :not_found | term()}

  @doc """
  Look up a deployment by registration and deployment_id.

  The `deployment_id` is case-sensitive and assigned by the platform.
  The `registration` parameter is the resolved `Ltix.Registration`,
  not the original struct returned by `c:get_registration/2`.

  Return any struct that implements `Ltix.Deployable`. The library
  validates it via the protocol and preserves your original struct
  in the `Ltix.LaunchContext`. A deployment with a different
  `deployment_id` fails the launch with `Ltix.Errors.Unknown.StorageError`.

  Return `{:error, :not_found}` when no deployment matches, and the launch
  returns `Ltix.Errors.Invalid.DeploymentNotFound`.
  """
  # [Core §3.1.3](https://www.imsglobal.org/spec/lti/v1p3/#tool-deployment)
  @callback get_deployment(registration :: Registration.t(), deployment_id :: String.t()) ::
              {:ok, Deployable.t()} | {:error, :not_found | term()}

  @doc """
  Record a nonce from a verified ID Token as used.

  Called during launch validation, after the token's signature and claims
  are verified. Return `:ok` the first time a nonce is recorded, and
  `{:error, :nonce_already_used}` every time after that. The launch then
  returns `Ltix.Errors.Security.NonceReused`.

  Recording has to be atomic. When two launches with the same nonce arrive
  at once, only one of them gets `:ok`.

  Keep each record until `expires_at`. Ltix rejects the token after that
  time, so you can delete the record then.
  """
  # [Sec §5.1.3 step 9](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
  @callback validate_nonce(
              nonce :: String.t(),
              registration :: Registration.t(),
              expires_at :: DateTime.t()
            ) :: :ok | {:error, :nonce_already_used | term()}

  # The functions below call an adapter's callback and return an Ltix error
  # for any result other than success.

  # Returns the adapter's record and the `Ltix.Registration` converted from it.
  @doc false
  @spec get_registration(module(), String.t(), String.t() | nil) ::
          {:ok, Registerable.t(), Registration.t()} | {:error, Exception.t()}
  def get_registration(adapter, issuer, client_id) do
    case adapter.get_registration(issuer, client_id) do
      {:ok, registration} ->
        with {:ok, resolved} <- convert(:get_registration, registration, :registration) do
          {:ok, registration, resolved}
        end

      {:error, :not_found} ->
        {:error, RegistrationNotFound.exception(issuer: issuer, client_id: client_id)}

      result ->
        {:error, storage_error(:get_registration, result)}
    end
  end

  @doc false
  @spec get_deployment(module(), Registration.t(), String.t()) ::
          {:ok, Deployable.t()} | {:error, Exception.t()}
  def get_deployment(adapter, registration, deployment_id) do
    case adapter.get_deployment(registration, deployment_id) do
      {:ok, deployment} ->
        check_deployment_id(deployment, deployment_id)

      {:error, :not_found} ->
        {:error, DeploymentNotFound.exception(deployment_id: deployment_id)}

      result ->
        {:error, storage_error(:get_deployment, result)}
    end
  end

  # [Core §5.3.3](https://www.imsglobal.org/spec/lti/v1p3/#lti-deployment-id-claim)
  defp check_deployment_id(deployment, deployment_id) do
    case convert(:get_deployment, deployment, :deployment) do
      {:ok, %Deployment{deployment_id: ^deployment_id}} ->
        {:ok, deployment}

      {:ok, %Deployment{deployment_id: other_deployment_id}} ->
        {:error,
         StorageError.exception(
           callback: :get_deployment,
           result: {:ok, deployment},
           reason:
             "returned deployment #{inspect(other_deployment_id)} " <>
               "for deployment_id #{inspect(deployment_id)}"
         )}

      {:error, _error} = error ->
        error
    end
  end

  # A record that does not convert is a storage error.
  defp convert(callback, record, kind) do
    case Records.convert(record, kind) do
      {:invalid, message} ->
        {:error,
         StorageError.exception(
           callback: callback,
           result: {:ok, record},
           reason: "returned an invalid record, #{message}"
         )}

      result ->
        result
    end
  end

  # [Sec §5.1.3 step 9](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
  @doc false
  @spec validate_nonce(module(), String.t(), Registration.t(), DateTime.t()) ::
          :ok | {:error, Exception.t()}
  def validate_nonce(adapter, nonce, registration, expires_at) do
    case adapter.validate_nonce(nonce, registration, expires_at) do
      :ok ->
        :ok

      {:error, :nonce_already_used} ->
        {:error, NonceReused.exception(spec_ref: "Sec §5.1.3 step 9")}

      result ->
        {:error, storage_error(:validate_nonce, result)}
    end
  end

  # Ltix errors returned by the adapter are returned unchanged.
  defp storage_error(callback, {:error, reason} = result) do
    if Errors.ltix_error?(reason),
      do: reason,
      else: StorageError.exception(callback: callback, result: result)
  end

  defp storage_error(callback, result) do
    StorageError.exception(callback: callback, result: result)
  end
end
