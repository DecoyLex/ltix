defmodule Ltix.Launch.CallbackCustomStructsTest do
  use ExUnit.Case, async: true

  alias Ltix.Launch

  setup do
    custom_reg =
      CustomRegistration.new(
        id: 42,
        platform_issuer: "https://platform.example.com",
        oauth_client_id: "tool-client-id"
      )

    custom_dep = %CustomDeployment{
      id: 99,
      registration_id: 42,
      platform_deployment_id: "deployment-001",
      label: "Production"
    }

    platform = Ltix.Test.setup_platform!(registration: custom_reg, deployment: custom_dep)

    CustomStorageAdapter.set_pid(
      start_supervised!(
        {CustomStorageAdapter, registrations: [custom_reg], deployments: [custom_dep]}
      )
    )

    %{platform: platform, custom_reg: custom_reg, custom_dep: custom_dep}
  end

  describe "custom struct integration" do
    test "the launch has the application's records and the Ltix records built from them", ctx do
      assert {:ok, %Launch{} = launch} =
               LaunchFlow.launch(ctx.platform, [], storage_adapter: CustomStorageAdapter)

      assert launch.source_registration == ctx.custom_reg
      assert launch.source_deployment == ctx.custom_dep

      assert %Ltix.Registration{
               issuer: "https://platform.example.com",
               client_id: "tool-client-id"
             } = launch.registration

      assert launch.deployment == %Ltix.Deployment{deployment_id: "deployment-001"}
      assert launch.claims.message_type == "LtiResourceLinkRequest"
      assert launch.claims.deployment_id == "deployment-001"
    end
  end
end
