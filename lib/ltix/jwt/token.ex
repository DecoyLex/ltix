defmodule Ltix.JWT.Token do
  @moduledoc """
  Decodes and validates LTI ID Tokens (JWTs).

  Implements the
  [Authentication Response Validation](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
  steps from the IMS Security Framework. The module verifies the JWT signature
  using the platform's public key (fetched via `Ltix.JWT.KeySet`), enforces
  RS256-only signing, and validates all required claims.

  Critical header extensions ([RFC 7515 §4.1.11][crit]) are not supported.

  [crit]: https://www.rfc-editor.org/rfc/rfc7515#section-4.1.11

  ## Examples

      {:ok, claims} = Ltix.JWT.Token.verify(token_string, registration)

  ## Validation Steps

  1. Decode the JWT header to extract `alg` and `kid`
  2. Reject any algorithm other than RS256
  3. Fetch the platform's public key by `kid` via `Ltix.JWT.KeySet`
  4. Verify the RS256 signature
  5. Validate `iss` matches the registration's issuer
  6. Validate `aud` is the tool's `client_id`, or a list containing only it
  7. Validate `azp` matches `client_id` (when present)
  8. Validate `iat` is a NumericDate
  9. Validate `exp` is not in the past and `iat` is within the maximum
     token age (with configurable clock skew)
  10. Validate `nonce` is present

  ## Options

    * `:clock_skew` — seconds of tolerance for `exp` and `iat` validation
      (default: `5`)
    * `:max_token_age` — seconds after `iat` that a token is still accepted,
      or `:infinity` to accept any age (defaults to application config, then
      `3600`)
    * `:now` — override current time in unix seconds (useful for testing)
    * `:req_options` — extra options passed through to `Ltix.JWT.KeySet`
    * `:jwks_cache` — cache module passed through to `Ltix.JWT.KeySet`
    * `:local_network_access` — passed through to `Ltix.JWT.KeySet`
  """

  alias Ltix.AppConfig
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.InvalidJSON
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.Errors.Security.AlgorithmNotAllowed
  alias Ltix.Errors.Security.AudienceMismatch
  alias Ltix.Errors.Security.IssuerMismatch
  alias Ltix.Errors.Security.KidMissing
  alias Ltix.Errors.Security.NonceMissing
  alias Ltix.Errors.Security.SignatureInvalid
  alias Ltix.Errors.Security.TokenExpired
  alias Ltix.JWT.KeySet
  alias Ltix.Options
  alias Ltix.Registration

  @default_clock_skew 5

  @options_schema Zoi.keyword(
                    [
                      clock_skew: Zoi.integer() |> Zoi.non_negative(),
                      max_token_age:
                        Zoi.union([Zoi.integer() |> Zoi.positive(), Zoi.literal(:infinity)]),
                      now: Zoi.integer(),
                      req_options: Zoi.keyword(Zoi.any()),
                      jwks_cache: Zoi.module(),
                      local_network_access: Ltix.HTTP.local_network_access_option()
                    ],
                    unrecognized_keys: :error
                  )

  @doc """
  Verify and decode an LTI ID Token.

  Implements the validation steps from
  [Sec §5.1.3](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation).

  Returns `{:ok, claims}` with the decoded claims map on success, or
  `{:error, exception}` on any validation failure.
  """
  # [Sec §5.1.3](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
  @spec verify(String.t(), Registration.t(), keyword()) ::
          {:ok, claims :: map()} | {:error, Exception.t()}
  def verify(token_string, %Registration{} = registration, opts \\ []) do
    opts = Options.parse!(opts, @options_schema)

    with {:ok, header} <- peek_header(token_string),
         :ok <- validate_algorithm(header),
         :ok <- validate_critical_headers(header),
         {:ok, kid} <- extract_kid(header),
         {:ok, jwk} <-
           KeySet.get_key(
             registration,
             kid,
             Keyword.take(opts, [:req_options, :jwks_cache, :local_network_access])
           ),
         {:ok, claims} <- verify_signature(token_string, jwk),
         :ok <- validate_claims(claims, registration, opts) do
      {:ok, claims}
    end
  end

  @doc false
  # Returns when a verified ID token stops being accepted, so its nonce
  # record can be deleted after that.
  @spec expires_at(map(), keyword()) :: DateTime.t()
  def expires_at(claims, opts) do
    DateTime.from_unix!(ceil(deadline(claims, opts)))
  end

  @doc false
  # Returns an ID token's claims without verifying it, so its registration can
  # be found before verification.
  @spec peek_claims(String.t()) :: {:ok, map()} | {:error, Exception.t()}
  def peek_claims(token_string) do
    with {:ok, payload} <- segment(token_string, 1), do: decode_object(payload)
  end

  # [RFC 7515 §5.2](https://www.rfc-editor.org/rfc/rfc7515#section-5.2)
  defp peek_header(token_string) do
    with {:ok, json} <- segment(token_string, 0),
         {:ok, header} <- decode_object(json) do
      header_with_algorithm(header)
    end
  end

  defp header_with_algorithm(%{"alg" => algorithm} = header) when is_binary(algorithm),
    do: {:ok, Map.put_new(header, "kid", nil)}

  defp header_with_algorithm(_header),
    do: {:error, SignatureInvalid.exception(spec_ref: "Sec §5.1.2")}

  # Returns the base64url-decoded header (index 0) or payload (index 1) of a
  # compact JWT.
  # [RFC 7519 §7.2](https://www.rfc-editor.org/rfc/rfc7519#section-7.2)
  defp segment(token_string, index) when is_binary(token_string) do
    with [_header, _payload, _signature] = segments <- String.split(token_string, "."),
         {:ok, json} <- Base.url_decode64(Enum.at(segments, index), padding: false) do
      {:ok, json}
    else
      _invalid -> {:error, invalid_json()}
    end
  end

  defp segment(_token, _index), do: {:error, invalid_json()}

  # [Sec §5.1.3 step 6; Cert §4.2] Only RS256 is permitted.
  defp validate_algorithm(%{"alg" => "RS256"}), do: :ok

  defp validate_algorithm(%{"alg" => alg}) do
    {:error,
     AlgorithmNotAllowed.exception(
       algorithm: alg,
       spec_ref: "Sec §5.1.3 step 6"
     )}
  end

  # [RFC 7515 §4.1.11](https://www.rfc-editor.org/rfc/rfc7515#section-4.1.11)
  # [RFC 7515 §5.2 step 5](https://www.rfc-editor.org/rfc/rfc7515#section-5.2)
  defp validate_critical_headers(%{"crit" => _critical}) do
    {:error, SignatureInvalid.exception(spec_ref: "RFC 7515 §4.1.11")}
  end

  defp validate_critical_headers(_header), do: :ok

  # [Sec §6.3] The kid MUST be present in the JWT header.
  defp extract_kid(%{"kid" => nil}) do
    {:error, KidMissing.exception(spec_ref: "Sec §6.3")}
  end

  defp extract_kid(%{"kid" => kid}) when is_binary(kid), do: {:ok, kid}

  # [RFC 7515 §4.1.4](https://www.rfc-editor.org/rfc/rfc7515#section-4.1.4)
  defp extract_kid(_header) do
    {:error, SignatureInvalid.exception(spec_ref: "RFC 7515 §4.1.4")}
  end

  # [Sec §5.1.3 step 1] Verify the signature using the platform's public key.
  defp verify_signature(token_string, jwk) do
    case JOSE.JWS.verify_strict(jwk, ["RS256"], token_string) do
      {true, payload, _jws} -> decode_object(payload)
      _invalid -> {:error, SignatureInvalid.exception(spec_ref: "Sec §5.1.3 step 1")}
    end
  end

  # [RFC 7519 §7.2 step 10](https://www.rfc-editor.org/rfc/rfc7519#section-7.2)
  defp decode_object(json) do
    case AppConfig.json_library!().decode(json) do
      {:ok, object} when is_map(object) -> {:ok, object}
      _invalid -> {:error, invalid_json()}
    end
  end

  defp invalid_json, do: InvalidJSON.exception(spec_ref: "RFC 7519 §7.2")

  # Validate claims per [Sec §5.1.3] steps 2-5, 7-9.
  defp validate_claims(claims, registration, opts) do
    with :ok <- validate_issuer(claims, registration),
         :ok <- validate_audience(claims, registration),
         :ok <- validate_issued_at(claims),
         :ok <- validate_expiration(claims, opts) do
      validate_nonce(claims)
    end
  end

  # [Sec §5.1.3 step 2] iss MUST match registration issuer.
  defp validate_issuer(%{"iss" => iss}, %Registration{issuer: expected}) when iss == expected,
    do: :ok

  defp validate_issuer(%{"iss" => iss}, %Registration{issuer: expected}) do
    {:error,
     IssuerMismatch.exception(
       expected: expected,
       actual: iss,
       spec_ref: "Sec §5.1.3 step 2"
     )}
  end

  # [Sec §5.1.2](https://www.imsglobal.org/spec/security/v1p0/#id-token)
  defp validate_issuer(_claims, _registration) do
    {:error, MissingClaim.exception(claim: "iss", spec_ref: "Sec §5.1.2")}
  end

  # [Sec §5.1.3 step 3] aud MUST contain client_id. The tool MUST reject
  # tokens containing additional audiences not trusted by the tool.
  # [Sec §5.1.3 step 5] If azp present, SHOULD match client_id.
  defp validate_audience(claims, %Registration{client_id: client_id}) do
    aud = Map.get(claims, "aud")
    azp = Map.get(claims, "azp")

    cond do
      # Single string audience
      is_binary(aud) and aud == client_id ->
        validate_azp(azp, client_id)

      # Array audience — must contain only client_id, no untrusted audiences
      is_list(aud) and aud == [client_id] ->
        validate_azp(azp, client_id)

      true ->
        {:error,
         AudienceMismatch.exception(
           claim: "aud",
           expected: client_id,
           actual: aud,
           spec_ref: "Sec §5.1.3 step 3"
         )}
    end
  end

  # [Sec §5.1.3 step 5] If azp is present, it SHOULD match client_id.
  defp validate_azp(nil, _client_id), do: :ok
  defp validate_azp(azp, client_id) when azp == client_id, do: :ok

  defp validate_azp(azp, client_id) do
    {:error,
     AudienceMismatch.exception(
       claim: "azp",
       expected: client_id,
       actual: azp,
       spec_ref: "Sec §5.1.3 step 5"
     )}
  end

  # [Sec §5.1.3 step 7] exp MUST be in the future (with clock skew tolerance).
  # [Sec §5.1.3 step 8] The Tool MAY reject tokens issued too long ago.
  defp validate_expiration(%{"exp" => exp} = claims, opts) when is_number(exp) do
    now = Keyword.get(opts, :now, System.system_time(:second))

    if now < deadline(claims, opts) do
      :ok
    else
      {:error, TokenExpired.exception(spec_ref: "Sec §5.1.3 steps 7-8")}
    end
  end

  # [Sec §5.1.2](https://www.imsglobal.org/spec/security/v1p0/#id-token)
  defp validate_expiration(%{"exp" => exp}, _opts) do
    {:error, InvalidClaim.exception(claim: "exp", value: exp, spec_ref: "Sec §5.1.2")}
  end

  defp validate_expiration(_claims, _opts) do
    {:error, MissingClaim.exception(claim: "exp", spec_ref: "Sec §5.1.2")}
  end

  defp deadline(%{"exp" => exp, "iat" => issued_at}, opts) do
    limit =
      case Keyword.get_lazy(opts, :max_token_age, &AppConfig.max_token_age/0) do
        :infinity -> exp
        max_token_age -> min(exp, issued_at + max_token_age)
      end

    limit + Keyword.get(opts, :clock_skew, @default_clock_skew)
  end

  # [Sec §5.1.2](https://www.imsglobal.org/spec/security/v1p0/#id-token)
  # [RFC 7519 §4.1.6](https://www.rfc-editor.org/rfc/rfc7519#section-4.1.6)
  defp validate_issued_at(%{"iat" => issued_at}) when is_number(issued_at), do: :ok

  defp validate_issued_at(%{"iat" => issued_at}) do
    {:error, InvalidClaim.exception(claim: "iat", value: issued_at, spec_ref: "Sec §5.1.2")}
  end

  defp validate_issued_at(_claims) do
    {:error, MissingClaim.exception(claim: "iat", spec_ref: "Sec §5.1.2")}
  end

  # [Sec §5.1.3 step 9] nonce MUST be present.
  defp validate_nonce(%{"nonce" => nonce}) when is_binary(nonce) and byte_size(nonce) > 0,
    do: :ok

  defp validate_nonce(_claims) do
    {:error, NonceMissing.exception(spec_ref: "Sec §5.1.3 step 9")}
  end
end
