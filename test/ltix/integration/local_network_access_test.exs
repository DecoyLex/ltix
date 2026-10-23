defmodule Ltix.Integration.LocalNetworkAccessTest do
  use ExUnit.Case, async: false

  alias Ltix.Errors.Security.LocalNetworkAccessDenied
  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.JWK
  alias Ltix.Launch
  alias Ltix.MembershipsService
  alias Ltix.MembershipsService.Endpoint, as: MembershipsServiceEndpoint
  alias Ltix.OAuth
  alias Ltix.Pagination
  alias Ltix.Test.StorageAdapter

  defmodule Adapter do
    def run(request), do: {request, Req.Response.json(%{"adapter" => true})}
  end

  @launch_url "https://tool.example.com/launch"
  @memberships_scope "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"

  setup do
    previous = Application.fetch_env(:ltix, :local_network_access)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:ltix, :local_network_access, value)
        :error -> Application.delete_env(:ltix, :local_network_access)
      end
    end)
  end

  # [LNA §2.1](https://wicg.github.io/local-network-access/#ip-address-space)
  describe "addresses" do
    for host <- ~w(127.8.8.8 0.0.0.0 198.18.0.1 [::1] [::ffff:127.0.0.1]) do
      test "rejects the loopback address #{host} unless loopback access is granted" do
        url = "https://#{unquote(host)}:1/members"

        for access <- [:none, :local] do
          assert {:error, %LocalNetworkAccessDenied{url: ^url, address_space: :loopback}} =
                   stream(url, access)
        end

        assert {:error, %TransportError{}} = stream(url, :loopback)
      end
    end

    for host <-
          ~w(10.0.0.1 100.64.0.1 172.31.255.255 192.168.1.1 169.254.169.254 0.1.2.3) ++
            ~w([fd12:3456::1] [fe80::1] [fec0::1]) do
      test "rejects the local address #{host} unless local access is granted" do
        url = "https://#{unquote(host)}:1/members"

        assert {:error, %LocalNetworkAccessDenied{url: ^url, address_space: :local}} =
                 stream(url, :none)
      end
    end

    test "rejects a host name that resolves to a loopback address unless loopback access is granted" do
      resolve("platform.ltix.test", {127, 0, 0, 1})
      url = "https://platform.ltix.test:#{LoopbackEndpoint.refusing_port()}/members"

      for access <- [:none, :local] do
        assert {:error, %LocalNetworkAccessDenied{url: ^url, address_space: :loopback}} =
                 stream(url, access)
      end

      assert {:error, %TransportError{} = error} = stream(url, :loopback)
      assert Exception.message(error) =~ "connection refused"
    end

    test "rejects the host name localhost unless loopback access is granted" do
      {port, server} = LoopbackEndpoint.start_http(["{}"])
      url = "http://localhost:#{port}/members"

      assert {:error, %LocalNetworkAccessDenied{address_space: :loopback}} = stream(url, :none)
      assert {:ok, pages} = stream(url, :loopback)
      assert Enum.to_list(pages) == [%{}]
      assert [_request] = Task.await(server)
    end

    test "connects to IPv6 loopback when loopback access is granted" do
      {port, server} = LoopbackEndpoint.start_http(["{}"], address: {0, 0, 0, 0, 0, 0, 0, 1})

      assert {:ok, pages} = stream("http://[::1]:#{port}/members", :loopback)
      assert Enum.to_list(pages) == [%{}]
      assert [_request] = Task.await(server)
    end

    test "applies the configured access when a call passes none" do
      {port, server} = LoopbackEndpoint.start_http(["{}"])
      url = "http://127.0.0.1:#{port}/members"

      assert {:error, %LocalNetworkAccessDenied{}} = Pagination.stream(url, [])

      Application.put_env(:ltix, :local_network_access, :loopback)
      assert {:ok, pages} = Pagination.stream(url, [])
      assert Enum.to_list(pages) == [%{}]
      assert [_request] = Task.await(server)
    end

    test "rejects options that make their own connections unless loopback access is granted" do
      url = "https://platform.example.com/members"

      for opts <- [
            [finch: MyApp.Finch],
            [adapter: __MODULE__.Adapter],
            [unix_socket: "/run/platform.sock"],
            [connect_options: [proxy: {:http, "proxy.example.com", 8888, []}]]
          ] do
        assert {:error, %TransportError{} = error} =
                 Pagination.stream(url, [], req_options: [retry: false] ++ opts)

        assert Exception.message(error) =~ "local_network_access: :loopback"
      end
    end

    test "sends a request through a custom adapter when loopback access is granted" do
      assert {:ok, pages} =
               Pagination.stream("https://platform.example.com/members", [],
                 req_options: [adapter: __MODULE__.Adapter],
                 local_network_access: :loopback
               )

      assert Enum.to_list(pages) == [%{"adapter" => true}]
    end
  end

  describe "plain HTTP" do
    test "is accepted only for loopback and local hosts" do
      for url <- ~w(http://platform.example.com/members http://8.8.8.8/members) do
        assert {:error, %TransportError{}} = stream(url, :loopback)
      end

      for {url, space} <- [
            {"http://10.0.0.1:1/members", :local},
            {"http://app.localhost:1/members", :loopback}
          ] do
        assert {:error, %LocalNetworkAccessDenied{address_space: ^space}} = stream(url, :none)
      end
    end
  end

  describe "launches and services" do
    setup do
      platform_jwk = JWK.generate()
      {port, server} = LoopbackEndpoint.start_http([Jason.encode!(JWK.to_jwks(platform_jwk))])

      registration =
        Ltix.Registration.new!(
          issuer: "http://localhost:#{port}",
          client_id: "tool-client-id",
          auth_endpoint: "http://localhost:#{port}/auth",
          jwks_uri: "http://localhost:#{port}/jwks",
          token_endpoint: "http://localhost:#{port}/token"
        )

      platform = %Ltix.Test.Platform{
        registration: registration,
        deployment: Ltix.Deployment.new!("deployment-001"),
        jwk: platform_jwk
      }

      StorageAdapter.set_pid(start_supervised!({StorageAdapter, platforms: [platform]}))
      %{platform: platform, port: port, server: server}
    end

    test "a launch fetches a loopback key set only with loopback access", ctx do
      {state, params} = launch(ctx.platform)
      opts = [storage_adapter: StorageAdapter, req_options: [retry: false]]

      assert {:error, %LocalNetworkAccessDenied{address_space: :loopback}} =
               Ltix.handle_callback(params, state, opts)

      {state, params} = launch(ctx.platform)

      assert {:ok, %Launch{}} =
               Ltix.handle_callback(params, state, [local_network_access: :loopback] ++ opts)

      assert [request] = Task.await(ctx.server)
      assert request =~ "GET /jwks HTTP/1.1"
    end

    test "a client keeps the access it was authenticated with", ctx do
      Task.shutdown(ctx.server)

      token = Jason.encode!(%{access_token: "token", token_type: "Bearer", expires_in: 3600})
      roster = Jason.encode!(%{id: "roster", context: %{id: "course"}, members: []})
      {port, server} = LoopbackEndpoint.start_http([token, roster])

      registration = %{
        ctx.platform.registration
        | token_endpoint: "http://127.0.0.1:#{port}/token"
      }

      endpoints = %{
        MembershipsService => MembershipsServiceEndpoint.new!("http://127.0.0.1:#{port}/members")
      }

      opts = [endpoints: endpoints, req_options: [retry: false]]

      assert {:error, %LocalNetworkAccessDenied{}} = OAuth.authenticate(registration, opts)

      assert {:ok, client} =
               OAuth.authenticate(registration, [local_network_access: :loopback] ++ opts)

      assert {:ok, %{members: []}} = MembershipsService.list_members(client)
      assert [token_request, roster_request] = Task.await(server)
      assert token_request =~ "POST /token HTTP/1.1"
      assert roster_request =~ "GET /members"
      assert @memberships_scope in MapSet.to_list(client.token.granted_scopes)
    end
  end

  defp stream(url, access) do
    Pagination.stream(url, [],
      local_network_access: access,
      req_options: [retry: false, connect_options: [timeout: 200]]
    )
  end

  # Makes a host name resolve to an address until the test exits.
  defp resolve(host, address) do
    lookup = :inet_db.res_option(:lookup)
    :inet_db.set_lookup([:file | lookup])
    :inet_db.add_host(address, [String.to_charlist(host)])

    on_exit(fn ->
      :inet_db.del_host(address)
      :inet_db.set_lookup(lookup)
    end)
  end

  defp launch(platform) do
    params = Map.put(Ltix.Test.login_params(platform), "client_id", "tool-client-id")
    {:ok, login} = Ltix.handle_login(params, @launch_url, storage_adapter: StorageAdapter)

    launch =
      Ltix.Test.launch_params(platform,
        nonce: Ltix.Test.extract_nonce(login.redirect_uri),
        state: login.state
      )

    {login.state, launch}
  end
end
