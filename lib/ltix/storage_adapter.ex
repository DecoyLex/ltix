defmodule Ltix.StorageAdapter do
  @moduledoc """
  Defines callbacks for looking up registrations, deployments, and managing nonces.

  Your application implements this behaviour to connect Ltix to your
  persistence layer. See the [Storage Adapters](storage-adapters.md) guide
  for a complete Ecto-backed example.

  ## Returning your own structs

  `c:get_registration/3` and `c:get_deployment/3` can return any struct that
  implements `Ltix.Registerable` or `Ltix.Deployable`. Your struct is
  passed through to the `Ltix.LaunchContext` after a successful launch,
  so you can access your own fields (database IDs, tenant info, etc.)
  without an extra query.

  During a launch, `c:get_deployment/3` and `c:validate_nonce/4` receive the
  struct `c:get_registration/3` returned. `c:key_id/2` and `c:sign/4` receive
  the struct you passed to `Ltix.OAuth.authenticate/2`, or a launch's
  `source_registration`.

  ## Options

  Every callback receives a keyword list of options as its last argument.
  It is the list you pass as `:storage_adapter_options` to the function
  that calls your adapter, such as `Ltix.handle_login/3`, and `[]` when you
  pass none. Use it for values your lookups need, such as a tenant.

      Ltix.handle_login(params, launch_url, storage_adapter_options: [tenant: tenant])

      @impl true
      def get_registration(issuer, client_id, opts) do
        MyApp.Lti.get_registration(opts[:tenant], issuer, client_id)
      end

  Ltix stores nothing between login and launch, so pass the same options to
  `Ltix.handle_callback/3`.

  ## Callback summary

  | Callback | Called during | Purpose |
  |---|---|---|
  | `c:get_registration/3` | Login initiation and launch validation | Look up a registration by issuer and optional client_id |
  | `c:get_deployment/3` | Launch validation | Look up a deployment by registration and deployment_id |
  | `c:validate_nonce/4` | Launch validation | Record a nonce as used, and reject one already used |
  | `c:key_id/2` | Service authentication and deep linking responses | Return the ID of the key that signs for a registration |
  | `c:sign/4` | Service authentication and deep linking responses | Sign a message with that key |

  ## Signing

  `c:key_id/2` and `c:sign/4` are optional. Implement them when your tool
  calls Advantage services or builds deep linking responses. Ltix builds
  each JWT and calls your adapter for the signature, so the private key
  stays wherever you keep it. `Ltix.JWK.sign/2` signs with a key held in
  your application.

      @impl true
      def key_id(registration, _opts) do
        {:ok, MyApp.Lti.signing_key(registration).kid}
      end

      @impl true
      def sign(_registration, key_id, message, _opts) do
        case MyApp.Lti.get_key(key_id) do
          nil -> {:error, :unknown_key}
          jwk -> Ltix.JWK.sign(jwk, message)
        end
      end

  ## Failures

  Return `{:error, reason}` when storage fails. The login or launch then
  returns `Ltix.Errors.Unknown.StorageError` with that value in `result`. Ltix
  errors are returned unchanged. A callback that returns any other
  unexpected value, or a record that does not implement `Ltix.Registerable` or
  `Ltix.Deployable`, also produces a `StorageError`.
  """

  alias Ltix.AppConfig
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
  Look up a registration by issuer and client_id.

  Called during login initiation with the login request's issuer and
  client_id, and again during launch validation with the ID token's issuer
  and audience. The `client_id` may be `nil` when the platform doesn't
  include it in the login request. Your adapter must handle both cases.

  When the platform sends a deployment ID, `opts[:deployment_id]` has
  it. It comes from the login request's `lti_deployment_id` during login
  initiation and from the ID token during launch validation. Ltix has not
  verified it at either point, and it replaces a `:deployment_id` you pass
  in `:storage_adapter_options`.

  Return any struct that implements `Ltix.Registerable`. The library
  extracts the `Ltix.Registration` it needs via the protocol and
  preserves your original struct in the `Ltix.LaunchContext`.

  Return `{:error, :not_found}` when no registration matches, and the login
  or launch returns `Ltix.Errors.Invalid.RegistrationNotFound`.
  """
  # [Sec §5.1.1.1](https://www.imsglobal.org/spec/security/v1p0/#step-1-third-party-initiated-login)
  # [Core §4.1.3](https://www.imsglobal.org/spec/lti/v1p3/#client_id-login-parameter)
  @callback get_registration(
              issuer :: String.t(),
              client_id :: String.t() | nil,
              opts :: keyword()
            ) ::
              {:ok, Registerable.t()} | {:error, :not_found | term()}

  @doc """
  Look up a deployment by registration and deployment_id.

  The `deployment_id` is case-sensitive and assigned by the platform.

  Return any struct that implements `Ltix.Deployable`. The library
  validates it via the protocol and preserves your original struct
  in the `Ltix.LaunchContext`. A deployment with a different
  `deployment_id` fails the launch with `Ltix.Errors.Unknown.StorageError`.

  Return `{:error, :not_found}` when no deployment matches, and the launch
  returns `Ltix.Errors.Invalid.DeploymentNotFound`.
  """
  # [Core §3.1.3](https://www.imsglobal.org/spec/lti/v1p3/#tool-deployment)
  @callback get_deployment(
              registration :: Registerable.t(),
              deployment_id :: String.t(),
              opts :: keyword()
            ) ::
              {:ok, Deployable.t()} | {:error, :not_found | term()}

  @doc """
  Record a nonce from a verified ID token as used.

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
              registration :: Registerable.t(),
              expires_at :: DateTime.t(),
              opts :: keyword()
            ) :: :ok | {:error, :nonce_already_used | term()}

  @doc """
  Return the ID of the key that signs for a registration.

  The ID becomes the `kid` of each JWT Ltix builds for the registration, and
  platforms use it to find the public key in your key set. Ltix passes it
  back to `c:sign/4`.
  """
  # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
  @callback key_id(registration :: Registerable.t(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Sign a message with the key `c:key_id/2` returned.

  Return `{:ok, signature}` with the RSASSA-PKCS1-v1_5 SHA-256 (RS256)
  signature of `message`, as raw bytes. `Ltix.JWK.sign/2` returns this for a
  key held in your application.

  Sign with the key whose ID is `key_id`, and return `{:error, reason}` for a key
  ID you can't sign with.
  """
  # [Sec §5.2.2](https://www.imsglobal.org/spec/security/v1p0/#tool-originating-messages)
  @callback sign(
              registration :: Registerable.t(),
              key_id :: String.t(),
              message :: binary(),
              opts :: keyword()
            ) ::
              {:ok, binary()} | {:error, term()}

  @optional_callbacks key_id: 2, sign: 4

  # The functions below call an adapter's callback and return an Ltix error
  # for any result other than success.

  # Returns the options for `c:get_registration/3`, with the deployment ID
  # the platform sent.
  @doc false
  @spec registration_options(keyword(), String.t() | nil) :: keyword()
  def registration_options(opts, nil), do: opts

  def registration_options(opts, deployment_id),
    do: Keyword.put(opts, :deployment_id, deployment_id)

  # Returns the adapter's record and the `Ltix.Registration` converted from it.
  @doc false
  @spec get_registration(module(), String.t(), String.t() | nil, keyword()) ::
          {:ok, Registerable.t(), Registration.t()} | {:error, Exception.t()}
  def get_registration(adapter, issuer, client_id, opts) do
    case adapter.get_registration(issuer, client_id, opts) do
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
  @spec get_deployment(module(), Registerable.t(), String.t(), keyword()) ::
          {:ok, Deployable.t()} | {:error, Exception.t()}
  def get_deployment(adapter, registration, deployment_id, opts) do
    case adapter.get_deployment(registration, deployment_id, opts) do
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
  @spec validate_nonce(module(), String.t(), Registerable.t(), DateTime.t(), keyword()) ::
          :ok | {:error, Exception.t()}
  def validate_nonce(adapter, nonce, registration, expires_at, opts) do
    case adapter.validate_nonce(nonce, registration, expires_at, opts) do
      :ok ->
        :ok

      {:error, :nonce_already_used} ->
        {:error, NonceReused.exception()}

      result ->
        {:error, storage_error(:validate_nonce, result)}
    end
  end

  # Returns a compact RS256 JWT with the given claims, signed by the adapter.
  # [RFC 7515 §7.1](https://www.rfc-editor.org/rfc/rfc7515#section-7.1)
  @doc false
  @spec sign_jwt(module(), Registerable.t(), map(), keyword()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def sign_jwt(adapter, registration, claims, opts) do
    with :ok <- require_signing(adapter),
         {:ok, key_id} <- key_id(adapter, registration, opts) do
      header = %{"alg" => "RS256", "typ" => "JWT", "kid" => key_id}
      message = encode_segment(header) <> "." <> encode_segment(claims)

      case adapter.sign(registration, key_id, message, opts) do
        {:ok, signature} when is_binary(signature) ->
          {:ok, message <> "." <> Base.url_encode64(signature, padding: false)}

        result ->
          {:error, storage_error(:sign, result)}
      end
    end
  end

  defp require_signing(adapter) do
    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :key_id, 2) and
         function_exported?(adapter, :sign, 4) do
      :ok
    else
      {:error,
       StorageError.exception(
         callback: :sign,
         reason:
           "is not implemented. #{inspect(adapter)} must implement key_id/2 and sign/4 " <>
             "to call Advantage services or build deep linking responses"
       )}
    end
  end

  defp key_id(adapter, registration, opts) do
    case adapter.key_id(registration, opts) do
      {:ok, key_id} when is_binary(key_id) and key_id != "" -> {:ok, key_id}
      result -> {:error, storage_error(:key_id, result)}
    end
  end

  defp encode_segment(map) do
    Base.url_encode64(AppConfig.json_library!().encode!(map), padding: false)
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
