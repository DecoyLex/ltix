defmodule Ltix.DeployableTest do
  use ExUnit.Case, async: true

  alias Ltix.Deployable
  alias Ltix.Deployment

  describe "Ltix.Deployment struct literals" do
    test "are validated like Deployment.new/1" do
      assert {:error, %Ltix.Errors.Invalid.InvalidField{field: :deployment_id, value: ""}} =
               Deployable.to_deployment(%Deployment{deployment_id: ""})
    end
  end
end
