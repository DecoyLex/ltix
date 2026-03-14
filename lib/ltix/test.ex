defmodule Ltix.Test do
  @moduledoc """
  Helpers for testing applications that use Ltix.

  Reduces LTI test setup to a single call. Instead of manually generating
  RSA keys, building JWKS payloads, creating registrations and deployments,
  starting storage adapters, and stubbing HTTP endpoints, call
  `setup_platform!/1`:

      setup do
        %{platform: Ltix.Test.setup_platform!()}
      end

  The in-memory storage adapter state is scoped to the calling process
  via the process dictionary, so async tests are safe without any cleanup.

  ## Configuration

  If your app's controllers call `Ltix.handle_login/3` or
  `Ltix.handle_callback/3` without passing `:storage_adapter` in opts
  (relying on application config), add this to `config/test.exs`:

      config :ltix, storage_adapter: Ltix.Test.StorageAdapter

  This is safe for `async: true` tests — each test process gets its own
  in-memory storage via the process dictionary.

  ## Integration tests (full OIDC flow)

      test "successful launch", %{platform: platform} do
        login_params = Ltix.Test.login_params(platform)

        {:ok, login_result} =
          Ltix.handle_login(login_params, "https://tool.example.com/launch")

        nonce = Ltix.Test.extract_nonce(login_result.redirect_uri)

        launch_params = Ltix.Test.launch_params(platform,
          nonce: nonce,
          state: login_result.state,
          roles: [:instructor]
        )

        {:ok, context} =
          Ltix.handle_callback(launch_params, login_result.state,
            Ltix.Test.callback_opts(platform)
          )

        assert Ltix.LaunchClaims.Role.instructor?(context.claims.roles)
      end

  ## Unit tests (direct context construction)

      test "instructor authorization", %{platform: platform} do
        context = Ltix.Test.build_launch_context(platform,
          roles: [:instructor],
          name: "Jane Smith"
        )

        assert MyApp.authorize(context) == :instructor
      end
  """

  alias Ltix.Deployment
  alias Ltix.LaunchClaims
  alias Ltix.LaunchClaims.AgsEndpoint
  alias Ltix.LaunchClaims.Context
  alias Ltix.LaunchClaims.DeepLinkingSettings
  alias Ltix.LaunchClaims.MembershipsEndpoint
  alias Ltix.LaunchClaims.ResourceLink
  alias Ltix.LaunchClaims.Role
  alias Ltix.LaunchContext
  alias Ltix.Registration
  alias Ltix.Test.Platform
  alias Ltix.Test.StorageAdapter

  # --- Platform Setup ---

  @doc """
  Set up a simulated LTI platform in one call.

  Generates RSA keys, creates a registration and deployment, starts the
  in-memory storage adapter, and stubs the JWKS HTTP endpoint.

  ## Options

    * `:issuer` — platform issuer URL (default: `"https://platform.example.com"`)
    * `:client_id` — OAuth client ID (default: `"tool-client-id"`)
    * `:deployment_id` — deployment identifier (default: `"deployment-001"`)
  """
  @spec setup_platform!(keyword()) :: Platform.t()
  def setup_platform!(opts \\ []) do
    issuer = Keyword.get(opts, :issuer, "https://platform.example.com")
    client_id = Keyword.get(opts, :client_id, "tool-client-id")
    deployment_id = Keyword.get(opts, :deployment_id, "deployment-001")

    {private_key, public_key, kid} = generate_rsa_key_pair()
    jwks = build_jwks([public_key])

    # Tool's own key pair for signing client assertions (separate from platform keys)
    {tool_private, _tool_public} = Ltix.JWK.generate_key_pair()

    # Unique JWKS URI per call for async test safety
    suffix = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)

    {:ok, registration} =
      Registration.new(%{
        issuer: issuer,
        client_id: client_id,
        auth_endpoint: "#{issuer}/auth",
        jwks_uri: "#{issuer}/.well-known/jwks-#{suffix}.json",
        token_endpoint: "#{issuer}/token",
        tool_jwk: tool_private
      })

    {:ok, deployment} = Deployment.new(deployment_id)

    {:ok, pid} =
      StorageAdapter.start_link(
        registrations: [registration],
        deployments: [deployment]
      )

    StorageAdapter.set_pid(pid)

    Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("cache-control", "max-age=300")
      |> Req.Test.json(jwks)
    end)

    %Platform{
      registration: registration,
      deployment: deployment,
      private_key: private_key,
      public_key: public_key,
      kid: kid,
      jwks: jwks
    }
  end

  # --- Request Builders ---

  @doc """
  Build POST params for `Ltix.handle_login/3`.

  ## Options

    * `:login_hint` — login hint value (default: `"user-hint"`)
    * `:target_link_uri` — launch URL (default: `"https://tool.example.com/launch"`)
  """
  @spec login_params(Platform.t(), keyword()) :: map()
  def login_params(%Platform{} = platform, opts \\ []) do
    %{
      "iss" => platform.registration.issuer,
      "login_hint" => Keyword.get(opts, :login_hint, "user-hint"),
      "target_link_uri" => Keyword.get(opts, :target_link_uri, "https://tool.example.com/launch")
    }
  end

  @doc """
  Build POST params for `Ltix.handle_callback/3`.

  Signs a JWT with the platform's private key and returns
  `%{"id_token" => jwt, "state" => state}`.

  ## Required options

    * `:nonce` — the nonce from the login redirect (use `extract_nonce/1`)
    * `:state` — the state from the login result

  ## Optional

    * `:message_type` — `:deep_linking` for Deep Linking requests
      (default: resource link)
    * `:roles` — list of role atoms (e.g., `[:instructor]`), `%Role{}` structs,
      or URI strings
    * `:subject` — user identifier (default: `"user-12345"`)
    * `:name`, `:email`, `:given_name`, `:family_name` — user PII
    * `:context` — map with `:id`, `:label`, `:title` keys
    * `:resource_link` — map with `:id`, `:title` keys
    * `:deep_linking_settings` — map of DL settings (used when
      `message_type: :deep_linking`)
    * `:claims` — raw claim map merged last (for advanced overrides)
  """
  @spec launch_params(Platform.t(), keyword()) :: map()
  def launch_params(%Platform{} = platform, opts) do
    nonce = Keyword.fetch!(opts, :nonce)
    state = Keyword.fetch!(opts, :state)

    claims = build_claims(platform, nonce, opts)
    id_token = mint_id_token(claims, platform.private_key, kid: platform.kid)

    %{"id_token" => id_token, "state" => state}
  end

  @doc """
  Extract the nonce from a login redirect URI.

      {:ok, result} = Ltix.handle_login(params, redirect_uri)
      nonce = Ltix.Test.extract_nonce(result.redirect_uri)
  """
  @spec extract_nonce(String.t()) :: String.t()
  def extract_nonce(redirect_uri) do
    redirect_uri
    |> URI.parse()
    |> Map.get(:query)
    |> URI.decode_query()
    |> Map.fetch!("nonce")
  end

  @doc """
  Options for `Ltix.handle_login/3` that work with `setup_platform!/1`.

      Ltix.handle_login(params, redirect_uri, Ltix.Test.login_opts(platform))
  """
  @spec login_opts(Platform.t()) :: keyword()
  def login_opts(%Platform{}) do
    [storage_adapter: StorageAdapter]
  end

  @doc """
  Options for `Ltix.handle_callback/3` that work with `setup_platform!/1`.

      Ltix.handle_callback(params, state, Ltix.Test.callback_opts(platform))
  """
  @spec callback_opts(Platform.t()) :: keyword()
  def callback_opts(%Platform{}) do
    [storage_adapter: StorageAdapter, req_options: [plug: {Req.Test, Ltix.JWT.KeySet}]]
  end

  # --- Direct Context Construction ---

  @doc """
  Build a `%LaunchContext{}` directly for unit testing.

  Constructs the context without going through the OIDC flow.
  Accepts the same claim options as `launch_params/2` (except `:nonce`
  and `:state`, which are not needed).

      context = Ltix.Test.build_launch_context(platform,
        roles: [:instructor, :teaching_assistant],
        name: "Jane Smith",
        context: %{id: "course-1", title: "Elixir 101"}
      )

  For Deep Linking contexts, pass `message_type: :deep_linking`:

      context = Ltix.Test.build_launch_context(platform,
        message_type: :deep_linking,
        deep_linking_settings: %{accept_types: ["ltiResourceLink"]}
      )
  """
  @spec build_launch_context(Platform.t(), keyword()) :: LaunchContext.t()
  def build_launch_context(%Platform{} = platform, opts \\ []) do
    claims = build_launch_claims(platform, opts)

    %LaunchContext{
      claims: claims,
      registration: platform.registration,
      deployment: platform.deployment
    }
  end

  defp build_launch_claims(platform, opts) do
    parsed_roles =
      opts
      |> Keyword.get(:roles, [])
      |> resolve_roles()

    message_type =
      opts
      |> Keyword.get(:message_type)
      |> normalize_message_type()

    base_claims = %LaunchClaims{
      issuer: platform.registration.issuer,
      audience: platform.registration.client_id,
      version: "1.3.0",
      deployment_id: platform.deployment.deployment_id,
      target_link_uri: Keyword.get(opts, :target_link_uri, "https://tool.example.com/launch"),
      roles: parsed_roles,
      name: Keyword.get(opts, :name),
      email: Keyword.get(opts, :email),
      given_name: Keyword.get(opts, :given_name),
      family_name: Keyword.get(opts, :family_name),
      context: build_context(Keyword.get(opts, :context)),
      memberships_endpoint: build_memberships_endpoint(Keyword.get(opts, :memberships_endpoint)),
      ags_endpoint: build_ags_endpoint(Keyword.get(opts, :ags_endpoint))
    }

    apply_message_type_claims(message_type, base_claims, opts)
  end

  defp apply_message_type_claims("LtiDeepLinkingRequest", claims, opts) do
    %{
      claims
      | message_type: "LtiDeepLinkingRequest",
        subject: Keyword.get(opts, :subject),
        deep_linking_settings:
          build_deep_linking_settings(Keyword.get(opts, :deep_linking_settings))
    }
  end

  defp apply_message_type_claims(_type, claims, opts) do
    %{
      claims
      | message_type: "LtiResourceLinkRequest",
        subject: Keyword.get(opts, :subject, "user-12345"),
        resource_link: build_resource_link(Keyword.get(opts, :resource_link))
    }
  end

  # --- Lower-Level Helpers ---

  @doc """
  Verify a Deep Linking response JWT signed by the tool.

  Decodes the JWT using the tool's public key (derived from
  `registration.tool_jwk`) and returns the parsed claims on success.

      {:ok, response} = Ltix.DeepLinking.build_response(context, items)
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, response.jwt)
      assert claims["https://purl.imsglobal.org/spec/lti/claim/message_type"] ==
               "LtiDeepLinkingResponse"
  """
  @spec verify_deep_linking_response(Platform.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def verify_deep_linking_response(%Platform{} = platform, jwt) do
    public_key = JOSE.JWK.to_public(platform.registration.tool_jwk)

    case JOSE.JWT.verify_strict(public_key, ["RS256"], jwt) do
      {true, %JOSE.JWT{fields: claims}, _jws} -> {:ok, claims}
      {false, _jwt, _jws} -> {:error, :signature_invalid}
    end
  end

  @doc """
  Generate an RSA key pair for testing.

  Returns `{private_jwk, public_jwk, kid}`. Delegates to `Ltix.JWK.generate_key_pair/0`.
  """
  @spec generate_rsa_key_pair() :: {JOSE.JWK.t(), JOSE.JWK.t(), String.t()}
  def generate_rsa_key_pair do
    {private_jwk, public_jwk} = Ltix.JWK.generate_key_pair()
    {_kty, fields} = JOSE.JWK.to_map(private_jwk)
    {private_jwk, public_jwk, fields["kid"]}
  end

  @doc """
  Build a JWKS map from a list of public JWKs.

  Returns `%{"keys" => [...]}`. Delegates to `Ltix.JWK.to_jwks/1`.
  """
  @spec build_jwks([JOSE.JWK.t()]) :: map()
  def build_jwks(public_keys) do
    Ltix.JWK.to_jwks(public_keys)
  end

  @doc """
  Sign claims as a JWT.

  ## Options

    * `:kid` — key ID for the JWT header
    * `:alg` — algorithm (default: `"RS256"`)
  """
  @spec mint_id_token(map(), JOSE.JWK.t(), keyword()) :: String.t()
  def mint_id_token(claims, private_jwk, opts \\ []) do
    kid = Keyword.get(opts, :kid)
    alg = Keyword.get(opts, :alg, "RS256")

    jws_fields =
      then(%{"alg" => alg}, fn fields ->
        if kid, do: Map.put(fields, "kid", kid), else: fields
      end)

    jws = JOSE.JWS.from_map(jws_fields)
    jwt = JOSE.JWT.from_map(claims)

    {_meta, token} = JOSE.JWS.compact(JOSE.JWT.sign(private_jwk, jws, jwt))

    token
  end

  @doc """
  Return a complete, valid LTI claim set.

  Caller can override individual claims via the `overrides` map.
  """
  @spec valid_lti_claims(map()) :: map()
  def valid_lti_claims(overrides \\ %{}) do
    now = System.system_time(:second)

    base = %{
      "iss" => "https://platform.example.com",
      "sub" => "user-12345",
      "aud" => "tool-client-id",
      "exp" => now + 3600,
      "iat" => now,
      "nonce" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false),
      "https://purl.imsglobal.org/spec/lti/claim/message_type" => "LtiResourceLinkRequest",
      "https://purl.imsglobal.org/spec/lti/claim/version" => "1.3.0",
      "https://purl.imsglobal.org/spec/lti/claim/deployment_id" => "deployment-001",
      "https://purl.imsglobal.org/spec/lti/claim/target_link_uri" =>
        "https://tool.example.com/launch",
      "https://purl.imsglobal.org/spec/lti/claim/roles" => [
        "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"
      ],
      "https://purl.imsglobal.org/spec/lti/claim/resource_link" => %{
        "id" => "resource-link-001",
        "title" => "Example Assignment"
      }
    }

    Map.merge(base, overrides)
  end

  # --- Private ---

  @lti_claim_prefix "https://purl.imsglobal.org/spec/lti/claim/"
  @dl_settings_claim_key "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings"

  defp build_claims(platform, nonce, opts) do
    now = System.system_time(:second)

    base = %{
      "iss" => platform.registration.issuer,
      "aud" => platform.registration.client_id,
      "exp" => now + 3600,
      "iat" => now,
      "nonce" => nonce,
      (@lti_claim_prefix <> "version") => "1.3.0",
      (@lti_claim_prefix <> "deployment_id") => platform.deployment.deployment_id,
      (@lti_claim_prefix <> "target_link_uri") =>
        Keyword.get(opts, :target_link_uri, "https://tool.example.com/launch")
    }

    message_type =
      opts
      |> Keyword.get(:message_type)
      |> normalize_message_type()

    base
    |> apply_message_type_jwt_claims(message_type, opts)
    |> maybe_put("name", Keyword.get(opts, :name))
    |> maybe_put("email", Keyword.get(opts, :email))
    |> maybe_put("given_name", Keyword.get(opts, :given_name))
    |> maybe_put("family_name", Keyword.get(opts, :family_name))
    |> maybe_put_lti("context", build_context_claim(Keyword.get(opts, :context)))
    |> merge_overrides(Keyword.get(opts, :claims, %{}))
  end

  defp apply_message_type_jwt_claims(claims, "LtiDeepLinkingRequest", opts) do
    claims
    |> Map.put(@lti_claim_prefix <> "message_type", "LtiDeepLinkingRequest")
    |> Map.put(
      @dl_settings_claim_key,
      build_deep_linking_settings_claim(Keyword.get(opts, :deep_linking_settings))
    )
    |> maybe_put("sub", Keyword.get(opts, :subject))
    |> maybe_put_lti("roles", maybe_resolve_roles(Keyword.get(opts, :roles)))
  end

  defp apply_message_type_jwt_claims(claims, _message_type, opts) do
    claims
    |> Map.put(@lti_claim_prefix <> "message_type", "LtiResourceLinkRequest")
    |> Map.put("sub", Keyword.get(opts, :subject, "user-12345"))
    |> Map.put(
      @lti_claim_prefix <> "roles",
      resolve_role_uris(Keyword.get(opts, :roles, [:instructor]))
    )
    |> Map.put(
      @lti_claim_prefix <> "resource_link",
      build_resource_link_claim(Keyword.get(opts, :resource_link))
    )
  end

  defp resolve_roles(roles) do
    Enum.map(roles, fn
      %Role{} = role -> role
      atom when is_atom(atom) -> Role.from_atom(atom)
      uri when is_binary(uri) -> resolve_role_uri(uri)
    end)
  end

  defp resolve_role_uri(uri) do
    case Role.parse(uri) do
      {:ok, role} -> role
      :error -> raise ArgumentError, "could not resolve role URI: #{inspect(uri)}"
    end
  end

  defp resolve_role_uris(roles) do
    Enum.map(roles, fn
      %Role{} = role ->
        case Role.to_uri(role) do
          {:ok, uri} -> uri
          :error -> raise ArgumentError, "could not resolve role to URI: #{inspect(role)}"
        end

      atom when is_atom(atom) ->
        Role.from_atom(atom).uri

      uri when is_binary(uri) ->
        uri
    end)
  end

  defp build_memberships_endpoint(nil), do: nil

  defp build_memberships_endpoint(%MembershipsEndpoint{} = ep), do: ep

  defp build_memberships_endpoint(url) when is_binary(url) do
    %MembershipsEndpoint{context_memberships_url: url, service_versions: ["2.0"]}
  end

  defp build_memberships_endpoint(map) when is_map(map) do
    %MembershipsEndpoint{
      context_memberships_url: Map.get(map, :url, "https://platform.example.com/memberships"),
      service_versions: Map.get(map, :service_versions, ["2.0"])
    }
  end

  defp build_ags_endpoint(nil), do: nil

  defp build_ags_endpoint(%AgsEndpoint{} = ep), do: ep

  defp build_ags_endpoint(map) when is_map(map) do
    %AgsEndpoint{
      lineitems: Map.get(map, :lineitems),
      lineitem: Map.get(map, :lineitem),
      scope: Map.get(map, :scope)
    }
  end

  defp build_context(nil), do: nil

  defp build_context(map) when is_map(map) do
    %Context{
      id: Map.get(map, :id, "context-001"),
      label: Map.get(map, :label),
      title: Map.get(map, :title),
      type: Map.get(map, :type)
    }
  end

  defp build_resource_link(nil) do
    %ResourceLink{id: "resource-link-001", title: "Example Assignment"}
  end

  defp build_resource_link(map) when is_map(map) do
    %ResourceLink{
      id: Map.get(map, :id, "resource-link-001"),
      title: Map.get(map, :title),
      description: Map.get(map, :description)
    }
  end

  defp build_context_claim(nil), do: nil

  defp build_context_claim(map) when is_map(map) do
    claim = %{"id" => Map.get(map, :id, "context-001")}

    claim
    |> maybe_put("label", Map.get(map, :label))
    |> maybe_put("title", Map.get(map, :title))
  end

  defp build_resource_link_claim(nil) do
    %{"id" => "resource-link-001", "title" => "Example Assignment"}
  end

  defp build_resource_link_claim(map) when is_map(map) do
    claim = %{"id" => Map.get(map, :id, "resource-link-001")}

    claim
    |> maybe_put("title", Map.get(map, :title))
    |> maybe_put("description", Map.get(map, :description))
  end

  defp normalize_message_type(:deep_linking), do: "LtiDeepLinkingRequest"
  defp normalize_message_type(other), do: other

  defp maybe_resolve_roles(nil), do: nil
  defp maybe_resolve_roles(roles), do: resolve_role_uris(roles)

  defp build_deep_linking_settings(nil) do
    %DeepLinkingSettings{
      deep_link_return_url: "https://platform.example.com/deep_links",
      accept_types: ["ltiResourceLink", "link", "file", "html", "image"],
      accept_presentation_document_targets: ["iframe", "window", "embed"],
      accept_multiple: true
    }
  end

  defp build_deep_linking_settings(%DeepLinkingSettings{} = settings), do: settings

  defp build_deep_linking_settings(map) when is_map(map) do
    %DeepLinkingSettings{
      deep_link_return_url:
        Map.get(map, :deep_link_return_url, "https://platform.example.com/deep_links"),
      accept_types:
        Map.get(map, :accept_types, ["ltiResourceLink", "link", "file", "html", "image"]),
      accept_presentation_document_targets:
        Map.get(map, :accept_presentation_document_targets, ["iframe", "window", "embed"]),
      accept_media_types: Map.get(map, :accept_media_types),
      accept_multiple: Map.get(map, :accept_multiple, true),
      accept_lineitem: Map.get(map, :accept_lineitem),
      auto_create: Map.get(map, :auto_create),
      title: Map.get(map, :title),
      text: Map.get(map, :text),
      data: Map.get(map, :data)
    }
  end

  defp build_deep_linking_settings_claim(nil) do
    %{
      "deep_link_return_url" => "https://platform.example.com/deep_links",
      "accept_types" => ["ltiResourceLink", "link", "file", "html", "image"],
      "accept_presentation_document_targets" => ["iframe", "window", "embed"],
      "accept_multiple" => true
    }
  end

  defp build_deep_linking_settings_claim(map) when is_map(map) do
    base = %{
      "deep_link_return_url" =>
        Map.get(map, :deep_link_return_url, "https://platform.example.com/deep_links"),
      "accept_types" =>
        Map.get(map, :accept_types, ["ltiResourceLink", "link", "file", "html", "image"]),
      "accept_presentation_document_targets" =>
        Map.get(map, :accept_presentation_document_targets, ["iframe", "window", "embed"])
    }

    base
    |> maybe_put("accept_media_types", Map.get(map, :accept_media_types))
    |> maybe_put("accept_multiple", Map.get(map, :accept_multiple))
    |> maybe_put("accept_lineitem", Map.get(map, :accept_lineitem))
    |> maybe_put("auto_create", Map.get(map, :auto_create))
    |> maybe_put("title", Map.get(map, :title))
    |> maybe_put("text", Map.get(map, :text))
    |> maybe_put("data", Map.get(map, :data))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_lti(map, _key, nil), do: map
  defp maybe_put_lti(map, key, value), do: Map.put(map, @lti_claim_prefix <> key, value)

  defp merge_overrides(claims, overrides) when map_size(overrides) == 0, do: claims
  defp merge_overrides(claims, overrides), do: Map.merge(claims, overrides)
end
