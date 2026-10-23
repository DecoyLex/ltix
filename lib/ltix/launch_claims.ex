defmodule Ltix.LaunchClaims do
  @moduledoc """
  Structured representation of claims from an LTI launch JWT.

  Standard OIDC and LTI claims are mapped to named fields, while any
  unrecognized claims are available in `extensions`. Access claims through
  `context.claims` after a successful launch.

      {:ok, context} = Ltix.handle_callback(params, state)
      context.claims.issuer          #=> "https://platform.example.com"
      context.claims.target_link_uri #=> "https://tool.example.com/launch"
      Role.instructor?(context.claims.roles)  #=> true

  ## Fields

  ### Identity

    * `:issuer` - platform identifier (matches `iss` in the JWT)
    * `:subject` - user identifier on the platform (matches `sub`)
    * `:audience` - tool's `client_id` (string or list of strings)
    * `:nonce` - replay prevention token
    * `:authorized_party` - `azp` claim, present when audience is a list
    * `:expires_at` - JWT expiration as a Unix timestamp
    * `:issued_at` - JWT issue time as a Unix timestamp

  ### User profile

  Profile fields depend on platform consent and privacy settings.
  Any may be `nil`.

    * `:name` - full display name
    * `:given_name`, `:family_name`, `:middle_name` - name parts
    * `:email` - email address
    * `:picture` - profile image URL
    * `:locale` - user's locale (e.g., `"en"`)

  ### LTI launch

    * `:message_type` - launch type (e.g., `"LtiResourceLinkRequest"`,
      `"LtiDeepLinkingRequest"`)
    * `:version` - LTI version (e.g., `"1.3.0"`)
    * `:deployment_id` - identifies the specific tool installation
    * `:target_link_uri` - URL the tool should load
    * `:roles` - list of parsed `t:Ltix.LaunchClaims.Role.t/0` structs
    * `:unrecognized_roles` - role URIs that could not be parsed
    * `:role_scope_mentor` - list of user IDs this user mentors
    * `:custom` - custom properties set by the platform administrator

  ### Nested claims

    * `:context` - course or section (`t:Ltix.LaunchClaims.Context.t/0`)
    * `:resource_link` - the resource link the user launched
      (`t:Ltix.LaunchClaims.ResourceLink.t/0`)
    * `:launch_presentation` - display preferences
      (`t:Ltix.LaunchClaims.LaunchPresentation.t/0`)
    * `:tool_platform` - platform instance info
      (`t:Ltix.LaunchClaims.ToolPlatform.t/0`)
    * `:lis` - SIS integration identifiers (`t:Ltix.LaunchClaims.LIS.t/0`)

  ### Advantage service endpoints

  Present when the platform supports the corresponding service.
  Pass the parent `%LaunchContext{}` to the service's `authenticate/2`.

    * `:ags_endpoint` - Assignment and Grade Services
      (`t:Ltix.LaunchClaims.AGSEndpoint.t/0`)
    * `:memberships_endpoint` - Names and Roles Provisioning
      (`t:Ltix.LaunchClaims.MembershipsEndpoint.t/0`)
    * `:deep_linking_settings` - Deep Linking
      (`t:Ltix.LaunchClaims.DeepLinkingSettings.t/0`)

  ### Extensions

    * `:extensions` - map of unrecognized claim keys to their raw values.
      Register custom parsers via the `:claim_parsers` option in `from_json/2`
      or application config (`:ltix, Ltix.LaunchClaims, :claim_parsers`).

  ## Examples

      iex> {:ok, claims} = Ltix.LaunchClaims.from_json(%{"iss" => "https://example.com", "sub" => "user-1"})
      iex> claims.issuer
      "https://example.com"
  """

  alias Ltix.AppConfig
  alias Ltix.Errors
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Unknown.Unknown
  alias Ltix.Options

  alias Ltix.LaunchClaims.AGSEndpoint
  alias Ltix.LaunchClaims.ClaimHelpers
  alias Ltix.LaunchClaims.Context
  alias Ltix.LaunchClaims.DeepLinkingSettings
  alias Ltix.LaunchClaims.LaunchPresentation
  alias Ltix.LaunchClaims.LIS
  alias Ltix.LaunchClaims.MembershipsEndpoint
  alias Ltix.LaunchClaims.ResourceLink
  alias Ltix.LaunchClaims.Role
  alias Ltix.LaunchClaims.ToolPlatform

  defstruct [
    # OIDC Standard Claims [Sec §5.1.2](https://www.imsglobal.org/spec/security/v1p0/#id-token)
    :issuer,
    :subject,
    :audience,
    :expires_at,
    :issued_at,
    :nonce,
    :authorized_party,
    # OIDC Profile Claims [OIDC Core §5.1]
    :email,
    :name,
    :given_name,
    :family_name,
    :middle_name,
    :picture,
    :locale,
    # LTI Core Required Claims [Core §5.3](https://www.imsglobal.org/spec/lti/v1p3/#required-message-claims)
    :message_type,
    :version,
    :deployment_id,
    :target_link_uri,
    :role_scope_mentor,
    # Nested Claim Objects
    :context,
    :resource_link,
    :custom,
    :launch_presentation,
    :tool_platform,
    :lis,
    # Advantage Service Claims [Core §6.1](https://www.imsglobal.org/spec/lti/v1p3/#services-exposed-as-additional-claims)
    :ags_endpoint,
    :memberships_endpoint,
    :deep_linking_settings,
    # Fields with defaults (must come last)
    roles: [],
    unrecognized_roles: [],
    extensions: %{}
  ]

  @type t :: %__MODULE__{
          issuer: String.t() | nil,
          subject: String.t() | nil,
          audience: String.t() | [String.t()] | nil,
          expires_at: number() | nil,
          issued_at: number() | nil,
          nonce: String.t() | nil,
          authorized_party: String.t() | nil,
          email: String.t() | nil,
          name: String.t() | nil,
          given_name: String.t() | nil,
          family_name: String.t() | nil,
          middle_name: String.t() | nil,
          picture: String.t() | nil,
          locale: String.t() | nil,
          message_type: String.t() | nil,
          version: String.t() | nil,
          deployment_id: String.t() | nil,
          target_link_uri: String.t() | nil,
          roles: [Role.t()],
          unrecognized_roles: [String.t()],
          role_scope_mentor: [String.t()] | nil,
          context: Context.t() | nil,
          resource_link: ResourceLink.t() | nil,
          custom: map() | nil,
          launch_presentation: LaunchPresentation.t() | nil,
          tool_platform: ToolPlatform.t() | nil,
          lis: LIS.t() | nil,
          ags_endpoint: AGSEndpoint.t() | nil,
          memberships_endpoint: MembershipsEndpoint.t() | nil,
          deep_linking_settings: DeepLinkingSettings.t() | nil,
          extensions: %{optional(String.t()) => term()}
        }

  # --- Key Classification Tables ---

  # Table 1. OIDC standard claims [Sec §5.1.2](https://www.imsglobal.org/spec/security/v1p0/#id-token)
  @oidc_keys %{
    "iss" => :issuer,
    "sub" => :subject,
    "aud" => :audience,
    "exp" => :expires_at,
    "iat" => :issued_at,
    "nonce" => :nonce,
    "azp" => :authorized_party,
    "email" => :email,
    "name" => :name,
    "given_name" => :given_name,
    "family_name" => :family_name,
    "middle_name" => :middle_name,
    "picture" => :picture,
    "locale" => :locale
  }

  # Table 2. LTI-namespaced claims
  # [Core §5.3](https://www.imsglobal.org/spec/lti/v1p3/#required-message-claims),
  # [Core §5.4](https://www.imsglobal.org/spec/lti/v1p3/#optional-message-claims)
  @lti_claim_prefix "https://purl.imsglobal.org/spec/lti/claim/"

  @lti_keys %{
    "message_type" => :message_type,
    "version" => :version,
    "deployment_id" => :deployment_id,
    "target_link_uri" => :target_link_uri,
    "roles" => :roles,
    "role_scope_mentor" => :role_scope_mentor,
    "context" => :context,
    "resource_link" => :resource_link,
    "custom" => :custom,
    "launch_presentation" => :launch_presentation,
    "tool_platform" => :tool_platform,
    "lis" => :lis
  }

  # Scalar claims are keyed by claim name, so errors include the claim name.
  #
  # [standard-claims]:
  # https://openid.net/specs/openid-connect-core-1_0.html#StandardClaims
  # [required-message-claims]:
  # https://www.imsglobal.org/spec/lti/v1p3/#required-message-claims
  # [role-scope-mentor-claim]:
  # https://www.imsglobal.org/spec/lti/v1p3/#role-scope-mentor-claim
  #
  # [OIDC §2](https://openid.net/specs/openid-connect-core-1_0.html#IDToken)
  # [OIDC §5.1][standard-claims]
  # [Core §5.3][required-message-claims]
  # [Core §5.4.3][role-scope-mentor-claim]
  # [JWT §2](https://www.rfc-editor.org/rfc/rfc7519.html#section-2)
  @scalar_claim_schemas %{
    "iss" => Zoi.string() |> Zoi.nullish(),
    "sub" => Zoi.string() |> Zoi.nullish(),
    "aud" => Zoi.union([Zoi.string(), Zoi.list(Zoi.string())]) |> Zoi.nullish(),
    "exp" => Zoi.number() |> Zoi.nullish(),
    "iat" => Zoi.number() |> Zoi.nullish(),
    "nonce" => Zoi.string() |> Zoi.nullish(),
    "azp" => Zoi.string() |> Zoi.nullish(),
    "email" => Zoi.string() |> ClaimHelpers.optional(),
    "name" => Zoi.string() |> ClaimHelpers.optional(),
    "given_name" => Zoi.string() |> ClaimHelpers.optional(),
    "family_name" => Zoi.string() |> ClaimHelpers.optional(),
    "middle_name" => Zoi.string() |> ClaimHelpers.optional(),
    "picture" => Zoi.string() |> ClaimHelpers.optional(),
    "locale" => Zoi.string() |> ClaimHelpers.optional(),
    "message_type" => Zoi.string() |> Zoi.nullish(),
    "version" => Zoi.string() |> Zoi.nullish(),
    "deployment_id" => Zoi.string() |> Zoi.nullish(),
    "target_link_uri" => Zoi.string() |> Zoi.nullish(),
    "role_scope_mentor" => Zoi.list(Zoi.string()) |> ClaimHelpers.optional()
  }
  @scalar_schema Zoi.map(@scalar_claim_schemas)
  @scalar_claims @oidc_keys
                 |> Map.merge(@lti_keys)
                 |> Map.take(Map.keys(@scalar_claim_schemas))

  # Table 3. Service endpoint claims [Core §6.1](https://www.imsglobal.org/spec/lti/v1p3/#services-exposed-as-additional-claims)
  @service_keys %{
    "https://purl.imsglobal.org/spec/lti-ags/claim/endpoint" => :ags_endpoint,
    "https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice" => :memberships_endpoint,
    "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings" => :deep_linking_settings
  }

  @options_schema Zoi.keyword(
                    [
                      claim_parsers: Zoi.map(Zoi.string(), Zoi.any()),
                      role_parsers: Zoi.map(Zoi.string(), Zoi.any())
                    ],
                    unrecognized_keys: :error
                  )

  @nested_claims %{
    context: {ClaimHelpers.optional(Context.schema()), "context"},
    resource_link: {ResourceLink.schema(), "resource_link"},
    launch_presentation:
      {ClaimHelpers.optional(LaunchPresentation.schema()), "launch_presentation"},
    tool_platform: {ClaimHelpers.optional(ToolPlatform.schema()), "tool_platform"},
    lis: {ClaimHelpers.optional(LIS.schema()), "lis"},
    ags_endpoint:
      {ClaimHelpers.optional(AGSEndpoint.schema()),
       "https://purl.imsglobal.org/spec/lti-ags/claim/endpoint"},
    memberships_endpoint:
      {ClaimHelpers.optional(MembershipsEndpoint.schema()),
       "https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice"},
    deep_linking_settings: {DeepLinkingSettings.schema(), "deep_linking_settings"}
  }

  # --- Public API ---

  @doc """
  Parse a JWT body map into a `%LaunchClaims{}` struct.

  ## Options

  - `:claim_parsers` - Map of claim keys to parsers, each a module
    implementing `Ltix.LaunchClaims.Parser` or a 1-arity function. Standard
    claim keys replace built-in parsers. Each parser receives the raw value
    and must return `{:ok, parsed}` or `{:error, reason}`. A parser's
    `{:error, reason}` is returned as `Ltix.Errors.Invalid.InvalidClaim`,
    unless `reason` is already an Ltix error. Per-call parsers override
    application config.
  - `:role_parsers` - Map of role URI prefixes to parser functions for
    parsing the `roles` claim. Each parser receives a role URI and must
    return a `{:ok, t:Ltix.LaunchClaims.Role.t/0}` struct or `:error`. Per-call
    parsers override application config.

  ## Examples

      iex> {:ok, claims} = Ltix.LaunchClaims.from_json(%{
      ...>   "iss" => "https://platform.example.com",
      ...>   "https://purl.imsglobal.org/spec/lti/claim/message_type" => "LtiResourceLinkRequest"
      ...> })
      iex> {claims.issuer, claims.message_type}
      {"https://platform.example.com", "LtiResourceLinkRequest"}
  """
  @spec from_json(map(), keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(json, opts \\ []) when is_map(json) do
    opts = Options.parse!(opts, @options_schema)
    claim_parsers = resolve_claim_parsers(opts)
    role_parsers = Keyword.get(opts, :role_parsers, %{})
    {configured_claims, builtin_claims} = Map.split(json, Map.keys(claim_parsers))
    {fields, extensions} = classify_keys(builtin_claims)

    with {:ok, configured_claims} <- parse_configured_claims(configured_claims, claim_parsers),
         {:ok, fields} <- parse_scalar_claims(fields),
         {:ok, fields} <- parse_nested_claims(fields, json[@lti_claim_prefix <> "message_type"]),
         {:ok, fields} <- parse_roles(fields, role_parsers) do
      {configured_fields, configured_extensions} = classify_keys(configured_claims)

      parsed_fields =
        fields
        |> Map.merge(configured_fields)
        |> Map.put(:extensions, Map.merge(extensions, configured_extensions))

      {:ok, struct!(__MODULE__, parsed_fields)}
    end
  end

  # --- Private Implementation ---

  defp classify_keys(json) do
    Enum.reduce(json, {%{}, %{}}, fn {key, value}, {fields, extensions} ->
      case classify_key(key) do
        {:oidc, field} -> {Map.put(fields, field, value), extensions}
        {:lti, field} -> {Map.put(fields, field, value), extensions}
        {:service, field} -> {Map.put(fields, field, value), extensions}
        {:extension, ext_key} -> {fields, Map.put(extensions, ext_key, value)}
      end
    end)
  end

  defp classify_key(key) do
    cond do
      Map.has_key?(@oidc_keys, key) ->
        {:oidc, Map.fetch!(@oidc_keys, key)}

      Map.has_key?(@service_keys, key) ->
        {:service, Map.fetch!(@service_keys, key)}

      String.starts_with?(key, @lti_claim_prefix) ->
        suffix = String.replace_leading(key, @lti_claim_prefix, "")

        case Map.fetch(@lti_keys, suffix) do
          {:ok, field} -> {:lti, field}
          :error -> {:extension, key}
        end

      true ->
        {:extension, key}
    end
  end

  defp parse_scalar_claims(fields) do
    scalars =
      for {claim, field} <- @scalar_claims, Map.has_key?(fields, field), into: %{} do
        {claim, Map.fetch!(fields, field)}
      end

    case ClaimHelpers.from_json(@scalar_schema, scalars, nil) do
      {:ok, parsed} ->
        {:ok,
         Map.merge(
           fields,
           Map.new(parsed, fn {claim, value} -> {@scalar_claims[claim], value} end)
         )}

      {:error, _error} = error ->
        error
    end
  end

  defp parse_nested_claims(fields, message_type) do
    Enum.reduce_while(@nested_claims, {:ok, fields}, fn {field, {schema, prefix}}, {:ok, acc} ->
      schema = nested_schema(field, schema, message_type)

      acc
      |> Map.get(field)
      |> parse_nested_field(field, {schema, prefix}, acc)
    end)
  end

  defp nested_schema(:resource_link, schema, "LtiDeepLinkingRequest"),
    do: ClaimHelpers.optional(schema)

  defp nested_schema(:deep_linking_settings, schema, "LtiResourceLinkRequest"),
    do: ClaimHelpers.optional(schema)

  defp nested_schema(_field, schema, _message_type), do: schema

  defp parse_nested_field(value, field, _schema, acc) when value in [nil, :null],
    do: {:cont, {:ok, Map.put(acc, field, nil)}}

  defp parse_nested_field(raw_value, field, {schema, prefix}, acc) do
    case ClaimHelpers.from_json(schema, raw_value, prefix) do
      {:ok, parsed} -> {:cont, {:ok, Map.put(acc, field, parsed)}}
      {:error, _} = error -> {:halt, error}
    end
  end

  # [Core §5.3.7](https://www.imsglobal.org/spec/lti/v1p3/#roles-claim)
  defp parse_roles(fields, role_parsers) do
    case Map.get(fields, :roles) do
      nil ->
        {:ok, fields}

      role_uris when is_list(role_uris) ->
        if Enum.all?(role_uris, &is_binary/1) do
          {parsed, unrecognized} = Role.parse_all(role_uris, role_parsers: role_parsers)

          {:ok,
           fields
           |> Map.put(:roles, parsed)
           |> Map.put(:unrecognized_roles, unrecognized)}
        else
          invalid_roles(role_uris)
        end

      role_uris ->
        invalid_roles(role_uris)
    end
  end

  defp invalid_roles(role_uris) do
    {:error,
     InvalidClaim.exception(
       claim: "roles",
       value: role_uris,
       message: "must be an array of strings"
     )}
  end

  defp parse_configured_claims(claims, parsers) do
    Enum.reduce_while(claims, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case Map.fetch!(parsers, key).(value) do
        {:ok, parsed} ->
          {:cont, {:ok, Map.put(acc, key, parsed)}}

        {:error, reason} ->
          {:halt, {:error, claim_parser_error(key, value, reason)}}

        other ->
          {:halt,
           {:error,
            Unknown.exception(
              error:
                "Claim parser for #{key} returned #{inspect(other)}, " <>
                  "expected {:ok, value} or {:error, reason}"
            )}}
      end
    end)
  end

  # Ltix errors are returned unchanged. Any other reason becomes an invalid claim error.
  defp claim_parser_error(key, value, reason) do
    if Errors.ltix_error?(reason) do
      reason
    else
      InvalidClaim.exception(claim: key, value: value, message: reason_message(reason))
    end
  end

  defp reason_message(reason) when is_binary(reason), do: reason
  defp reason_message(reason) when is_exception(reason), do: Exception.message(reason)
  defp reason_message(reason), do: inspect(reason)

  defp resolve_claim_parsers(opts) do
    configured_parsers = AppConfig.claims_parsers!()

    configured_parsers
    |> Map.merge(Keyword.get(opts, :claim_parsers, %{}))
    |> Map.new(fn {key, parser} -> {key, Options.parser_function!(parser, :claim_parsers)} end)
  end
end
