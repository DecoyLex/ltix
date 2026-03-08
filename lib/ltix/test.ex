defmodule Ltix.Test do
  @moduledoc """
  Helpers for testing applications that use Ltix.

  Reduces LTI test setup to a single call. Instead of manually generating
  RSA keys, building JWKS payloads, creating registrations and deployments,
  starting storage adapters, and stubbing HTTP endpoints, call
  `setup_platform!/1`:

      setup do
        platform = Ltix.Test.setup_platform!()

        on_exit(fn ->
          Application.delete_env(:ltix, :storage_adapter)
        end)

        %{platform: platform}
      end

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

  alias Ltix.{Deployment, LaunchClaims, LaunchContext, Registration}
  alias Ltix.LaunchClaims.{Context, ResourceLink, Role}
  alias Ltix.Test.{Platform, StorageAdapter}

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

    # Unique JWKS URI per call for async test safety
    suffix = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)

    {:ok, registration} =
      Registration.new(%{
        issuer: issuer,
        client_id: client_id,
        auth_endpoint: "#{issuer}/auth",
        jwks_uri: "#{issuer}/.well-known/jwks-#{suffix}.json"
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

    Application.put_env(:ltix, :storage_adapter, StorageAdapter)

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

    * `:roles` — list of role atoms (e.g., `[:instructor]`), `%Role{}` structs,
      or URI strings
    * `:subject` — user identifier (default: `"user-12345"`)
    * `:name`, `:email`, `:given_name`, `:family_name` — user PII
    * `:context` — map with `:id`, `:label`, `:title` keys
    * `:resource_link` — map with `:id`, `:title` keys
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
  """
  @spec build_launch_context(Platform.t(), keyword()) :: LaunchContext.t()
  def build_launch_context(%Platform{} = platform, opts \\ []) do
    role_uris = resolve_role_uris(Keyword.get(opts, :roles, []))
    {parsed_roles, _unrecognized} = Role.parse_all(role_uris)

    claims = %LaunchClaims{
      issuer: platform.registration.issuer,
      subject: Keyword.get(opts, :subject, "user-12345"),
      audience: platform.registration.client_id,
      message_type: "LtiResourceLinkRequest",
      version: "1.3.0",
      deployment_id: platform.deployment.deployment_id,
      target_link_uri: Keyword.get(opts, :target_link_uri, "https://tool.example.com/launch"),
      roles: parsed_roles,
      name: Keyword.get(opts, :name),
      email: Keyword.get(opts, :email),
      given_name: Keyword.get(opts, :given_name),
      family_name: Keyword.get(opts, :family_name),
      context: build_context(Keyword.get(opts, :context)),
      resource_link: build_resource_link(Keyword.get(opts, :resource_link))
    }

    %LaunchContext{
      claims: claims,
      registration: platform.registration,
      deployment: platform.deployment
    }
  end

  # --- Lower-Level Helpers ---

  @doc """
  Generate an RSA key pair for testing.

  Returns `{private_jwk, public_jwk, kid}`.
  """
  @spec generate_rsa_key_pair() :: {JOSE.JWK.t(), JOSE.JWK.t(), String.t()}
  def generate_rsa_key_pair do
    kid = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    private_jwk = JOSE.JWK.generate_key({:rsa, 2048})
    private_jwk = JOSE.JWK.merge(private_jwk, %{"kid" => kid})
    public_jwk = JOSE.JWK.to_public(private_jwk)

    {private_jwk, public_jwk, kid}
  end

  @doc """
  Build a JWKS map from a list of public JWKs.

  Returns `%{"keys" => [...]}`.
  """
  @spec build_jwks([JOSE.JWK.t()]) :: map()
  def build_jwks(public_keys) do
    keys =
      Enum.map(public_keys, fn jwk ->
        {_kty, fields} = JOSE.JWK.to_map(jwk)
        fields
      end)

    %{"keys" => keys}
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
      %{"alg" => alg}
      |> then(fn fields ->
        if kid, do: Map.put(fields, "kid", kid), else: fields
      end)

    jws = JOSE.JWS.from_map(jws_fields)
    jwt = JOSE.JWT.from_map(claims)

    {_meta, token} =
      JOSE.JWT.sign(private_jwk, jws, jwt)
      |> JOSE.JWS.compact()

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

  defp build_claims(platform, nonce, opts) do
    now = System.system_time(:second)

    base = %{
      "iss" => platform.registration.issuer,
      "sub" => Keyword.get(opts, :subject, "user-12345"),
      "aud" => platform.registration.client_id,
      "exp" => now + 3600,
      "iat" => now,
      "nonce" => nonce,
      (@lti_claim_prefix <> "message_type") => "LtiResourceLinkRequest",
      (@lti_claim_prefix <> "version") => "1.3.0",
      (@lti_claim_prefix <> "deployment_id") => platform.deployment.deployment_id,
      (@lti_claim_prefix <> "target_link_uri") =>
        Keyword.get(opts, :target_link_uri, "https://tool.example.com/launch"),
      (@lti_claim_prefix <> "roles") =>
        resolve_role_uris(Keyword.get(opts, :roles, [:instructor])),
      (@lti_claim_prefix <> "resource_link") =>
        build_resource_link_claim(Keyword.get(opts, :resource_link))
    }

    base
    |> maybe_put("name", Keyword.get(opts, :name))
    |> maybe_put("email", Keyword.get(opts, :email))
    |> maybe_put("given_name", Keyword.get(opts, :given_name))
    |> maybe_put("family_name", Keyword.get(opts, :family_name))
    |> maybe_put_lti("context", build_context_claim(Keyword.get(opts, :context)))
    |> merge_overrides(Keyword.get(opts, :claims, %{}))
  end

  defp resolve_role_uris(roles) do
    Enum.map(roles, fn
      uri when is_binary(uri) ->
        uri

      %Role{uri: uri} when is_binary(uri) ->
        uri

      %Role{} = role ->
        case Role.to_uri(role) do
          {:ok, uri} -> uri
          :error -> raise ArgumentError, "could not resolve role to URI: #{inspect(role)}"
        end

      atom when is_atom(atom) ->
        role = %Role{type: :context, name: atom, sub_role: nil}

        case Role.to_uri(role) do
          {:ok, uri} -> uri
          :error -> raise ArgumentError, "unknown role atom: #{inspect(atom)}"
        end
    end)
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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_lti(map, _key, nil), do: map
  defp maybe_put_lti(map, key, value), do: Map.put(map, @lti_claim_prefix <> key, value)

  defp merge_overrides(claims, overrides) when map_size(overrides) == 0, do: claims
  defp merge_overrides(claims, overrides), do: Map.merge(claims, overrides)
end
