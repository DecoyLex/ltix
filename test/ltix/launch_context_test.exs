defmodule Ltix.LaunchContextTest do
  use ExUnit.Case, async: true

  alias Ltix.{Deployment, LaunchClaims, LaunchContext, Registration}
  alias Ltix.Test.JWTHelper

  describe "%LaunchContext{}" do
    test "wraps claims, registration, and deployment" do
      {:ok, registration} =
        Registration.new(%{
          issuer: "https://platform.example.com",
          client_id: "tool-123",
          auth_endpoint: "https://platform.example.com/auth",
          jwks_uri: "https://platform.example.com/.well-known/jwks.json"
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
