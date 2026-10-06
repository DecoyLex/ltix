defmodule Ltix.OIDC.Callback do
  @moduledoc false

  alias Ltix.Errors
  alias Ltix.JWT.Token
  alias Ltix.LaunchClaims
  alias Ltix.LaunchContext
  alias Ltix.OIDC.State
  alias Ltix.Registration
  alias Ltix.StorageAdapter

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.Errors.Invalid.MissingParameter

  alias Ltix.Errors.Security.AuthenticationFailed
  alias Ltix.Errors.Security.NonceNotFound
  alias Ltix.Errors.Security.StateMismatch

  @lti "https://purl.imsglobal.org/spec/lti/claim/"
  @dl_settings_key "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings"

  # [Sec §5.1.1.3](https://www.imsglobal.org/spec/security/v1p0/#step-3-authentication-response)
  @spec call(map(), String.t(), module(), keyword()) ::
          {:ok, LaunchContext.t()} | {:error, Exception.t()}
  def call(params, expected_state, callback_module, opts \\ []) do
    case launch(params, expected_state, callback_module, opts) do
      {:ok, context, _registration} -> {:ok, context}
      {:error, _error} = error -> error
    end
  end

  # Same as `call/4`, and also returns the resolved registration.
  @spec launch(map(), String.t(), module(), keyword()) ::
          {:ok, LaunchContext.t(), Registration.t()} | {:error, Exception.t()}
  def launch(params, expected_state, callback_module, opts) do
    token_opts =
      Keyword.take(opts, [
        :clock_skew,
        :max_token_age,
        :req_options,
        :jwks_cache,
        :local_network_access
      ])

    with :ok <- check_error_response(params),
         {:ok, id_token} <- extract_id_token(params),
         :ok <- verify_state(params, expected_state),
         {:ok, iss, client_id} <- peek_issuer_and_audience(id_token),
         {:ok, user_registration, registration} <-
           StorageAdapter.get_registration(callback_module, iss, client_id),
         {:ok, raw_claims} <- Token.verify(id_token, registration, token_opts),
         :ok <- verify_nonce_binding(raw_claims, expected_state, registration),
         :ok <-
           StorageAdapter.validate_nonce(
             callback_module,
             raw_claims["nonce"],
             registration,
             Token.expires_at(raw_claims, token_opts)
           ),
         :ok <- validate_required_lti_claims(raw_claims, opts),
         {:ok, user_deployment} <-
           StorageAdapter.get_deployment(
             callback_module,
             registration,
             raw_claims[@lti <> "deployment_id"]
           ),
         {:ok, claims} <-
           LaunchClaims.from_json(raw_claims, Keyword.take(opts, [:claim_parsers, :role_parsers])) do
      context = %LaunchContext{
        claims: claims,
        registration: user_registration,
        deployment: user_deployment
      }

      {:ok, context, registration}
    end
  end

  # [Sec §5.1.1.5](https://www.imsglobal.org/spec/security/v1p0/#authentication-error-response)
  defp check_error_response(%{"error" => error} = params) do
    {:error,
     AuthenticationFailed.exception(
       error: error,
       error_description: params["error_description"],
       error_uri: params["error_uri"],
       spec_ref: "Sec §5.1.1.5"
     )}
  end

  defp check_error_response(_params), do: :ok

  defp extract_id_token(%{"id_token" => id_token})
       when is_binary(id_token) and byte_size(id_token) > 0 do
    {:ok, id_token}
  end

  defp extract_id_token(_params) do
    {:error, MissingParameter.exception(parameter: "id_token", spec_ref: "Sec §5.1.1.3")}
  end

  # [Sec §7.3.1](https://www.imsglobal.org/spec/security/v1p0/#prohibiting-the-login-csrf-vulnerability)
  defp verify_state(params, expected_state) do
    if State.matches?(params["state"], expected_state) do
      :ok
    else
      {:error, StateMismatch.exception(spec_ref: "Sec §7.3.1")}
    end
  end

  # Peek at unverified JWT claims to get iss and aud for registration lookup.
  # Safe because Token.verify/3 validates iss and aud against the registration
  # after signature verification.
  defp peek_issuer_and_audience(id_token) do
    with {:ok, claims} <- Token.peek_claims(id_token),
         {:ok, issuer} <- issuer(claims) do
      {:ok, issuer, audience(claims["aud"])}
    end
  end

  # [Sec §5.1.2](https://www.imsglobal.org/spec/security/v1p0/#id-token)
  defp issuer(%{"iss" => issuer}) when is_binary(issuer), do: {:ok, issuer}

  defp issuer(%{"iss" => issuer}) when not is_nil(issuer) do
    {:error,
     InvalidClaim.exception(
       claim: "iss",
       value: issuer,
       message: "must be a string",
       spec_ref: "Sec §5.1.2"
     )}
  end

  defp issuer(_claims), do: {:error, MissingClaim.exception(claim: "iss", spec_ref: "Sec §5.1.2")}

  defp audience(client_id) when is_binary(client_id), do: client_id
  defp audience([client_id | _]) when is_binary(client_id), do: client_id
  defp audience(_audience), do: nil

  # [nonce-validation]:
  # https://openid.net/specs/openid-connect-core-1_0.html#ImplicitIDTValidation
  #
  # [OIDC §3.2.2.11][nonce-validation]
  defp verify_nonce_binding(claims, expected_state, registration) do
    if State.nonce_matches?(claims["nonce"], expected_state, registration) do
      :ok
    else
      {:error, NonceNotFound.exception(spec_ref: "OIDC §3.2.2.11")}
    end
  end

  # Every missing or invalid required claim is reported.
  #
  # [Core §5.3](https://www.imsglobal.org/spec/lti/v1p3/#required-message-claims)
  defp validate_required_lti_claims(claims, opts) do
    message_type = claims[@lti <> "message_type"]

    Errors.collect([
      validate_message_type(message_type),
      validate_version(claims[@lti <> "version"]),
      # [Core §5.3.3](https://www.imsglobal.org/spec/lti/v1p3/#lti-deployment-id-claim)
      validate_string(claims, @lti <> "deployment_id", "deployment_id", "Core §5.3.3"),
      # [Core §5.3.4](https://www.imsglobal.org/spec/lti/v1p3/#target-link-uri)
      validate_string(claims, @lti <> "target_link_uri", "target_link_uri", "Core §5.3.4")
      | validate_message_specific_claims(message_type, claims, opts)
    ])
  end

  defp validate_message_specific_claims("LtiResourceLinkRequest", claims, opts) do
    [
      validate_resource_link(claims[@lti <> "resource_link"]),
      validate_roles(claims[@lti <> "roles"]),
      validate_sub(claims, opts)
    ]
  end

  # [DL §4.4](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-request-message)
  defp validate_message_specific_claims("LtiDeepLinkingRequest", claims, _opts) do
    [validate_deep_linking_settings(claims[@dl_settings_key])]
  end

  defp validate_message_specific_claims(_message_type, _claims, _opts), do: []

  # [Core §5.3.1](https://www.imsglobal.org/spec/lti/v1p3/#message-type-claim)
  # [DL §4.4.2](https://www.imsglobal.org/spec/lti-dl/v2p0/#message-type)
  defp validate_message_type(message_type)
       when message_type in ["LtiResourceLinkRequest", "LtiDeepLinkingRequest"],
       do: nil

  defp validate_message_type(nil) do
    MissingClaim.exception(claim: "message_type", spec_ref: "Core §5.3.1")
  end

  defp validate_message_type(message_type) do
    InvalidClaim.exception(
      claim: "message_type",
      message: "unrecognized message_type",
      value: message_type,
      spec_ref: "Core §5.3.1"
    )
  end

  # [Core §5.3.2](https://www.imsglobal.org/spec/lti/v1p3/#lti-version-claim)
  defp validate_version("1.3.0"), do: nil

  defp validate_version(nil),
    do: MissingClaim.exception(claim: "version", spec_ref: "Core §5.3.2")

  defp validate_version(version) do
    InvalidClaim.exception(
      claim: "version",
      message: "unrecognized LTI version",
      value: version,
      spec_ref: "Core §5.3.2"
    )
  end

  defp validate_string(claims, key, claim, spec_ref) do
    case claims[key] do
      value when is_binary(value) and byte_size(value) > 0 ->
        nil

      nil ->
        MissingClaim.exception(claim: claim, spec_ref: spec_ref)

      value ->
        InvalidClaim.exception(
          claim: claim,
          value: value,
          message: "must be a non-empty string",
          spec_ref: spec_ref
        )
    end
  end

  # [Core §5.3.5](https://www.imsglobal.org/spec/lti/v1p3/#resource-link-claim)
  defp validate_resource_link(resource_link) when is_map(resource_link) do
    validate_string(resource_link, "id", "resource_link.id", "Core §5.3.5")
  end

  defp validate_resource_link(nil) do
    MissingClaim.exception(claim: "resource_link", spec_ref: "Core §5.3.5")
  end

  defp validate_resource_link(resource_link) do
    invalid_object("resource_link", resource_link, "Core §5.3.5")
  end

  # [Core §5.3.7](https://www.imsglobal.org/spec/lti/v1p3/#roles-claim)
  defp validate_roles(nil), do: MissingClaim.exception(claim: "roles", spec_ref: "Core §5.3.7")

  defp validate_roles(roles) do
    if is_list(roles) and Enum.all?(roles, &is_binary/1) do
      nil
    else
      InvalidClaim.exception(
        claim: "roles",
        value: roles,
        message: "must be an array of strings",
        spec_ref: "Core §5.3.7"
      )
    end
  end

  # [Core §5.3.6](https://www.imsglobal.org/spec/lti/v1p3/#user-identity-claims)
  # [Core §5.3.6.1](https://www.imsglobal.org/spec/lti/v1p3/#anonymous-launch-case)
  defp validate_sub(claims, opts) do
    if Keyword.get(opts, :allow_anonymous, false) and not Map.has_key?(claims, "sub") do
      nil
    else
      validate_string(claims, "sub", "sub", "Core §5.3.6")
    end
  end

  # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
  defp validate_deep_linking_settings(settings) when is_map(settings), do: nil

  defp validate_deep_linking_settings(nil) do
    MissingClaim.exception(claim: "deep_linking_settings", spec_ref: "DL §4.4.1")
  end

  defp validate_deep_linking_settings(settings) do
    invalid_object("deep_linking_settings", settings, "DL §4.4.1")
  end

  defp invalid_object(claim, value, spec_ref) do
    InvalidClaim.exception(
      claim: claim,
      value: value,
      message: "must be an object",
      spec_ref: spec_ref
    )
  end
end
