defmodule Ltix.HTTP.AddressSpace do
  @moduledoc false

  # Address spaces follow the Local Network Access specification.
  # [LNA §2.1](https://wicg.github.io/local-network-access/#ip-address-space)

  import Bitwise

  @type t :: :public | :local | :loopback
  @type access :: :none | :local | :loopback

  @ipv4_blocks [
    {{127, 0, 0, 0}, 8, :loopback},
    {{10, 0, 0, 0}, 8, :local},
    {{100, 64, 0, 0}, 10, :local},
    {{172, 16, 0, 0}, 12, :local},
    {{192, 168, 0, 0}, 16, :local},
    {{198, 18, 0, 0}, 15, :loopback},
    {{169, 254, 0, 0}, 16, :local},
    {{0, 0, 0, 0}, 32, :loopback},
    {{0, 0, 0, 0}, 8, :local}
  ]

  @ipv6_blocks [
    {{0, 0, 0, 0, 0, 0, 0, 1}, 128, :loopback},
    {{0xFC00, 0, 0, 0, 0, 0, 0, 0}, 7, :local},
    {{0xFE80, 0, 0, 0, 0, 0, 0, 0}, 10, :local},
    {{0xFEC0, 0, 0, 0, 0, 0, 0, 0}, 10, :local},
    {{0, 0, 0, 0, 0, 0, 0, 0}, 128, :loopback},
    {{0x2001, 0xDB8, 0, 0, 0, 0, 0, 0}, 32, :local},
    {{0x3FFF, 0, 0, 0, 0, 0, 0, 0}, 20, :local}
  ]

  @doc """
  Returns the address space of an IP address.
  """
  @spec classify(:inet.ip_address()) :: t()
  def classify({0, 0, 0, 0, 0, 0xFFFF, _high, _low} = address) do
    classify(:inet.ipv4_mapped_ipv6_address(address))
  end

  def classify(address) when tuple_size(address) == 4, do: classify(address, @ipv4_blocks, 8)
  def classify(address) when tuple_size(address) == 8, do: classify(address, @ipv6_blocks, 16)

  defp classify(address, blocks, bits) do
    number = to_integer(address, bits)
    size = tuple_size(address) * bits

    Enum.find_value(blocks, :public, fn {block, prefix, space} ->
      shift = size - prefix
      if number >>> shift == to_integer(block, bits) >>> shift, do: space
    end)
  end

  defp to_integer(address, bits) do
    address
    |> Tuple.to_list()
    |> Enum.reduce(0, fn part, number -> (number <<< bits) + part end)
  end

  @doc """
  Returns whether `access` allows requests to an address space.
  """
  @spec allowed?(t(), access()) :: boolean()
  def allowed?(:public, _access), do: true
  def allowed?(:local, access), do: access in [:local, :loopback]
  def allowed?(:loopback, access), do: access == :loopback

  # `:ssl` takes its transport as a module, so each access level has one.
  @transports [
    none: __MODULE__.PublicTransport,
    local: __MODULE__.LocalTransport,
    loopback: __MODULE__.LoopbackTransport
  ]

  @doc """
  Returns the TLS transport options for a connection that refuses the
  addresses `access` doesn't allow.

  The check runs on each address the connection's host resolves to, before
  connecting to it.
  """
  @spec tls_transport_options(access()) :: keyword()
  def tls_transport_options(access) do
    [cb_info: {Keyword.fetch!(@transports, access), :tcp, :tcp_closed, :tcp_error, :tcp_passive}]
  end

  # [`:ssl` `cb_info`](https://www.erlang.org/doc/apps/ssl/ssl.html#t:transport_option/0)
  for {access, transport} <- @transports do
    defmodule transport do
      @moduledoc false

      alias Ltix.HTTP.AddressSpace

      @access access

      def connect(host, port, options, timeout),
        do: AddressSpace.connect(@access, host, port, options, timeout)

      defdelegate send(socket, data), to: :gen_tcp
      defdelegate recv(socket, length, timeout), to: :gen_tcp
      defdelegate controlling_process(socket, pid), to: :gen_tcp
      defdelegate shutdown(socket, how), to: :gen_tcp
      defdelegate close(socket), to: :gen_tcp
      defdelegate setopts(socket, options), to: :inet
      defdelegate getopts(socket, options), to: :inet
      defdelegate peername(socket), to: :inet
      defdelegate sockname(socket), to: :inet
      defdelegate port(socket), to: :inet
    end
  end

  @doc false
  # Connects like `:gen_tcp.connect/4` to the addresses `host` resolves to,
  # skipping the ones `access` doesn't allow. Without a family option, the
  # IPv6 addresses are tried when the host has no IPv4 address.
  def connect(access, host, port, options, timeout) do
    deadline = deadline(timeout)
    # Removes the family options so `:gen_tcp.connect/4` uses the TCP module
    # for each address's family.
    {families, options} = Enum.split_with(options, &(&1 in [:inet, :inet6]))

    with {:ok, addresses} <- getaddrs(host, families) do
      Enum.reduce_while(addresses, {:error, :einval}, fn address, _error ->
        try_address(access, address, port, options, remaining(deadline))
      end)
    end
  end

  defp getaddrs(host, []) do
    with {:error, _reason} <- :inet.getaddrs(host, :inet) do
      :inet.getaddrs(host, :inet6)
    end
  end

  defp getaddrs(host, [family | _families]), do: :inet.getaddrs(host, family)

  # Stops at a connection or at an `:einval` or `:timeout` error, to match
  # `:gen_tcp.connect/4`. Moves to the next address after any other error or an
  # address `access` doesn't allow.
  defp try_address(access, address, port, options, timeout) do
    space = classify(address)

    if allowed?(space, access) do
      case :gen_tcp.connect(address, port, options, timeout) do
        {:error, reason} = error when reason not in [:einval, :timeout] -> {:cont, error}
        result -> {:halt, result}
      end
    else
      {:cont, {:error, {:ltix_address_space, space}}}
    end
  end

  defp deadline(:infinity), do: :infinity
  defp deadline(timeout), do: System.monotonic_time(:millisecond) + timeout

  defp remaining(:infinity), do: :infinity
  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
