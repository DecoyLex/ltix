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

  @doc """
  Returns the transport options that refuse connections `access` doesn't allow.

  The check runs on the address a connection is made to, after the host
  name is resolved.
  """
  @spec transport_options(access()) :: keyword()
  def transport_options(:none), do: [tcp_module: __MODULE__.PublicSocket]
  def transport_options(:local), do: [tcp_module: __MODULE__.LocalSocket]
  def transport_options(:loopback), do: [tcp_module: __MODULE__.LoopbackSocket]

  @doc false
  def getaddrs(address, _timer) when is_tuple(address), do: {:ok, [address]}

  def getaddrs(address, timer) do
    with {:error, _reason} <- :inet_tcp.getaddrs(address, timer) do
      :inet6_tcp.getaddrs(address, timer)
    end
  end

  @doc false
  def connect(access, address, port, options, timeout) do
    space = classify(address)

    cond do
      not allowed?(space, access) -> {:error, {:ltix_address_space, space}}
      tuple_size(address) == 8 -> :inet6_tcp.connect(address, port, options, timeout)
      true -> :inet_tcp.connect(address, port, options, timeout)
    end
  end
end
