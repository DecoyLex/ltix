defmodule Ltix.DeployableTest do
  use ExUnit.Case, async: true

  alias Ltix.Deployable
  alias Ltix.Deployment

  describe "Ltix.Deployment identity implementation" do
    test "returns the deployment unchanged" do
      {:ok, dep} = Deployment.new("deploy-001")
      assert Deployable.to_deployment(dep) == {:ok, dep}
    end
  end

  describe "Ltix.Deployment struct literals" do
    test "are validated like Deployment.new/1" do
      assert {:error, %Ltix.Errors.Invalid.InvalidField{field: :deployment_id, value: ""}} =
               Deployable.to_deployment(%Deployment{deployment_id: ""})
    end
  end

  describe "custom struct implementation" do
    test "extracts a Deployment from a custom struct" do
      custom = %CustomDeployment{
        id: 99,
        registration_id: 42,
        platform_deployment_id: "deploy-abc",
        label: "Production"
      }

      assert {:ok, %Deployment{} = dep} = Deployable.to_deployment(custom)
      assert dep.deployment_id == "deploy-abc"
    end
  end
end
