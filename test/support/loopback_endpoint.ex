defmodule LoopbackEndpoint do
  @moduledoc false

  # Platform endpoints and refusing ports on this machine's loopback interface.
  # Other programs, such as tools that look for development servers, may connect
  # to any listening port, so the servers respond only to connections from one
  # node and close the rest. Each port stays reserved until the calling process
  # exits.
  #
  # The servers take these options.
  #
  #   * `:address` - the loopback address to listen on (defaults to 127.0.0.1)
  #   * `:client` - the peer process from `PeerNode.start!/1` of the node to
  #     respond to (defaults to this node)

  # Returns a port on a loopback address that refuses every connection.
  def refusing_port(address \\ {127, 0, 0, 1}) do
    family = family(address)
    {:ok, socket} = :socket.open(family, :stream, :tcp)
    :ok = :socket.bind(socket, %{family: family, addr: address, port: 0})
    {:ok, %{port: port}} = :socket.sockname(socket)
    port
  end

  # Serves one JSON body per HTTP connection. Returns the port and a task that
  # returns the requests it received.
  def start_http(bodies, opts \\ []) do
    {listener, port} = listen(opts)

    server =
      Task.async(fn ->
        Enum.map(bodies, fn body ->
          socket = accept(listener, opts)
          {:ok, request} = :gen_tcp.recv(socket, 0, 5000)

          :ok =
            :gen_tcp.send(socket, [
              "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\n",
              "content-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n",
              body
            ])

          :gen_tcp.close(socket)
          request
        end)
      end)

    {port, server}
  end

  # Responds to one HTTPS connection with a 204 response, using
  # `configuration`, such as from `tls_configuration/1`, as the server's TLS
  # options. Returns the port and a task that returns `{:ok, request}` or
  # `{:error, reason}`.
  def start_https(configuration, opts \\ []) do
    {listener, port} = listen(opts)

    server =
      Task.async(fn ->
        with {:ok, socket} <- :ssl.handshake(accept(listener, opts), configuration, 5000),
             {:ok, request} <- :ssl.recv(socket, 0, 5000) do
          :ok =
            :ssl.send(
              socket,
              "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            )

          :ssl.close(socket)
          {:ok, request}
        end
      end)

    {port, server}
  end

  # Returns server TLS options with a certificate for `subject_alt_name`, such
  # as `{:dNSName, ~c"platform.ltix.test"}`. The options' `:cacerts` are the
  # certificate authorities a client needs to verify the certificate.
  def tls_configuration(subject_alt_name) do
    :public_key.pkix_test_data(%{
      root: [key: {:rsa, 2048, 65_537}, digest: :sha256],
      intermediates: [],
      peer: [
        key: {:rsa, 2048, 65_537},
        digest: :sha256,
        extensions: [{:Extension, {2, 5, 29, 17}, false, [subject_alt_name]}]
      ]
    })
  end

  # Whether one of this node's sockets has `address` as its local address.
  def own_socket?(address) do
    Enum.any?(:erlang.ports(), fn port ->
      Port.info(port, :name) == {:name, ~c"tcp_inet"} && :inet.sockname(port) == {:ok, address}
    end) ||
      Enum.any?(:socket.which_sockets(:tcp), fn socket ->
        case :socket.sockname(socket) do
          {:ok, %{addr: ip, port: port}} -> {ip, port} == address
          {:error, _closed} -> false
        end
      end)
  end

  defp listen(opts) do
    address = Keyword.get(opts, :address, {127, 0, 0, 1})

    {:ok, listener} =
      :gen_tcp.listen(0, [family(address), :binary, ip: address, active: false])

    {:ok, port} = :inet.port(listener)
    {listener, port}
  end

  defp family(address) when tuple_size(address) == 8, do: :inet6
  defp family(_address), do: :inet

  # Accepts the next connection from the client node and closes connections
  # from other programs.
  defp accept(listener, opts) do
    {:ok, socket} = :gen_tcp.accept(listener, 5000)

    with {:ok, peer} <- :inet.peername(socket),
         true <- client_socket?(Keyword.get(opts, :client), peer) do
      socket
    else
      _other_program ->
        :gen_tcp.close(socket)
        accept(listener, opts)
    end
  end

  defp client_socket?(nil, address), do: own_socket?(address)
  defp client_socket?(peer, address), do: :peer.call(peer, __MODULE__, :own_socket?, [address])
end
