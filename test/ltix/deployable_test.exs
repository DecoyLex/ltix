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

    test "surfaces validation errors from Deployment.new/1" do
      custom = %CustomDeployment{
        id: 1,
        registration_id: 1,
        platform_deployment_id: "",
        label: "Bad"
      }

      assert {:error, error} = Deployable.to_deployment(custom)
      assert Exception.message(error) =~ "deployment_id"
    end
  end

  test "raises Protocol.UndefinedError for unimplemented types" do
    assert_raise Protocol.UndefinedError, fn ->
      Deployable.to_deployment(%{})
    end
  end
end
