defmodule Ltix.Integration.InetBackendTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Security.LocalNetworkAccessDenied
  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.OAuth.Client

  # Platform requests from nodes started with `-kernel inet_backend inet` and
  # `-kernel inet_backend socket`.
  setup_all do
    %{nodes: %{inet: PeerNode.start!(:inet), socket: PeerNode.start!(:socket)}}
  end

  for backend <- [:inet, :socket] do
    describe "with the #{backend} backend" do
      setup %{nodes: nodes} do
        %{node: Map.fetch!(nodes, unquote(backend))}
      end

      for {host, address} <- [
            {"loopback.ltix.test", {127, 0, 0, 1}},
            {"ipv6.ltix.test", {0, 0, 0, 0, 0, 0, 0, 1}}
          ] do
        test "rejects a host name that resolves only to #{:inet.ntoa(address)} unless loopback access is granted",
             %{node: node} do
          address = unquote(Macro.escape(address))
          PeerNode.resolve(node, unquote(host), address)
          url = "https://#{unquote(host)}:#{LoopbackEndpoint.refusing_port(address)}/members"

          for access <- [:none, :local] do
            assert {:error, %LocalNetworkAccessDenied{url: ^url, address_space: :loopback}} =
                     request(node, url, access)
          end

          assert {:error, %TransportError{} = error} = request(node, url, :loopback)
          assert Exception.message(error) =~ "connection refused"
        end
      end

      test "sends an HTTPS request to a host name whose address is allowed", %{node: node} do
        PeerNode.resolve(node, "platform.ltix.test", {127, 0, 0, 1})
        configuration = LoopbackEndpoint.tls_configuration({:dNSName, ~c"platform.ltix.test"})
        {port, server} = LoopbackEndpoint.start_https(configuration, client: node)

        assert {:ok, %Req.Response{status: 204}} =
                 request(node, "https://platform.ltix.test:#{port}/members", :loopback,
                   cacerts: configuration[:cacerts]
                 )

        assert {:ok, request} = Task.await(server)
        assert request =~ "GET /members HTTP/1.1"
        assert request =~ "authorization: Bearer test-token"
      end

      test "sends HTTP requests to loopback addresses", %{node: node} do
        for {address, host} <- [
              {{127, 0, 0, 1}, "127.0.0.1"},
              {{0, 0, 0, 0, 0, 0, 0, 1}, "[::1]"}
            ] do
          {port, server} = LoopbackEndpoint.start_http(["{}"], address: address, client: node)

          assert {:ok, %Req.Response{status: 200, body: %{}}} =
                   request(node, "http://#{host}:#{port}/members", :loopback)

          assert [request] = Task.await(server)
          assert request =~ "GET /members HTTP/1.1"
        end
      end
    end
  end

  # Sends a GET request to `url` from `node` with `Ltix.OAuth.Client.request/3`.
  defp request(node, url, access, transport_opts \\ []) do
    registration =
      Ltix.Registration.new!(
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri: "https://platform.example.com/jwks",
        token_endpoint: "https://platform.example.com/token"
      )

    client =
      TestClient.build(registration, %{},
        local_network_access: access,
        req_options: [
          retry: false,
          connect_options: [timeout: 1000, transport_opts: transport_opts]
        ]
      )

    :peer.call(node, Client, :request, [client, __MODULE__, [url: url]])
  end
end
