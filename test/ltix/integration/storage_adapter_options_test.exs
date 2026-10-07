defmodule Ltix.Integration.StorageAdapterOptionsTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking
  alias Ltix.Errors.Invalid.InvalidOption
  alias Ltix.LaunchClaims.MembershipsEndpoint
  alias Ltix.MembershipsService
  alias Ltix.OAuth
  alias Ltix.OAuth.Client
  alias Ltix.Test.StorageAdapter

  @launch_url "https://tool.example.com/launch"
  @req_options [plug: {Req.Test, :ltix}, retry: false]

  # Sends the options of each callback to the test process.
  defmodule OptionsStorageAdapter do
    @moduledoc false
    @behaviour Ltix.StorageAdapter

    @impl Ltix.StorageAdapter
    def get_registration(issuer, client_id, opts) do
      send(self(), {:get_registration, opts})
      StorageAdapter.get_registration(issuer, client_id, opts)
    end

    @impl Ltix.StorageAdapter
    def get_deployment(registration, deployment_id, opts) do
      send(self(), {:get_deployment, opts})
      StorageAdapter.get_deployment(registration, deployment_id, opts)
    end

    @impl Ltix.StorageAdapter
    def validate_nonce(nonce, registration, expires_at, opts) do
      send(self(), {:validate_nonce, opts})
      StorageAdapter.validate_nonce(nonce, registration, expires_at, opts)
    end

    @impl Ltix.StorageAdapter
    def key_id(registration, opts) do
      send(self(), {:key_id, opts})
      StorageAdapter.key_id(registration, opts)
    end

    @impl Ltix.StorageAdapter
    def sign(registration, key_id, message, opts) do
      send(self(), {:sign, opts})
      StorageAdapter.sign(registration, key_id, message, opts)
    end
  end

  setup do
    platform = Ltix.Test.setup_platform!()
    StorageAdapter.set_pid(start_supervised!({StorageAdapter, platforms: [platform]}))
    Ltix.Test.stub_token_response()

    endpoints = %{
      MembershipsService => MembershipsEndpoint.new!("https://platform.example.com/members")
    }

    %{
      platform: platform,
      endpoints: endpoints,
      adapter: [storage_adapter: OptionsStorageAdapter, storage_adapter_options: [tenant: "acme"]]
    }
  end

  defp login(ctx, params \\ %{}, opts) do
    Ltix.handle_login(
      Map.merge(Ltix.Test.login_params(ctx.platform), params),
      @launch_url,
      opts
    )
  end

  defp launch(ctx, login, opts) do
    params =
      Ltix.Test.launch_params(ctx.platform,
        nonce: Ltix.Test.extract_nonce(login.redirect_uri),
        state: login.state
      )

    Ltix.handle_callback(params, login.state, [req_options: @req_options] ++ opts)
  end

  describe "login and launch" do
    test "pass the storage adapter options to each callback", ctx do
      assert {:ok, login} = login(ctx, ctx.adapter)
      assert_received {:get_registration, [tenant: "acme"]}

      assert {:ok, _context} = launch(ctx, login, ctx.adapter)
      assert_received {:get_registration, opts}
      assert opts[:tenant] == "acme"
      assert_received {:validate_nonce, [tenant: "acme"]}
      assert_received {:get_deployment, [tenant: "acme"]}
    end

    test "pass an empty list without storage adapter options", ctx do
      assert {:ok, login} = login(ctx, storage_adapter: OptionsStorageAdapter)
      assert_received {:get_registration, []}

      assert {:ok, _context} = launch(ctx, login, storage_adapter: OptionsStorageAdapter)
      assert_received {:validate_nonce, []}
      assert_received {:get_deployment, []}
    end

    test "raise for storage adapter options given as a map", ctx do
      opts = Keyword.put(ctx.adapter, :storage_adapter_options, %{tenant: "acme"})

      assert_raise InvalidOption, ~r/Option :storage_adapter_options is invalid/, fn ->
        login(ctx, opts)
      end
    end
  end

  describe "service authentication" do
    test "passes the options to the signing callbacks, and again on refresh", ctx do
      assert {:ok, %Client{} = client} =
               OAuth.authenticate(
                 ctx.platform.registration,
                 [endpoints: ctx.endpoints, req_options: @req_options] ++ ctx.adapter
               )

      assert_received {:key_id, [tenant: "acme"]}
      assert_received {:sign, [tenant: "acme"]}

      assert {:ok, %Client{}} = Client.force_refresh(client)
      assert_received {:key_id, [tenant: "acme"]}
      assert_received {:sign, [tenant: "acme"]}
    end

    test "passes the options from a launch context", ctx do
      context =
        Ltix.Test.build_launch_context(ctx.platform,
          memberships_endpoint: "https://platform.example.com/members"
        )

      assert {:ok, %Client{}} =
               OAuth.authenticate(
                 context,
                 [services: [MembershipsService], req_options: @req_options] ++ ctx.adapter
               )

      assert_received {:sign, [tenant: "acme"]}
    end

    test "passes the options of a client built from a cached token", ctx do
      {:ok, %Client{token: token}} =
        OAuth.authenticate(ctx.platform.registration,
          endpoints: ctx.endpoints,
          storage_adapter: StorageAdapter,
          req_options: @req_options
        )

      assert {:ok, %Client{} = client} =
               Client.from_access_token(
                 token,
                 [
                   registration: ctx.platform.registration,
                   endpoints: ctx.endpoints,
                   req_options: @req_options
                 ] ++ ctx.adapter
               )

      assert {:ok, %Client{}} = Client.force_refresh(client)
      assert_received {:sign, [tenant: "acme"]}
    end
  end

  describe "deep linking responses" do
    test "pass the options to the signing callbacks", ctx do
      context = Ltix.Test.build_launch_context(ctx.platform, message_type: :deep_linking)

      assert {:ok, _response} = DeepLinking.build_response(context, [], ctx.adapter)
      assert_received {:key_id, [tenant: "acme"]}
      assert_received {:sign, [tenant: "acme"]}
    end
  end
end
