defmodule Ltix.LaunchClaims do
  @moduledoc """
  The structured representation of claims from an LTI launch JWT.

  Standard OIDC and LTI claims are mapped to named fields, while any
  unrecognized claims are available in `extensions`.

  ## Examples

      iex> {:ok, claims} = Ltix.LaunchClaims.from_json(%{"iss" => "https://example.com", "sub" => "user-1"})
      iex> claims.issuer
      "https://example.com"
  """

  alias Ltix.LaunchClaims.{
    AgsEndpoint,
    Context,
    DeepLinkingSettings,
    LaunchPresentation,
    Lis,
    MembershipsEndpoint,
    ResourceLink,
    Role,
    ToolPlatform
  }

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
          expires_at: integer() | nil,
          issued_at: integer() | nil,
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
          lis: Lis.t() | nil,
          ags_endpoint: AgsEndpoint.t() | nil,
          memberships_endpoint: MembershipsEndpoint.t() | nil,
          deep_linking_settings: DeepLinkingSettings.t() | nil,
          extensions: %{optional(String.t()) => term()}
        }

  # --- Key Classification Tables ---

  # Table 1: OIDC standard claims [Sec §5.1.2](https://www.imsglobal.org/spec/security/v1p0/#id-token)
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

  # Table 2: LTI-namespaced claims
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

  # Table 3: Service endpoint claims [Core §6.1](https://www.imsglobal.org/spec/lti/v1p3/#services-exposed-as-additional-claims)
  @service_keys %{
    "https://purl.imsglobal.org/spec/lti-ags/claim/endpoint" => :ags_endpoint,
    "https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice" => :memberships_endpoint,
    "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings" => :deep_linking_settings
  }

  # Nested claim fields → parser functions
  @nested_parsers %{
    context: &Context.from_json/1,
    resource_link: &ResourceLink.from_json/1,
    launch_presentation: &LaunchPresentation.from_json/1,
    tool_platform: &ToolPlatform.from_json/1,
    lis: &Lis.from_json/1,
    ags_endpoint: &AgsEndpoint.from_json/1,
    memberships_endpoint: &MembershipsEndpoint.from_json/1,
    deep_linking_settings: &DeepLinkingSettings.from_json/1
  }

  # --- Public API ---

  @doc """
  Parse a JWT body map into a `%LaunchClaims{}` struct.

  ## Options

  - `:parsers` — Map of extension claim keys to parser functions.
    Each parser receives the raw value and must return `{:ok, parsed}` or
    `{:error, reason}`. Per-call parsers override application config.

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
    extension_parsers = resolve_extension_parsers(opts)
    {fields, extensions} = classify_keys(json)

    with {:ok, fields} <- parse_nested_claims(fields),
         {:ok, fields} <- parse_roles(fields),
         {:ok, extensions} <- parse_extensions(extensions, extension_parsers) do
      {:ok, struct!(__MODULE__, Map.put(fields, :extensions, extensions))}
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

  defp parse_nested_claims(fields) do
    Enum.reduce_while(@nested_parsers, {:ok, fields}, fn {field, parser}, {:ok, acc} ->
      acc
      |> Map.get(field)
      |> parse_nested_field(field, parser, acc)
    end)
  end

  defp parse_nested_field(nil, _field, _parser, acc), do: {:cont, {:ok, acc}}

  defp parse_nested_field(raw_value, field, parser, acc) do
    case parser.(raw_value) do
      {:ok, parsed} -> {:cont, {:ok, Map.put(acc, field, parsed)}}
      {:error, _} = error -> {:halt, error}
    end
  end

  defp parse_roles(fields) do
    case Map.get(fields, :roles) do
      nil ->
        {:ok, fields}

      role_uris when is_list(role_uris) ->
        {parsed, unrecognized} = Role.parse_all(role_uris)

        {:ok,
         fields
         |> Map.put(:roles, parsed)
         |> Map.put(:unrecognized_roles, unrecognized)}
    end
  end

  defp parse_extensions(extensions, parsers) when map_size(parsers) == 0 do
    {:ok, extensions}
  end

  defp parse_extensions(extensions, parsers) do
    Enum.reduce_while(extensions, {:ok, extensions}, fn {key, value}, {:ok, acc} ->
      parse_extension_field(key, value, parsers, acc)
    end)
  end

  defp parse_extension_field(key, value, parsers, acc) do
    case Map.fetch(parsers, key) do
      {:ok, parser} ->
        case parser.(value) do
          {:ok, parsed} -> {:cont, {:ok, Map.put(acc, key, parsed)}}
          {:error, _} = error -> {:halt, error}
        end

      :error ->
        {:cont, {:ok, acc}}
    end
  end

  defp resolve_extension_parsers(opts) do
    config_parsers = Application.get_env(:ltix, :launch_claim_parsers, %{})
    call_parsers = Keyword.get(opts, :parsers, %{})
    Map.merge(config_parsers, call_parsers)
  end
end
