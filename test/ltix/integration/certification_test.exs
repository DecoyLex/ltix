defmodule Ltix.Integration.CertificationTest do
  use ExUnit.Case, async: true

  alias Ltix.Deployment
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.Errors.Security
  alias Ltix.LaunchClaims
  alias Ltix.LaunchContext
  alias Ltix.Registration
  alias Ltix.Test.JWTHelper
  alias Ltix.Test.StorageAdapter

  @lti "https://purl.imsglobal.org/spec/lti/claim/"

  setup do
    {private, public, kid} = JWTHelper.generate_rsa_key_pair()
    jwks = JWTHelper.build_jwks([public])

    {:ok, registration} =
      Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri: "https://platform.example.com/.well-known/jwks.json",
        tool_jwk: private
      })

    {:ok, deployment} = Deployment.new("deployment-001")

    nonce = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    {:ok, pid} =
      StorageAdapter.start_link(
        registrations: [registration],
        deployments: [deployment]
      )

    StorageAdapter.set_pid(pid)
    StorageAdapter.store_nonce(nonce, registration)

    Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("cache-control", "max-age=300")
      |> Req.Test.json(jwks)
    end)

    claims = JWTHelper.valid_lti_claims(%{"nonce" => nonce})

    on_exit(fn ->
      Application.delete_env(:ltix, :allow_anonymous)
    end)

    %{
      registration: registration,
      deployment: deployment,
      private: private,
      kid: kid,
      nonce: nonce,
      state: state,
      claims: claims
    }
  end

  # [Cert §6.1.1](https://www.imsglobal.org/spec/lti/v1p3/cert/#known-bad-payloads)
  describe "Known Bad Payloads [Cert §6.1.1]" do
    test "No KID Sent in JWT header", ctx do
      id_token = JWTHelper.mint_id_token(ctx.claims, ctx.private)
      params = %{"id_token" => id_token, "state" => ctx.state}

      assert {:error, %Security.KidMissing{}} = handle_callback(params, ctx.state)
    end

    test "Incorrect KID in JWT header", ctx do
      id_token = JWTHelper.mint_id_token(ctx.claims, ctx.private, kid: "wrong-kid")
      params = %{"id_token" => id_token, "state" => ctx.state}

      assert {:error, %Security.KidNotFound{kid: "wrong-kid"}} =
               handle_callback(params, ctx.state)
    end

    test "Wrong LTI Version", ctx do
      claims = put_lti_claim(ctx.claims, "version", "1.2.0")
      params = mint_and_params(claims, ctx)

      assert {:error, %InvalidClaim{claim: "version", value: "1.2.0"}} =
               handle_callback(params, ctx.state)
    end

    test "No LTI Version", ctx do
      claims = Map.delete(ctx.claims, @lti <> "version")
      params = mint_and_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "version"}} =
               handle_callback(params, ctx.state)
    end

    test "Invalid LTI message", ctx do
      params = %{"id_token" => "not-a-jwt", "state" => ctx.state}

      assert {:error, _} = handle_callback(params, ctx.state)
    end

    test "Missing LTI Claims", ctx do
      claims =
        ctx.claims
        |> Map.delete(@lti <> "message_type")
        |> Map.delete(@lti <> "version")
        |> Map.delete(@lti <> "deployment_id")

      params = mint_and_params(claims, ctx)

      assert {:error, %MissingClaim{}} = handle_callback(params, ctx.state)
    end

    test "Timestamps Incorrect", ctx do
      claims = Map.put(ctx.claims, "exp", System.system_time(:second) - 3600)
      params = mint_and_params(claims, ctx)

      assert {:error, %Security.TokenExpired{}} = handle_callback(params, ctx.state)
    end

    # [sic] — matches cert suite spelling
    test "messsage_type Claim Missing", ctx do
      claims = Map.delete(ctx.claims, @lti <> "message_type")
      params = mint_and_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "message_type"}} =
               handle_callback(params, ctx.state)
    end

    test "role Claim Missing", ctx do
      claims = Map.delete(ctx.claims, @lti <> "roles")
      params = mint_and_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "roles"}} =
               handle_callback(params, ctx.state)
    end

    test "deployment_id Claim Missing", ctx do
      claims = Map.delete(ctx.claims, @lti <> "deployment_id")
      params = mint_and_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "deployment_id"}} =
               handle_callback(params, ctx.state)
    end

    test "resource_link_id Claim Missing", ctx do
      claims = put_lti_claim(ctx.claims, "resource_link", %{"title" => "No ID"})
      params = mint_and_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "resource_link.id"}} =
               handle_callback(params, ctx.state)
    end

    test "user Claim Missing", ctx do
      claims = Map.delete(ctx.claims, "sub")
      params = mint_and_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "sub"}} = handle_callback(params, ctx.state)
    end
  end

  # [Cert §6.1.2](https://www.imsglobal.org/spec/lti/v1p3/cert/#valid-teacher-launches)
  describe "Valid Teacher Launches [Cert §6.1.2]" do
    test "Valid Instructor Launch", ctx do
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

      assert {:ok, %LaunchContext{} = launch} = handle_callback(params, ctx.state)

      assert LaunchClaims.Role.instructor?(launch.claims.roles)
      assert launch.claims.name == "Jane Doe"
      assert launch.claims.email == "instructor@example.com"
      assert launch.claims.context.id == "course-001"
    end

    test "Valid Instructor Launch with Roles", ctx do
      claims =
        put_lti_claim(ctx.claims, "roles", [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor",
          "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Faculty"
        ])

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} = handle_callback(params, ctx.state)

      assert [%LaunchClaims.Role{name: :instructor}, %LaunchClaims.Role{}] =
               launch.claims.roles
    end

    test "Valid Instructor Launch Short Role", ctx do
      claims = put_lti_claim(ctx.claims, "roles", ["Instructor"])
      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} = handle_callback(params, ctx.state)

      assert [%LaunchClaims.Role{name: :instructor}] = launch.claims.roles
    end

    test "Valid Instructor Launch Unknown Role", ctx do
      claims =
        put_lti_claim(ctx.claims, "roles", [
          "http://example.com/custom/TeachingAssistant"
        ])

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} = handle_callback(params, ctx.state)

      assert launch.claims.roles == []

      assert launch.claims.unrecognized_roles == [
               "http://example.com/custom/TeachingAssistant"
             ]
    end

    test "Valid Instructor Launch No Role", ctx do
      claims = put_lti_claim(ctx.claims, "roles", [])
      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} = handle_callback(params, ctx.state)

      assert launch.claims.roles == []
    end

    test "Valid Instructor Launch Email Only", ctx do
      claims =
        ctx.claims
        |> Map.put("email", "instructor@example.com")
        |> Map.delete("name")
        |> Map.delete("given_name")
        |> Map.delete("family_name")

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} = handle_callback(params, ctx.state)

      assert launch.claims.email == "instructor@example.com"
      assert launch.claims.name == nil
    end

    test "Valid Instructor Launch Names Only", ctx do
      claims =
        ctx.claims
        |> Map.put("name", "Jane Doe")
        |> Map.put("given_name", "Jane")
        |> Map.put("family_name", "Doe")
        |> Map.delete("email")

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} = handle_callback(params, ctx.state)

      assert launch.claims.name == "Jane Doe"
      assert launch.claims.email == nil
    end

    test "Valid Instructor No PII", ctx do
      claims =
        ctx.claims
        |> Map.delete("email")
        |> Map.delete("name")
        |> Map.delete("given_name")
        |> Map.delete("family_name")

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{}} = handle_callback(params, ctx.state)
    end

    test "Valid Instructor Email Without Context", ctx do
      claims =
        ctx.claims
        |> Map.put("email", "instructor@example.com")
        |> Map.delete(@lti <> "context")

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} = handle_callback(params, ctx.state)

      assert launch.claims.email == "instructor@example.com"
      assert launch.claims.context == nil
    end
  end

  # [Cert §6.1.3](https://www.imsglobal.org/spec/lti/v1p3/cert/#valid-student-launches)
  describe "Valid Student Launches [Cert §6.1.3]" do
    test "Valid Student Launch", ctx do
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

      assert {:ok, %LaunchContext{} = launch} = handle_callback(params, ctx.state)

      assert LaunchClaims.Role.learner?(launch.claims.roles)
      assert launch.claims.name == "John Smith"
      assert launch.claims.email == "student@example.com"
      assert launch.claims.context.id == "course-001"
    end

    test "Valid Student Launch with Roles", ctx do
      claims =
        put_lti_claim(ctx.claims, "roles", [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner",
          "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Student"
        ])

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} = handle_callback(params, ctx.state)

      assert [%LaunchClaims.Role{name: :learner}, %LaunchClaims.Role{}] =
               launch.claims.roles
    end

    test "Valid Student Launch Short Role", ctx do
      claims = put_lti_claim(ctx.claims, "roles", ["Learner"])
      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} = handle_callback(params, ctx.state)

      assert [%LaunchClaims.Role{name: :learner}] = launch.claims.roles
    end

    test "Valid Student Launch Unknown Role", ctx do
      claims =
        put_lti_claim(ctx.claims, "roles", [
          "http://example.com/custom/Auditor"
        ])

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} = handle_callback(params, ctx.state)

      assert launch.claims.roles == []
      assert launch.claims.unrecognized_roles == ["http://example.com/custom/Auditor"]
    end

    test "Valid Student Launch No Role", ctx do
      claims = put_lti_claim(ctx.claims, "roles", [])
      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{}} = handle_callback(params, ctx.state)
    end

    test "Valid Student Launch Email Only", ctx do
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

      assert {:ok, %LaunchContext{} = launch} = handle_callback(params, ctx.state)

      assert launch.claims.email == "student@example.com"
      assert launch.claims.name == nil
    end

    test "Valid Student Launch Names Only", ctx do
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

      assert {:ok, %LaunchContext{} = launch} = handle_callback(params, ctx.state)

      assert launch.claims.name == "John Smith"
      assert launch.claims.email == nil
    end

    test "Valid Student No PII", ctx do
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

      assert {:ok, %LaunchContext{}} = handle_callback(params, ctx.state)
    end

    test "Valid Student Email Without Context", ctx do
      claims =
        ctx.claims
        |> put_lti_claim("roles", [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"
        ])
        |> Map.put("email", "student@example.com")
        |> Map.delete(@lti <> "context")

      params = mint_and_params(claims, ctx)

      assert {:ok, %LaunchContext{} = launch} = handle_callback(params, ctx.state)

      assert launch.claims.email == "student@example.com"
      assert launch.claims.context == nil
    end
  end

  # -- Helpers --

  defp handle_callback(params, state) do
    Ltix.handle_callback(params, state,
      storage_adapter: StorageAdapter,
      req_options: req_options()
    )
  end

  defp mint_and_params(claims, ctx) do
    id_token = JWTHelper.mint_id_token(claims, ctx.private, kid: ctx.kid)
    %{"id_token" => id_token, "state" => ctx.state}
  end

  defp req_options, do: [plug: {Req.Test, Ltix.JWT.KeySet}]

  defp put_lti_claim(claims, key, value) do
    Map.put(claims, @lti <> key, value)
  end
end
