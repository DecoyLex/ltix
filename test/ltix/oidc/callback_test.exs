defmodule Ltix.OIDC.CallbackTest do
  use ExUnit.Case, async: true

  alias Ltix.{Deployment, LaunchClaims, LaunchContext, Registration}

  alias Ltix.Errors.Invalid.{
    DeploymentNotFound,
    InvalidClaim,
    MissingClaim,
    MissingParameter,
    RegistrationNotFound
  }

  alias Ltix.Errors.Security
  alias Ltix.OIDC.Callback
  alias Ltix.Test.{JWTHelper, TestStorageAdapter}

  @lti "https://purl.imsglobal.org/spec/lti/claim/"

  setup do
    {private, public, kid} = JWTHelper.generate_rsa_key_pair()
    jwks = JWTHelper.build_jwks([public])

    {:ok, registration} =
      Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri: "https://platform.example.com/.well-known/jwks.json"
      })

    {:ok, deployment} = Deployment.new("deployment-001")

    nonce = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    {:ok, pid} =
      TestStorageAdapter.start_link(
        registrations: [registration],
        deployments: [deployment]
      )

    TestStorageAdapter.set_pid(pid)
    TestStorageAdapter.store_nonce(nonce, registration)

    stub_jwks(jwks)

    claims = JWTHelper.valid_lti_claims(%{"nonce" => nonce})
    id_token = JWTHelper.mint_id_token(claims, private, kid: kid)

    params = %{"id_token" => id_token, "state" => state}

    %{
      registration: registration,
      deployment: deployment,
      private: private,
      kid: kid,
      nonce: nonce,
      state: state,
      params: params,
      claims: claims
    }
  end

  describe "happy path" do
    test "valid launch returns LaunchContext", ctx do
      assert {:ok, %LaunchContext{} = launch} =
               Callback.call(ctx.params, ctx.state, TestStorageAdapter,
                 req_options: req_options()
               )

      assert launch.registration == ctx.registration
      assert launch.deployment == ctx.deployment
      assert launch.claims.message_type == "LtiResourceLinkRequest"
      assert launch.claims.version == "1.3.0"
      assert launch.claims.deployment_id == "deployment-001"
      assert launch.claims.target_link_uri == "https://tool.example.com/launch"
      assert launch.claims.subject == "user-12345"
    end
  end

  # [Sec §5.1.1.5](https://www.imsglobal.org/spec/security/v1p0/#authentication-error-response)
  describe "error responses [Sec §5.1.1.5]" do
    test "platform error response returns AuthenticationFailed", ctx do
      params = %{
        "error" => "login_required",
        "error_description" => "User session expired",
        "state" => ctx.state
      }

      assert {:error,
              %Security.AuthenticationFailed{
                error: "login_required",
                error_description: "User session expired"
              }} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "platform error without description", ctx do
      params = %{"error" => "access_denied", "state" => ctx.state}

      assert {:error,
              %Security.AuthenticationFailed{
                error: "access_denied",
                error_description: nil
              }} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())
    end
  end

  describe "parameter validation" do
    test "missing id_token returns MissingParameter", ctx do
      params = Map.delete(ctx.params, "id_token")

      assert {:error, %MissingParameter{parameter: "id_token"}} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    # [Sec §7.3.1](https://www.imsglobal.org/spec/security/v1p0/#prohibiting-the-login-csrf-vulnerability)
    test "state mismatch returns StateMismatch", ctx do
      assert {:error, %Security.StateMismatch{}} =
               Callback.call(
                 ctx.params,
                 "wrong-state",
                 TestStorageAdapter,
                 req_options: req_options()
               )
    end

    test "missing state returns StateMismatch", ctx do
      params = Map.delete(ctx.params, "state")

      assert {:error, %Security.StateMismatch{}} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "malformed id_token returns error", ctx do
      params = Map.put(ctx.params, "id_token", "not-a-jwt")

      assert {:error, _} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())
    end
  end

  describe "registration lookup" do
    test "unknown issuer returns RegistrationNotFound", ctx do
      claims =
        JWTHelper.valid_lti_claims(%{
          "iss" => "https://unknown.example.com",
          "nonce" => ctx.nonce
        })

      id_token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)
      params = %{"id_token" => id_token, "state" => ctx.state}

      assert {:error, %RegistrationNotFound{issuer: "https://unknown.example.com"}} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())
    end
  end

  # [Cert §6.1.1](https://www.imsglobal.org/spec/lti/v1p3/cert/#known-bad-payloads)
  describe "bad JWT payloads [Cert §6.1.1]" do
    test "missing KID", ctx do
      id_token = JWTHelper.mint_id_token(ctx.claims, ctx.private)
      params = %{"id_token" => id_token, "state" => ctx.state}

      assert {:error, %Security.KidMissing{}} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "incorrect KID", ctx do
      id_token = JWTHelper.mint_id_token(ctx.claims, ctx.private, kid: "wrong-kid")
      params = %{"id_token" => id_token, "state" => ctx.state}

      assert {:error, %Security.KidNotFound{kid: "wrong-kid"}} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "expired token", ctx do
      claims = Map.put(ctx.claims, "exp", System.system_time(:second) - 3600)
      id_token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)
      params = %{"id_token" => id_token, "state" => ctx.state}

      assert {:error, %Security.TokenExpired{}} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())
    end
  end

  # [Sec §5.1.3 step 9](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
  describe "nonce validation [Sec §5.1.3 step 9]" do
    test "unknown nonce returns NonceNotFound", ctx do
      claims = Map.put(ctx.claims, "nonce", "never-stored-nonce")
      id_token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)
      params = %{"id_token" => id_token, "state" => ctx.state}

      assert {:error, %Security.NonceNotFound{}} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "replayed nonce returns NonceReused", ctx do
      opts = [req_options: req_options()]

      # First call consumes the nonce
      assert {:ok, _} = Callback.call(ctx.params, ctx.state, TestStorageAdapter, opts)

      # Store a fresh nonce for a second token, but reuse the consumed one
      fresh_nonce = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      TestStorageAdapter.store_nonce(fresh_nonce, ctx.registration)

      # Mint a new token that reuses the original (now consumed) nonce
      claims = Map.put(ctx.claims, "nonce", ctx.nonce)
      id_token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)
      new_state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      params = %{"id_token" => id_token, "state" => new_state}

      assert {:error, %Security.NonceReused{}} =
               Callback.call(params, new_state, TestStorageAdapter, opts)
    end
  end

  # [Core §5.3](https://www.imsglobal.org/spec/lti/v1p3/#required-message-claims)
  describe "LTI claim validation [Cert §6.1.1]" do
    test "wrong LTI version", ctx do
      claims = put_lti_claim(ctx.claims, "version", "1.2.0")
      id_token = mint_and_params(claims, ctx)

      assert {:error, %InvalidClaim{claim: "version", value: "1.2.0"}} =
               Callback.call(id_token, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "missing LTI version", ctx do
      claims = Map.delete(ctx.claims, @lti <> "version")
      id_token = mint_and_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "version"}} =
               Callback.call(id_token, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "missing message_type", ctx do
      claims = Map.delete(ctx.claims, @lti <> "message_type")
      id_token = mint_and_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "message_type"}} =
               Callback.call(id_token, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "missing deployment_id", ctx do
      claims = Map.delete(ctx.claims, @lti <> "deployment_id")
      id_token = mint_and_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "deployment_id"}} =
               Callback.call(id_token, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "missing target_link_uri", ctx do
      claims = Map.delete(ctx.claims, @lti <> "target_link_uri")
      id_token = mint_and_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "target_link_uri"}} =
               Callback.call(id_token, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "missing resource_link", ctx do
      claims = Map.delete(ctx.claims, @lti <> "resource_link")
      id_token = mint_and_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "resource_link"}} =
               Callback.call(id_token, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "missing resource_link.id", ctx do
      claims = put_lti_claim(ctx.claims, "resource_link", %{"title" => "No ID"})
      id_token = mint_and_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "resource_link.id"}} =
               Callback.call(id_token, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "missing sub", ctx do
      claims = Map.delete(ctx.claims, "sub")
      id_token = mint_and_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "sub"}} =
               Callback.call(id_token, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "missing roles", ctx do
      claims = Map.delete(ctx.claims, @lti <> "roles")
      id_token = mint_and_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "roles"}} =
               Callback.call(id_token, ctx.state, TestStorageAdapter, req_options: req_options())
    end
  end

  # [Core §3.1.3](https://www.imsglobal.org/spec/lti/v1p3/#tool-deployment)
  describe "deployment validation [Core §3.1.3]" do
    test "unknown deployment_id returns DeploymentNotFound", ctx do
      claims = put_lti_claim(ctx.claims, "deployment_id", "unknown-deployment")
      id_token = mint_and_params(claims, ctx)

      assert {:error, %DeploymentNotFound{deployment_id: "unknown-deployment"}} =
               Callback.call(id_token, ctx.state, TestStorageAdapter, req_options: req_options())
    end
  end

  # [Cert §6.1.2](https://www.imsglobal.org/spec/lti/v1p3/cert/#valid-teacher-launches)
  describe "valid instructor launches [Cert §6.1.2]" do
    test "standard instructor launch", ctx do
      claims =
        ctx.claims
        |> Map.put("name", "Jane Doe")
        |> Map.put("email", "instructor@example.com")
        |> put_lti_claim("context", %{
          "id" => "course-001",
          "label" => "CS101",
          "title" => "Intro to CS"
        })

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())

      assert LaunchClaims.Role.instructor?(launch.claims.roles)
      assert launch.claims.name == "Jane Doe"
      assert launch.claims.email == "instructor@example.com"
      assert launch.claims.context.id == "course-001"
    end

    test "instructor launch with multiple roles", ctx do
      claims =
        put_lti_claim(ctx.claims, "roles", [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor",
          "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Faculty"
        ])

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())

      assert [%LaunchClaims.Role{name: :instructor}, %LaunchClaims.Role{}] =
               launch.claims.roles
    end

    test "instructor launch with short role", ctx do
      claims =
        put_lti_claim(ctx.claims, "roles", [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"
        ])

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{}} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "instructor launch with unknown role", ctx do
      claims =
        put_lti_claim(ctx.claims, "roles", [
          "http://example.com/custom/TeachingAssistant"
        ])

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{}} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "instructor launch with no roles (empty array)", ctx do
      claims = put_lti_claim(ctx.claims, "roles", [])
      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())

      assert launch.claims.roles == []
    end

    test "instructor launch email only", ctx do
      claims =
        ctx.claims
        |> Map.put("email", "instructor@example.com")
        |> Map.delete("name")
        |> Map.delete("given_name")
        |> Map.delete("family_name")

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())

      assert launch.claims.email == "instructor@example.com"
      assert launch.claims.name == nil
    end

    test "instructor launch names only", ctx do
      claims =
        ctx.claims
        |> Map.put("name", "Jane Doe")
        |> Map.put("given_name", "Jane")
        |> Map.put("family_name", "Doe")
        |> Map.delete("email")

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())

      assert launch.claims.name == "Jane Doe"
      assert launch.claims.email == nil
    end

    test "instructor launch no PII", ctx do
      claims =
        ctx.claims
        |> Map.delete("email")
        |> Map.delete("name")
        |> Map.delete("given_name")
        |> Map.delete("family_name")

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{}} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "instructor launch email without context", ctx do
      claims =
        ctx.claims
        |> Map.put("email", "instructor@example.com")
        |> Map.delete(@lti <> "context")

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())

      assert launch.claims.email == "instructor@example.com"
      assert launch.claims.context == nil
    end
  end

  # [Cert §6.1.3](https://www.imsglobal.org/spec/lti/v1p3/cert/#valid-student-launches)
  describe "valid student launches [Cert §6.1.3]" do
    test "standard student launch", ctx do
      claims =
        ctx.claims
        |> put_lti_claim("roles", [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"
        ])
        |> Map.put("name", "John Smith")
        |> Map.put("email", "student@example.com")
        |> put_lti_claim("context", %{
          "id" => "course-001",
          "label" => "CS101",
          "title" => "Intro to CS"
        })

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())

      assert LaunchClaims.Role.learner?(launch.claims.roles)
      assert launch.claims.name == "John Smith"
      assert launch.claims.email == "student@example.com"
      assert launch.claims.context.id == "course-001"
    end

    test "student launch with multiple roles", ctx do
      claims =
        put_lti_claim(ctx.claims, "roles", [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner",
          "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Student"
        ])

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())

      assert [%LaunchClaims.Role{name: :learner}, %LaunchClaims.Role{}] = launch.claims.roles
    end

    test "student launch with short role", ctx do
      claims =
        put_lti_claim(ctx.claims, "roles", [
          "Learner"
        ])

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{}} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "student launch with unknown role", ctx do
      claims =
        put_lti_claim(ctx.claims, "roles", [
          "http://example.com/custom/Auditor"
        ])

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{}} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "student launch with no roles (empty array)", ctx do
      claims = put_lti_claim(ctx.claims, "roles", [])
      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{}} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "student launch email only", ctx do
      claims =
        ctx.claims
        |> put_lti_claim("roles", [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"
        ])
        |> Map.put("email", "student@example.com")
        |> Map.delete("name")
        |> Map.delete("given_name")
        |> Map.delete("family_name")

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())

      assert launch.claims.email == "student@example.com"
      assert launch.claims.name == nil
    end

    test "student launch names only", ctx do
      claims =
        ctx.claims
        |> put_lti_claim("roles", [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"
        ])
        |> Map.put("name", "John Smith")
        |> Map.put("given_name", "John")
        |> Map.put("family_name", "Smith")
        |> Map.delete("email")

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())

      assert launch.claims.name == "John Smith"
      assert launch.claims.email == nil
    end

    test "student launch no PII", ctx do
      claims =
        ctx.claims
        |> put_lti_claim("roles", [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"
        ])
        |> Map.delete("email")
        |> Map.delete("name")
        |> Map.delete("given_name")
        |> Map.delete("family_name")

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{}} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())
    end

    test "student launch email without context", ctx do
      claims =
        ctx.claims
        |> put_lti_claim("roles", [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"
        ])
        |> Map.put("email", "student@example.com")
        |> Map.delete(@lti <> "context")

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} =
               Callback.call(params, ctx.state, TestStorageAdapter, req_options: req_options())

      assert launch.claims.email == "student@example.com"
      assert launch.claims.context == nil
    end
  end

  # -- Helpers --

  defp mint_and_params(claims, ctx) do
    id_token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)
    %{"id_token" => id_token, "state" => ctx.state}
  end

  defp stub_jwks(jwks) do
    Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("cache-control", "max-age=300")
      |> Req.Test.json(jwks)
    end)
  end

  defp req_options, do: [plug: {Req.Test, Ltix.JWT.KeySet}]

  defp put_lti_claim(claims, key, value) do
    Map.put(claims, @lti <> key, value)
  end
end
