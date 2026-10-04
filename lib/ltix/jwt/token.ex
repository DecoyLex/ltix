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
  8. Validate `exp` is not in the past (with configurable clock skew)
  9. Validate `iat` is a NumericDate
  10. Validate `nonce` is present

  ## Options

    * `:clock_skew` — seconds of tolerance for `exp` validation (default: `5`)
    * `:now` — override current time in unix seconds (useful for testing)
    * `:req_options` — extra options passed through to `Ltix.JWT.KeySet`
    * `:jwks_cache` — cache module passed through to `Ltix.JWT.KeySet`
  """

  alias Ltix.Errors.Invalid.InvalidClaim
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
                      now: Zoi.integer(),
                      req_options: Zoi.keyword(Zoi.any()),
                      jwks_cache: Zoi.module()
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
           KeySet.get_key(registration, kid, Keyword.take(opts, [:req_options, :jwks_cache])),
         {:ok, claims} <- verify_signature(token_string, jwk),
         :ok <- validate_claims(claims, registration, opts) do
      {:ok, claims}
    end
  end

  # [RFC 7515 §5.2](https://www.rfc-editor.org/rfc/rfc7515#section-5.2)
  defp peek_header(token_string) when is_binary(token_string) do
    with [encoded_header, _payload, _signature] <- String.split(token_string, "."),
         {:ok, header_json} <- Base.url_decode64(encoded_header, padding: false),
         {:ok, %{"alg" => algorithm} = header} when is_binary(algorithm) <-
           Ltix.AppConfig.json_library!().decode(header_json) do
      {:ok, Map.put_new(header, "kid", nil)}
    else
      _invalid -> {:error, SignatureInvalid.exception(spec_ref: "Sec §5.1.2")}
    end
  end

  defp peek_header(_token) do
    {:error, SignatureInvalid.exception(spec_ref: "Sec §5.1.2")}
  end

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
    case JOSE.JWT.verify_strict(jwk, ["RS256"], token_string) do
      {true, %JOSE.JWT{fields: claims}, _jws} when is_map(claims) ->
        {:ok, claims}

      _invalid ->
        {:error, SignatureInvalid.exception(spec_ref: "Sec §5.1.3 step 1")}
    end
  end

  # Validate claims per [Sec §5.1.3] steps 2-5, 7-9.
  defp validate_claims(claims, registration, opts) do
    with :ok <- validate_issuer(claims, registration),
         :ok <- validate_audience(claims, registration),
         :ok <- validate_expiration(claims, opts),
         :ok <- validate_issued_at(claims) do
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
       expected: client_id,
       actual: azp,
       spec_ref: "Sec §5.1.3 step 5"
     )}
  end

  # [Sec §5.1.3 step 7] exp MUST be in the future (with clock skew tolerance).
  defp validate_expiration(claims, opts) do
    exp = Map.get(claims, "exp")
    clock_skew = Keyword.get(opts, :clock_skew, @default_clock_skew)
    now = Keyword.get(opts, :now, System.system_time(:second))

    if is_number(exp) and now < exp + clock_skew do
      :ok
    else
      {:error, TokenExpired.exception(spec_ref: "Sec §5.1.3 step 7")}
    end
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
