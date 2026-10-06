defmodule Ltix.HTTP.AddressSpace.LoopbackSocket do
  @moduledoc false

  alias Ltix.HTTP.AddressSpace

  defdelegate getserv(port), to: :inet_tcp
  defdelegate getaddrs(address, timer), to: AddressSpace

  def connect(address, port, options, timeout),
    do: AddressSpace.connect(:loopback, address, port, options, timeout)
end
