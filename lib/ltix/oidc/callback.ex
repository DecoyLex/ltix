defmodule Ltix.OIDC.Callback do
  @moduledoc false

  alias Ltix.Errors.Invalid.DeploymentNotFound
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.Errors.Invalid.MissingParameter
  alias Ltix.Errors.Invalid.RegistrationNotFound
  alias Ltix.Errors.Security.AuthenticationFailed
  alias Ltix.Errors.Security.NonceNotFound
  alias Ltix.Errors.Security.NonceReused
  alias Ltix.Errors.Security.StateMismatch
  alias Ltix.JWT.Token
  alias Ltix.LaunchClaims
  alias Ltix.LaunchContext

  @lti "https://purl.imsglobal.org/spec/lti/claim/"
  @dl_settings_key "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings"

  # [Sec §5.1.1.3](https://www.imsglobal.org/spec/security/v1p0/#step-3-authentication-response)
  @spec call(map(), String.t(), module(), keyword()) ::
          {:ok, LaunchContext.t()} | {:error, Exception.t()}
  def call(params, expected_state, callback_module, opts \\ []) do
    claim_parsers = Keyword.get(opts, :claim_parsers, [])

    with :ok <- check_error_response(params),
         {:ok, id_token} <- extract_id_token(params),
         :ok <- verify_state(params, expected_state),
         {:ok, iss, client_id} <- peek_issuer_and_audience(id_token),
         {:ok, registration} <- lookup_registration(iss, client_id, callback_module),
         {:ok, raw_claims} <- Token.verify(id_token, registration, opts),
         :ok <- validate_nonce(raw_claims, registration, callback_module),
         :ok <- validate_required_lti_claims(raw_claims, opts),
         {:ok, deployment} <- lookup_deployment(raw_claims, registration, callback_module),
         {:ok, claims} <- LaunchClaims.from_json(raw_claims, parsers: claim_parsers) do
      {:ok, %LaunchContext{claims: claims, registration: registration, deployment: deployment}}
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
  defp verify_state(%{"state" => state}, expected_state) when state == expected_state, do: :ok

  defp verify_state(_params, _expected_state) do
    {:error, StateMismatch.exception(spec_ref: "Sec §7.3.1")}
  end

  # Peek at unverified JWT claims to get iss and aud for registration lookup.
  # Safe because Token.verify/3 validates iss and aud against the registration
  # after signature verification.
  defp peek_issuer_and_audience(id_token) do
    %JOSE.JWT{fields: fields} = JOSE.JWT.peek_payload(id_token)
    iss = fields["iss"]

    client_id =
      case fields["aud"] do
        id when is_binary(id) -> id
        [id | _] -> id
        _ -> nil
      end

    {:ok, iss, client_id}
  rescue
    _ -> {:error, MissingParameter.exception(parameter: "id_token", spec_ref: "Sec §5.1.1.3")}
  end

  defp lookup_registration(iss, client_id, callback_module) do
    case callback_module.get_registration(iss, client_id) do
      {:ok, registration} ->
        {:ok, registration}

      {:error, :not_found} ->
        {:error, RegistrationNotFound.exception(issuer: iss, client_id: client_id)}
    end
  end

  # [Sec §5.1.3 step 9](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
  # Token.verify already checked nonce is present; now validate binding + replay.
  defp validate_nonce(%{"nonce" => nonce}, registration, callback_module) do
    case callback_module.validate_nonce(nonce, registration) do
      :ok ->
        :ok

      {:error, :nonce_already_used} ->
        {:error, NonceReused.exception(spec_ref: "Sec §5.1.3 step 9")}

      {:error, :nonce_not_found} ->
        {:error, NonceNotFound.exception(spec_ref: "Sec §5.1.3 step 9")}
    end
  end

  # [Core §5.3](https://www.imsglobal.org/spec/lti/v1p3/#required-message-claims)
  defp validate_required_lti_claims(claims, opts) do
    with {:ok, message_type} <- validate_message_type(claims),
         :ok <- validate_version(claims),
         :ok <- validate_present(claims, @lti <> "deployment_id", "deployment_id", "Core §5.3.3"),
         :ok <-
           validate_present(
             claims,
             @lti <> "target_link_uri",
             "target_link_uri",
             "Core §5.3.4"
           ) do
      validate_message_specific_claims(message_type, claims, opts)
    end
  end

  defp validate_message_specific_claims("LtiResourceLinkRequest", claims, opts) do
    with :ok <- validate_resource_link(claims),
         :ok <- validate_roles_present(claims) do
      validate_sub(claims, opts)
    end
  end

  # [DL §4.4](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-request-message)
  defp validate_message_specific_claims("LtiDeepLinkingRequest", claims, _opts) do
    validate_deep_linking_settings_present(claims)
  end

  # [Core §5.3.1](https://www.imsglobal.org/spec/lti/v1p3/#message-type-claim)
  defp validate_message_type(claims) do
    case claims[@lti <> "message_type"] do
      "LtiResourceLinkRequest" ->
        {:ok, "LtiResourceLinkRequest"}

      # [DL §4.4.2](https://www.imsglobal.org/spec/lti-dl/v2p0/#message-type)
      "LtiDeepLinkingRequest" ->
        {:ok, "LtiDeepLinkingRequest"}

      nil ->
        {:error, MissingClaim.exception(claim: "message_type", spec_ref: "Core §5.3.1")}

      other ->
        {:error,
         InvalidClaim.exception(
           claim: "message_type",
           message: "unrecognized message_type",
           value: other,
           spec_ref: "Core §5.3.1"
         )}
    end
  end

  # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
  defp validate_deep_linking_settings_present(claims) do
    case claims[@dl_settings_key] do
      %{} -> :ok
      _ -> {:error, MissingClaim.exception(claim: "deep_linking_settings", spec_ref: "DL §4.4.1")}
    end
  end

  # [Core §5.3.2](https://www.imsglobal.org/spec/lti/v1p3/#lti-version-claim)
  defp validate_version(claims) do
    case claims[@lti <> "version"] do
      "1.3.0" ->
        :ok

      nil ->
        {:error, MissingClaim.exception(claim: "version", spec_ref: "Core §5.3.2")}

      other ->
        {:error,
         InvalidClaim.exception(
           claim: "version",
           message: "unrecognized LTI version",
           value: other,
           spec_ref: "Core §5.3.2"
         )}
    end
  end

  defp validate_present(claims, full_key, display_name, spec_ref) do
    case claims[full_key] do
      value when is_binary(value) and byte_size(value) > 0 -> :ok
      _ -> {:error, MissingClaim.exception(claim: display_name, spec_ref: spec_ref)}
    end
  end

  # [Core §5.3.5](https://www.imsglobal.org/spec/lti/v1p3/#resource-link-claim)
  defp validate_resource_link(claims) do
    case claims[@lti <> "resource_link"] do
      %{"id" => id} when is_binary(id) and byte_size(id) > 0 ->
        :ok

      %{} ->
        {:error, MissingClaim.exception(claim: "resource_link.id", spec_ref: "Core §5.3.5")}

      _ ->
        {:error, MissingClaim.exception(claim: "resource_link", spec_ref: "Core §5.3.5")}
    end
  end

  # [Core §5.3.7](https://www.imsglobal.org/spec/lti/v1p3/#roles-claim)
  defp validate_roles_present(claims) do
    case claims[@lti <> "roles"] do
      roles when is_list(roles) -> :ok
      _ -> {:error, MissingClaim.exception(claim: "roles", spec_ref: "Core §5.3.7")}
    end
  end

  # [Core §5.3.6](https://www.imsglobal.org/spec/lti/v1p3/#user-identity-claims)
  # [Core §5.3.6.1](https://www.imsglobal.org/spec/lti/v1p3/#anonymous-launch-case)
  defp validate_sub(%{"sub" => sub}, _opts) when is_binary(sub) and byte_size(sub) > 0, do: :ok

  defp validate_sub(claims, opts) do
    if Keyword.get(opts, :allow_anonymous, false) and not Map.has_key?(claims, "sub") do
      :ok
    else
      {:error, MissingClaim.exception(claim: "sub", spec_ref: "Core §5.3.6")}
    end
  end

  # [Core §3.1.3](https://www.imsglobal.org/spec/lti/v1p3/#tool-deployment)
  defp lookup_deployment(claims, registration, callback_module) do
    deployment_id = claims[@lti <> "deployment_id"]

    case callback_module.get_deployment(registration, deployment_id) do
      {:ok, deployment} ->
        {:ok, deployment}

      {:error, :not_found} ->
        {:error, DeploymentNotFound.exception(deployment_id: deployment_id)}
    end
  end
end
