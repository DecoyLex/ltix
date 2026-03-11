defmodule Ltix.LaunchContextTest do
  use ExUnit.Case, async: true

  alias Ltix.Deployment
  alias Ltix.LaunchClaims
  alias Ltix.LaunchContext
  alias Ltix.Registration
  alias Ltix.Test.JWTHelper

  @tool_jwk elem(Ltix.JWK.generate_key_pair(), 0)

  describe "%LaunchContext{}" do
    test "wraps claims, registration, and deployment" do
      {:ok, registration} =
        Registration.new(%{
          issuer: "https://platform.example.com",
          client_id: "tool-123",
          auth_endpoint: "https://platform.example.com/auth",
          jwks_uri: "https://platform.example.com/.well-known/jwks.json",
          tool_jwk: @tool_jwk
        })

      {:ok, deployment} = Deployment.new("deploy-001")
      {:ok, claims} = LaunchClaims.from_json(JWTHelper.valid_lti_claims())

      context = %LaunchContext{
        claims: claims,
        registration: registration,
        deployment: deployment
      }

      assert context.claims == claims
      assert context.registration == registration
      assert context.deployment == deployment
    end
  end
end
