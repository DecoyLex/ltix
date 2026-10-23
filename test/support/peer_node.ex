defmodule PeerNode do
  @moduledoc false

  # Nodes that run this project's code with a setting the test node can't
  # change for one test. A node stops when the process that started it exits.

  # Starts a node whose sockets use `backend`, `:inet` or `:socket`, and
  # returns its peer process. The node looks up host names in its hosts table
  # first, so `resolve/3` can add names.
  def start!(backend) do
    {:ok, peer, _name} =
      :peer.start_link(%{
        connection: :standard_io,
        args: [~c"-kernel", ~c"inet_backend", Atom.to_charlist(backend)]
      })

    :ok = :peer.call(peer, :code, :add_paths, [:code.get_path()])
    {:ok, _applications} = :peer.call(peer, Application, :ensure_all_started, [:ltix])
    lookup = :peer.call(peer, :inet_db, :res_option, [:lookup])
    :ok = :peer.call(peer, :inet_db, :set_lookup, [[:file | lookup]])
    peer
  end

  # Makes a host name resolve to an address on the node.
  def resolve(peer, host, address) do
    :ok = :peer.call(peer, :inet_db, :add_host, [address, [String.to_charlist(host)]])
  end
end
