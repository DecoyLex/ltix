defmodule Ltix.Integration.CertificationTest do
  use ExUnit.Case, async: true

  alias Ltix.Deployment
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.InvalidJSON
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.Errors.Security
  alias Ltix.Launch
  alias Ltix.Registration
  alias Ltix.Role
  alias Ltix.Test.StorageAdapter

  @lti "https://purl.imsglobal.org/spec/lti/claim/"

  setup do
    platform_jwk = Ltix.JWK.generate()
    jwks = Ltix.JWK.to_jwks(platform_jwk)

    {:ok, registration} =
      Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri:
          "https://platform.example.com/.well-known/jwks-#{System.unique_integer([:positive])}.json"
      })

    {:ok, deployment} = Deployment.new("deployment-001")

    platform = %Ltix.Test.Platform{
      registration: registration,
      deployment: deployment,
      jwk: platform_jwk
    }

    StorageAdapter.set_pid(start_supervised!({StorageAdapter, platforms: [platform]}))

    {:ok, login} =
      Ltix.handle_login(
        %{
          "iss" => registration.issuer,
          "client_id" => registration.client_id,
          "login_hint" => "user-hint",
          "target_link_uri" => "https://tool.example.com/launch"
        },
        "https://tool.example.com/launch",
        storage_adapter: StorageAdapter
      )

    nonce = Ltix.Test.extract_nonce(login.redirect_uri)
    state = login.state

    Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("cache-control", "max-age=300")
      |> Req.Test.json(jwks)
    end)

    claims = Ltix.Test.valid_lti_claims(platform, %{"nonce" => nonce})

    %{
      platform: platform,
      registration: registration,
      deployment: deployment,
      platform_jwk: platform_jwk,
      nonce: nonce,
      state: state,
      claims: claims
    }
  end

  # [Cert, Known "Bad" Payloads](https://standards.1edtech.org/lti/specifications/guides/conformance/conformance-guide#known-bad-payloads)
  describe "Known Bad Payloads" do
    test "No KID Sent in JWT header", ctx do
      id_token = Ltix.Test.sign_id_token(ctx.claims, ctx.platform_jwk, kid: nil)
      params = %{"id_token" => id_token, "state" => ctx.state}

      assert {:error, %Security.KidMissing{}} = handle_callback(params, ctx.state)
    end

    test "Incorrect KID in JWT header", ctx do
      id_token = Ltix.Test.sign_id_token(ctx.claims, ctx.platform_jwk, kid: "wrong-kid")
      params = %{"id_token" => id_token, "state" => ctx.state}

      assert {:error, %Security.KidNotFound{kid: "wrong-kid"}} =
               handle_callback(params, ctx.state)
    end

    test "Wrong LTI Version", ctx do
      claims = put_lti_claim(ctx.claims, "version", "1.2.0")
      params = sign_params(claims, ctx)

      assert {:error, %InvalidClaim{claim: "version", value: "1.2.0"}} =
               handle_callback(params, ctx.state)
    end

    test "No LTI Version", ctx do
      claims = Map.delete(ctx.claims, @lti <> "version")
      params = sign_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "version"}} =
               handle_callback(params, ctx.state)
    end

    test "Invalid LTI message", ctx do
      params = %{"id_token" => "not-a-jwt", "state" => ctx.state}

      assert {:error, %InvalidJSON{}} = handle_callback(params, ctx.state)
    end

    test "Missing LTI Claims", ctx do
      claims =
        ctx.claims
        |> Map.delete(@lti <> "message_type")
        |> Map.delete(@lti <> "version")
        |> Map.delete(@lti <> "deployment_id")

      params = sign_params(claims, ctx)

      assert {:error,
              %Ltix.Errors.Invalid{
                errors: [
                  %MissingClaim{claim: "message_type"},
                  %MissingClaim{claim: "version"},
                  %MissingClaim{claim: "deployment_id"}
                ]
              }} = handle_callback(params, ctx.state)
    end

    test "Timestamps Incorrect", ctx do
      claims = Map.put(ctx.claims, "exp", System.system_time(:second) - 3600)
      params = sign_params(claims, ctx)

      assert {:error, %Security.TokenExpired{}} = handle_callback(params, ctx.state)
    end

    # [sic], matches cert suite spelling
    test "messsage_type Claim Missing", ctx do
      claims = Map.delete(ctx.claims, @lti <> "message_type")
      params = sign_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "message_type"}} =
               handle_callback(params, ctx.state)
    end

    test "role Claim Missing", ctx do
      claims = Map.delete(ctx.claims, @lti <> "roles")
      params = sign_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "roles"}} =
               handle_callback(params, ctx.state)
    end

    test "deployment_id Claim Missing", ctx do
      claims = Map.delete(ctx.claims, @lti <> "deployment_id")
      params = sign_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "deployment_id"}} =
               handle_callback(params, ctx.state)
    end

    test "resource_link_id Claim Missing", ctx do
      claims = put_lti_claim(ctx.claims, "resource_link", %{"title" => "No ID"})
      params = sign_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "resource_link.id"}} =
               handle_callback(params, ctx.state)
    end

    test "user Claim Missing", ctx do
      claims = Map.delete(ctx.claims, "sub")
      params = sign_params(claims, ctx)

      assert {:error, %MissingClaim{claim: "sub"}} = handle_callback(params, ctx.state)
    end
  end

  # [Cert, Valid Teacher Launches](https://standards.1edtech.org/lti/specifications/guides/conformance/conformance-guide#valid-teacher-launches)
  describe "Valid Teacher Launches" do
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

      params = sign_params(claims, ctx)

      assert {:ok, %Launch{} = launch} = handle_callback(params, ctx.state)

      assert Role.instructor?(launch.claims.roles)
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

      params = sign_params(claims, ctx)

      assert {:ok, %Launch{} = launch} = handle_callback(params, ctx.state)

      assert launch.claims.roles == [
               "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor",
               "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Faculty"
             ]
    end

    test "Valid Instructor Launch Short Role", ctx do
      claims = put_lti_claim(ctx.claims, "roles", ["Instructor"])
      params = sign_params(claims, ctx)

      assert {:ok, %Launch{} = launch} = handle_callback(params, ctx.state)

      assert launch.claims.roles == ["Instructor"]
      assert Role.instructor?(launch.claims.roles)
    end

    test "Valid Instructor Launch Unknown Role", ctx do
      claims =
        put_lti_claim(ctx.claims, "roles", [
          "http://example.com/custom/TeachingAssistant"
        ])

      params = sign_params(claims, ctx)

      assert {:ok, %Launch{} = launch} = handle_callback(params, ctx.state)

      assert launch.claims.roles == ["http://example.com/custom/TeachingAssistant"]
    end

    test "Valid Instructor Launch No Role", ctx do
      claims = put_lti_claim(ctx.claims, "roles", [])
      params = sign_params(claims, ctx)

      assert {:ok, %Launch{} = launch} = handle_callback(params, ctx.state)

      assert launch.claims.roles == []
    end

    test "Valid Instructor Launch Email Only", ctx do
      claims =
        ctx.claims
        |> Map.put("email", "instructor@example.com")
        |> Map.delete("name")
        |> Map.delete("given_name")
        |> Map.delete("family_name")

      params = sign_params(claims, ctx)

      assert {:ok, %Launch{} = launch} = handle_callback(params, ctx.state)

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

      params = sign_params(claims, ctx)

      assert {:ok, %Launch{} = launch} = handle_callback(params, ctx.state)

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

      params = sign_params(claims, ctx)

      assert {:ok, %Launch{}} = handle_callback(params, ctx.state)
    end

    test "Valid Instructor Email Without Context", ctx do
      claims =
        ctx.claims
        |> Map.put("email", "instructor@example.com")
        |> Map.delete(@lti <> "context")

      params = sign_params(claims, ctx)

      assert {:ok, %Launch{} = launch} = handle_callback(params, ctx.state)

      assert launch.claims.email == "instructor@example.com"
      assert launch.claims.context == nil
    end
  end

  # [Cert, Valid Student Launches](https://standards.1edtech.org/lti/specifications/guides/conformance/conformance-guide#valid-student-launches)
  describe "Valid Student Launches" do
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

      params = sign_params(claims, ctx)

      assert {:ok, %Launch{} = launch} = handle_callback(params, ctx.state)

      assert Role.learner?(launch.claims.roles)
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

      params = sign_params(claims, ctx)

      assert {:ok, %Launch{} = launch} = handle_callback(params, ctx.state)

      assert launch.claims.roles == [
               "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner",
               "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Student"
             ]
    end

    test "Valid Student Launch Short Role", ctx do
      claims = put_lti_claim(ctx.claims, "roles", ["Learner"])
      params = sign_params(claims, ctx)

      assert {:ok, %Launch{} = launch} = handle_callback(params, ctx.state)

      assert launch.claims.roles == ["Learner"]
      assert Role.learner?(launch.claims.roles)
    end

    test "Valid Student Launch Unknown Role", ctx do
      claims =
        put_lti_claim(ctx.claims, "roles", [
          "http://example.com/custom/Auditor"
        ])

      params = sign_params(claims, ctx)

      assert {:ok, %Launch{} = launch} = handle_callback(params, ctx.state)

      assert launch.claims.roles == ["http://example.com/custom/Auditor"]
    end

    test "Valid Student Launch No Role", ctx do
      claims = put_lti_claim(ctx.claims, "roles", [])
      params = sign_params(claims, ctx)

      assert {:ok, %Launch{}} = handle_callback(params, ctx.state)
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

      params = sign_params(claims, ctx)

      assert {:ok, %Launch{} = launch} = handle_callback(params, ctx.state)

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

      params = sign_params(claims, ctx)

      assert {:ok, %Launch{} = launch} = handle_callback(params, ctx.state)

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

      params = sign_params(claims, ctx)

      assert {:ok, %Launch{}} = handle_callback(params, ctx.state)
    end

    test "Valid Student Email Without Context", ctx do
      claims =
        ctx.claims
        |> put_lti_claim("roles", [
          "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"
        ])
        |> Map.put("email", "student@example.com")
        |> Map.delete(@lti <> "context")

      params = sign_params(claims, ctx)

      assert {:ok, %Launch{} = launch} = handle_callback(params, ctx.state)

      assert launch.claims.email == "student@example.com"
      assert launch.claims.context == nil
    end
  end

  # -- Helpers --

  defp handle_callback(params, state),
    do: LaunchFlow.callback(params, state, storage_adapter: StorageAdapter)

  defp sign_params(claims, ctx) do
    id_token = Ltix.Test.sign_id_token(claims, ctx.platform_jwk)
    %{"id_token" => id_token, "state" => ctx.state}
  end

  defp put_lti_claim(claims, key, value) do
    Map.put(claims, @lti <> key, value)
  end
end
