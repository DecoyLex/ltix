defmodule Ltix.Test do
  @moduledoc """
  Helpers for testing applications that use Ltix.

  Reduces LTI test setup to a single call. Instead of manually generating
  RSA keys, building JWKS payloads, and creating registrations and
  deployments, call `setup_platform!/1`:

      setup do
        %{platform: Ltix.Test.setup_platform!()}
      end

  Your application's own storage adapter (configured in `config/test.exs`)
  handles persistence. `setup_platform!/1` provides the platform-side
  simulation: RSA keys, a JWKS endpoint stub, and registration/deployment
  data your adapter can look up.

  ## Connecting to your storage adapter

  Pass a `:registration` function to create records in your own persistence
  layer. The function receives a valid `Ltix.Registration` with the
  platform details and returns your app's struct (which must implement
  `Ltix.Registerable`):

      setup do
        platform = Ltix.Test.setup_platform!(
          registration: fn reg ->
            jwk = MyApp.Lti.generate_jwk!()

            MyApp.Lti.create_registration!(%{
              issuer: reg.issuer,
              client_id: reg.client_id,
              auth_endpoint: reg.auth_endpoint,
              jwks_uri: reg.jwks_uri,
              token_endpoint: reg.token_endpoint,
              tool_jwk_id: jwk.id
            })
          end,
          deployment: fn dep, my_reg ->
            MyApp.Lti.create_deployment!(%{
              deployment_id: dep.deployment_id,
              registration_id: my_reg.id
            })
          end
        )

        %{platform: platform}
      end

  ## Controller tests (full OIDC flow)

  Simulate a platform-initiated launch against your controller endpoints.
  Your app's storage adapter resolves registrations and nonces as it would
  in production:

      test "instructor launch renders dashboard", %{conn: conn, platform: platform} do
        conn = post(conn, ~p"/lti/login", Ltix.Test.login_params(platform))

        state = get_session(conn, :lti_state)
        nonce = Ltix.Test.extract_nonce(redirected_to(conn, 302))

        conn =
          conn
          |> recycle()
          |> Plug.Test.init_test_session(%{lti_state: state})
          |> post(~p"/lti/launch",
            Ltix.Test.launch_params(platform,
              nonce: nonce,
              state: state,
              roles: [:instructor],
              name: "Jane Doe"
            )
          )

        assert html_response(conn, 200) =~ "Dashboard"
      end

  ## Unit tests (direct context construction)

  When testing business logic that receives a `%LaunchContext{}`, skip
  the OIDC flow entirely with `build_launch_context/2`:

      test "instructors can manage grades", %{platform: platform} do
        context = Ltix.Test.build_launch_context(platform,
          roles: [:instructor],
          name: "Jane Smith"
        )

        assert MyApp.Permissions.can_manage_grades?(context)
      end

  ## Advantage service tests

  When testing code that calls `Ltix.GradeService` or
  `Ltix.MembershipsService`, stub the OAuth token endpoint and the
  service's HTTP calls. Each service has a well-known `Req.Test` stub
  name matching its module.

      setup do
        platform = Ltix.Test.setup_platform!()

        Ltix.Test.stub_token_response(scopes: [
          "https://purl.imsglobal.org/spec/lti-ags/scope/score"
        ])

        Ltix.Test.stub_post_score()

        %{platform: platform}
      end

      test "posts a score", %{platform: platform} do
        context = Ltix.Test.build_launch_context(platform,
          ags_endpoint: %Ltix.LaunchClaims.AgsEndpoint{
            lineitem: "https://platform.example.com/lineitems/1",
            scope: ["https://purl.imsglobal.org/spec/lti-ags/scope/score"]
          }
        )

        {:ok, client} = Ltix.GradeService.authenticate(context)
        :ok = Ltix.GradeService.post_score(client, score)
      end

  See the [Testing LTI Launches](testing-lti-launches.md) cookbook for
  more examples, including role customization, raw claim overrides, and
  memberships service testing.
  """

  alias Ltix.Deployable
  alias Ltix.Deployment
  alias Ltix.GradeService.LineItem
  alias Ltix.GradeService.Result
  alias Ltix.LaunchClaims
  alias Ltix.LaunchClaims.AgsEndpoint
  alias Ltix.LaunchClaims.Context
  alias Ltix.LaunchClaims.DeepLinkingSettings
  alias Ltix.LaunchClaims.MembershipsEndpoint
  alias Ltix.LaunchClaims.ResourceLink
  alias Ltix.LaunchClaims.Role
  alias Ltix.LaunchContext
  alias Ltix.MembershipsService.Member
  alias Ltix.Registerable
  alias Ltix.Registration
  alias Ltix.Test.Platform

  # --- Platform Setup ---

  @doc """
  Set up a simulated LTI platform in one call.

  Generates platform-side RSA keys, builds a registration and deployment,
  and stubs the JWKS HTTP endpoint. Your app's own storage adapter
  (configured via `config :ltix, storage_adapter: ...`) handles
  persistence during the OIDC flow.

  ## Options

    * `:issuer` — platform issuer URL (default: `"https://platform.example.com"`)
    * `:client_id` — OAuth client ID (default: `"tool-client-id"`)
    * `:deployment_id` — deployment identifier (default: `"deployment-001"`)
    * `:registration` — either an app struct implementing `Ltix.Registerable`
      (mutually exclusive with `:issuer` and `:client_id`), or a 1-arity
      function that receives an `Ltix.Registration` and returns your app's
      struct. The function form lets you create a matching record in your
      own persistence layer using the platform details (issuer, client_id,
      endpoints). Works with `:issuer` and `:client_id` overrides.
    * `:deployment` — either an app struct implementing `Ltix.Deployable`
      (mutually exclusive with `:deployment_id`), or a 2-arity function
      `(Ltix.Deployment, registration)` where `registration` is whatever
      the registration step returned. Lets you create a deployment record
      linked to your registration.
  """
  @spec setup_platform!(keyword()) :: Platform.t()
  def setup_platform!(opts \\ []) do
    validate_setup_opts!(opts)

    {private_key, public_key, kid} = generate_rsa_key_pair()
    jwks = build_jwks([public_key])

    registration = build_or_use_registration(opts)
    deployment = build_or_use_deployment(opts, registration)

    # Eagerly validate protocol implementations
    {:ok, _} = Registerable.to_registration(registration)
    {:ok, _} = Deployable.to_deployment(deployment)

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
      "iss" => resolved_registration(platform).issuer,
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

    reg = resolved_registration(platform)
    dep = resolved_deployment(platform)

    base_claims = %LaunchClaims{
      issuer: reg.issuer,
      audience: reg.client_id,
      version: "1.3.0",
      deployment_id: dep.deployment_id,
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

  # --- Service Test Helpers ---

  @doc """
  Stub the OAuth token endpoint for advantage service tests.

  Stubs the OAuth token endpoint so advantage service tests don't make
  real HTTP calls. Call this in your test setup before authenticating a
  service client.

      Ltix.Test.stub_token_response(scopes: [
        "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
        "https://purl.imsglobal.org/spec/lti-ags/scope/score"
      ])

  ## Options

    * `:scopes` — list of granted scope URIs (default: `[]`)
    * `:access_token` — token string (default: `"test-token"`)
    * `:expires_in` — token lifetime in seconds (default: `3600`)
  """
  @spec stub_token_response(keyword()) :: :ok
  def stub_token_response(opts \\ []) do
    scopes = Keyword.get(opts, :scopes, [])

    Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
      Req.Test.json(conn, %{
        "access_token" => Keyword.get(opts, :access_token, "test-token"),
        "token_type" => "Bearer",
        "expires_in" => Keyword.get(opts, :expires_in, 3600),
        "scope" => Enum.join(scopes, " ")
      })
    end)
  end

  # --- Grade Service Stubs ---

  @doc """
  Stub `list_line_items/2` to return the given line items.

      Ltix.Test.stub_list_line_items([
        %LineItem{id: "https://lms.example.com/lineitems/1", label: "Quiz 1", score_maximum: 100},
        %LineItem{id: "https://lms.example.com/lineitems/2", label: "Quiz 2", score_maximum: 50}
      ])

  Registers a stub on `Ltix.GradeService`. Overwrites any previous
  grade service stub in the current process.
  """
  @spec stub_list_line_items([LineItem.t()]) :: :ok
  def stub_list_line_items(line_items) when is_list(line_items) do
    json = Enum.map(line_items, &LineItem.to_map/1)

    Req.Test.stub(Ltix.GradeService, fn conn ->
      Req.Test.json(conn, json)
    end)
  end

  @doc """
  Stub `get_line_item/2` to return the given line item.

      Ltix.Test.stub_get_line_item(
        %LineItem{id: "https://lms.example.com/lineitems/1", label: "Quiz 1", score_maximum: 100}
      )
  """
  @spec stub_get_line_item(LineItem.t()) :: :ok
  def stub_get_line_item(%LineItem{} = item) do
    json = LineItem.to_map(item)

    Req.Test.stub(Ltix.GradeService, fn conn ->
      Req.Test.json(conn, json)
    end)
  end

  @doc """
  Stub `create_line_item/2` to return the given line item.

  Pass the line item you want the platform to "return" (typically the
  same fields the caller sent, plus an `:id` assigned by the platform).

      Ltix.Test.stub_create_line_item(
        %LineItem{id: "https://lms.example.com/lineitems/new", label: "Quiz 1", score_maximum: 100}
      )
  """
  @spec stub_create_line_item(LineItem.t()) :: :ok
  def stub_create_line_item(%LineItem{} = item) do
    json = LineItem.to_map(item)

    Req.Test.stub(Ltix.GradeService, fn conn ->
      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(json)
    end)
  end

  @doc """
  Stub `update_line_item/2` to return the given line item.

      Ltix.Test.stub_update_line_item(
        %LineItem{id: "https://lms.example.com/lineitems/1", label: "Updated Quiz", score_maximum: 100}
      )
  """
  @spec stub_update_line_item(LineItem.t()) :: :ok
  def stub_update_line_item(%LineItem{} = item) do
    json = LineItem.to_map(item)

    Req.Test.stub(Ltix.GradeService, fn conn ->
      Req.Test.json(conn, json)
    end)
  end

  @doc """
  Stub `delete_line_item/3` to succeed.

      Ltix.Test.stub_delete_line_item()
  """
  @spec stub_delete_line_item() :: :ok
  def stub_delete_line_item do
    Req.Test.stub(Ltix.GradeService, fn conn ->
      Plug.Conn.send_resp(conn, 204, "")
    end)
  end

  @doc """
  Stub `post_score/3` to succeed.

      Ltix.Test.stub_post_score()
  """
  @spec stub_post_score() :: :ok
  def stub_post_score do
    Req.Test.stub(Ltix.GradeService, fn conn ->
      Plug.Conn.send_resp(conn, 200, "")
    end)
  end

  @doc """
  Stub `get_results/2` to return the given results.

      Ltix.Test.stub_get_results([
        %Result{user_id: "student-1", result_score: 0.85, result_maximum: 1},
        %Result{user_id: "student-2", result_score: 0.92, result_maximum: 1}
      ])
  """
  @spec stub_get_results([Result.t()]) :: :ok
  def stub_get_results(results) when is_list(results) do
    json = Enum.map(results, &result_to_json/1)

    Req.Test.stub(Ltix.GradeService, fn conn ->
      Req.Test.json(conn, json)
    end)
  end

  # --- Memberships Service Stubs ---

  @doc """
  Stub `get_members/2` (and `stream_members/2`) to return the given members.

      Ltix.Test.stub_get_members([
        %Member{user_id: "student-1", roles: [Role.from_atom(:learner)], name: "Alice"},
        %Member{user_id: "student-2", roles: [Role.from_atom(:instructor)], name: "Bob"}
      ])

  ## Options

    * `:context` — `%Context{}` for the container (default: `%Context{id: "context-001"}`)
    * `:id` — container ID URL (default: `nil`)
  """
  @spec stub_get_members([Member.t()], keyword()) :: :ok
  def stub_get_members(members, opts \\ []) when is_list(members) do
    context = Keyword.get(opts, :context, %Context{id: "context-001"})
    container_id = Keyword.get(opts, :id)

    json =
      %{
        "context" => context_to_json(context),
        "members" => Enum.map(members, &member_to_json/1)
      }
      |> maybe_put("id", container_id)

    Req.Test.stub(Ltix.MembershipsService, fn conn ->
      Req.Test.json(conn, json)
    end)
  end

  # --- Struct Serialization (test only) ---

  defp result_to_json(%Result{} = result) do
    %{}
    |> maybe_put("id", result.id)
    |> maybe_put("scoreOf", result.score_of)
    |> maybe_put("userId", result.user_id)
    |> maybe_put("resultScore", result.result_score)
    |> maybe_put("resultMaximum", result.result_maximum)
    |> maybe_put("scoringUserId", result.scoring_user_id)
    |> maybe_put("comment", result.comment)
    |> Map.merge(result.extensions)
  end

  defp member_to_json(%Member{} = member) do
    role_uris =
      Enum.map(member.roles, fn role ->
        {:ok, uri} = Role.to_uri(role)
        uri
      end) ++ member.unrecognized_roles

    %{"user_id" => member.user_id, "roles" => role_uris}
    |> maybe_put("status", status_to_string(member.status))
    |> maybe_put("name", member.name)
    |> maybe_put("picture", member.picture)
    |> maybe_put("given_name", member.given_name)
    |> maybe_put("family_name", member.family_name)
    |> maybe_put("middle_name", member.middle_name)
    |> maybe_put("email", member.email)
    |> maybe_put("lis_person_sourcedid", member.lis_person_sourcedid)
    |> maybe_put("lti11_legacy_user_id", member.lti11_legacy_user_id)
  end

  defp context_to_json(%Context{} = ctx) do
    %{"id" => ctx.id}
    |> maybe_put("label", ctx.label)
    |> maybe_put("title", ctx.title)
    |> maybe_put("type", ctx.type)
  end

  defp status_to_string(:active), do: "Active"
  defp status_to_string(:inactive), do: "Inactive"
  defp status_to_string(:deleted), do: "Deleted"
  defp status_to_string(nil), do: nil

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
    public_key =
      resolved_registration(platform).tool_jwk
      |> Ltix.JWK.to_jose()
      |> JOSE.JWK.to_public()

    case JOSE.JWT.verify_strict(public_key, ["RS256"], jwt) do
      {true, %JOSE.JWT{fields: claims}, _jws} -> {:ok, claims}
      {false, _jwt, _jws} -> {:error, :signature_invalid}
    end
  end

  @doc """
  Generate an RSA key pair for testing.

  Returns `{private_jwk, public_jwk, kid}` as `JOSE.JWK.t()` values.
  Used internally for platform-side keys in test helpers.
  """
  @spec generate_rsa_key_pair() :: {JOSE.JWK.t(), JOSE.JWK.t(), String.t()}
  def generate_rsa_key_pair do
    private_jwk =
      {:rsa, 2048}
      |> JOSE.JWK.generate_key()
      |> JOSE.JWK.merge(%{"alg" => "RS256", "use" => "sig"})

    kid = JOSE.JWK.thumbprint(private_jwk)
    private_jwk = JOSE.JWK.merge(private_jwk, %{"kid" => kid})
    public_jwk = JOSE.JWK.to_public(private_jwk)

    {private_jwk, public_jwk, kid}
  end

  @doc """
  Build a JWKS map from a list of public JWKs.

  Returns `%{"keys" => [...]}`. Accepts `JOSE.JWK.t()` values
  (platform-side keys used in test helpers).
  """
  @spec build_jwks([JOSE.JWK.t()]) :: map()
  def build_jwks(public_keys) do
    keys =
      Enum.map(public_keys, fn jwk ->
        {_kty, fields} =
          jwk
          |> JOSE.JWK.to_public()
          |> JOSE.JWK.to_map()

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

    jws_fields = if kid, do: %{"alg" => alg, "kid" => kid}, else: %{"alg" => alg}

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
    reg = resolved_registration(platform)
    dep = resolved_deployment(platform)

    base = %{
      "iss" => reg.issuer,
      "aud" => reg.client_id,
      "exp" => now + 3600,
      "iat" => now,
      "nonce" => nonce,
      (@lti_claim_prefix <> "version") => "1.3.0",
      (@lti_claim_prefix <> "deployment_id") => dep.deployment_id,
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

  defp build_context(nil), do: %Context{id: "context-001"}

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

  defp build_context_claim(nil), do: %{"id" => "context-001"}

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

  defp merge_overrides(claims, overrides), do: Map.merge(claims, overrides)

  # --- Setup Helpers ---

  defp validate_setup_opts!(opts) do
    registration = Keyword.get(opts, :registration)
    deployment = Keyword.get(opts, :deployment)

    # Struct registrations are mutually exclusive with :issuer/:client_id.
    # Function registrations are not — the function receives a registration
    # built from those values.
    if not is_nil(registration) and not is_function(registration) do
      if Keyword.has_key?(opts, :issuer) do
        raise ArgumentError,
              ":registration and :issuer are mutually exclusive in setup_platform!/1"
      end

      if Keyword.has_key?(opts, :client_id) do
        raise ArgumentError,
              ":registration and :client_id are mutually exclusive in setup_platform!/1"
      end
    end

    if not is_nil(deployment) and not is_function(deployment) do
      if Keyword.has_key?(opts, :deployment_id) do
        raise ArgumentError,
              ":deployment and :deployment_id are mutually exclusive in setup_platform!/1"
      end
    end
  end

  defp build_or_use_registration(opts) do
    case Keyword.get(opts, :registration) do
      nil ->
        build_default_registration(opts)

      fun when is_function(fun, 1) ->
        fun.(build_default_registration(opts))

      registration ->
        registration
    end
  end

  defp build_default_registration(opts) do
    issuer = Keyword.get(opts, :issuer, "https://platform.example.com")
    client_id = Keyword.get(opts, :client_id, "tool-client-id")
    tool_jwk = Ltix.JWK.generate()
    suffix = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)

    {:ok, registration} =
      Registration.new(%{
        issuer: issuer,
        client_id: client_id,
        auth_endpoint: "#{issuer}/auth",
        jwks_uri: "#{issuer}/.well-known/jwks-#{suffix}.json",
        token_endpoint: "#{issuer}/token",
        tool_jwk: tool_jwk
      })

    registration
  end

  defp build_or_use_deployment(opts, registration) do
    case Keyword.get(opts, :deployment) do
      nil ->
        deployment_id = Keyword.get(opts, :deployment_id, "deployment-001")
        {:ok, deployment} = Deployment.new(deployment_id)
        deployment

      fun when is_function(fun, 2) ->
        deployment_id = Keyword.get(opts, :deployment_id, "deployment-001")
        {:ok, default} = Deployment.new(deployment_id)
        fun.(default, registration)

      deployment ->
        deployment
    end
  end

  defp resolved_registration(%Platform{} = platform) do
    {:ok, reg} = Registerable.to_registration(platform.registration)
    reg
  end

  defp resolved_deployment(%Platform{} = platform) do
    {:ok, dep} = Deployable.to_deployment(platform.deployment)
    dep
  end
end
