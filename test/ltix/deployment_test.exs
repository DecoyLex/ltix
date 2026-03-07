defmodule Ltix.DeploymentTest do
  use ExUnit.Case, async: true

  alias Ltix.Deployment

  doctest Ltix.Deployment

  describe "new/1" do
    test "valid deployment" do
      assert {:ok, %Deployment{deployment_id: "deploy-123"}} =
               Deployment.new("deploy-123")
    end

    # [Core §5.3.3] deployment_id MUST be non-empty
    test "rejects empty deployment_id" do
      assert {:error, error} = Deployment.new("")
      assert Exception.message(error) =~ "deployment_id"
    end

    test "rejects nil deployment_id" do
      assert {:error, error} = Deployment.new(nil)
      assert Exception.message(error) =~ "deployment_id"
    end

    # [Core §5.3.3] deployment_id MUST NOT exceed 255 ASCII characters
    test "accepts deployment_id at 255 characters" do
      id = String.duplicate("a", 255)
      assert {:ok, %Deployment{deployment_id: ^id}} = Deployment.new(id)
    end

    test "rejects deployment_id exceeding 255 characters" do
      id = String.duplicate("a", 256)
      assert {:error, error} = Deployment.new(id)
      assert Exception.message(error) =~ "255"
    end

    # [Core §5.3.3] deployment_id is ASCII — non-ASCII chars should be rejected
    test "rejects non-ASCII deployment_id" do
      assert {:error, error} = Deployment.new("deploy-café")
      assert Exception.message(error) =~ "ASCII"
    end
  end
end
