defmodule Ltix.DeploymentTest do
  use ExUnit.Case, async: true

  alias Ltix.Deployment
  alias Ltix.Errors.Invalid.InvalidField

  doctest Ltix.Deployment

  describe "new/1" do
    test "requires a deployment_id" do
      assert {:error, %InvalidField{struct: Deployment, field: :deployment_id, reason: :required}} =
               Deployment.new(nil)
    end

    test "new!/1 returns the deployment or raises the error" do
      assert %Deployment{deployment_id: "deploy-123"} = Deployment.new!("deploy-123")

      assert_raise InvalidField, ~r/Ltix.Deployment field :deployment_id is invalid/, fn ->
        Deployment.new!("")
      end
    end

    # [Core §5.3.3] deployment_id MUST NOT exceed 255 ASCII characters
    test "accepts deployment_id at 255 characters" do
      id = String.duplicate("a", 255)
      assert {:ok, %Deployment{deployment_id: ^id}} = Deployment.new(id)
    end

    # [Core §5.3.3](https://www.imsglobal.org/spec/lti/v1p3/#lti-deployment-id-claim)
    test "reports an invalid deployment_id with its value" do
      for {value, reason} <- [
            {"", "must be a non-empty string"},
            {123, "must be a non-empty string"},
            {String.duplicate("a", 256), "must not exceed 255 ASCII characters"},
            {"deploy-café", "must contain only ASCII characters"}
          ] do
        assert {:error, %InvalidField{field: :deployment_id, value: ^value, reason: ^reason}} =
                 Deployment.new(value)
      end
    end
  end
end
