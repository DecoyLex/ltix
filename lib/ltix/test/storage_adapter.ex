defmodule Ltix.Test.StorageAdapter do
  @moduledoc """
  In-memory `StorageAdapter` for tests.

  Uses an `Agent` to store registrations, deployments, and nonces. Each
  test should start its own adapter via `start_link/1` and register it
  with `set_pid/1`.

  `Ltix.Test.setup_platform!/1` handles this automatically.

  ## Manual usage

      {:ok, pid} = Ltix.Test.StorageAdapter.start_link(
        registrations: [registration],
        deployments: [deployment]
      )
      Ltix.Test.StorageAdapter.set_pid(pid)
  """

  @behaviour Ltix.StorageAdapter

  use Agent

  @doc """
  Start the storage adapter agent.

  ## Options

    * `:registrations` — list of `%Registration{}` structs (default: `[]`)
    * `:deployments` — list of `%Deployment{}` structs (default: `[]`)
  """
  def start_link(opts \\ []) do
    registrations = Keyword.get(opts, :registrations, [])
    deployments = Keyword.get(opts, :deployments, [])

    Agent.start_link(fn ->
      %{
        registrations: registrations,
        deployments: deployments,
        nonces: MapSet.new(),
        used_nonces: MapSet.new()
      }
    end)
  end

  @doc "Register the adapter PID in the calling process."
  def set_pid(pid), do: Process.put(:ltix_test_storage_adapter_pid, pid)
  defp get_pid, do: Process.get(:ltix_test_storage_adapter_pid)

  @impl Ltix.StorageAdapter
  def get_registration(issuer, client_id) do
    Agent.get(get_pid(), fn state ->
      state.registrations
      |> Enum.find(fn reg ->
        reg.issuer == issuer and (client_id == nil or reg.client_id == client_id)
      end)
      |> case do
        nil -> {:error, :not_found}
        reg -> {:ok, reg}
      end
    end)
  end

  @impl Ltix.StorageAdapter
  def get_deployment(_registration, deployment_id) do
    Agent.get(get_pid(), fn state ->
      state.deployments
      |> Enum.find(fn dep -> dep.deployment_id == deployment_id end)
      |> case do
        nil -> {:error, :not_found}
        dep -> {:ok, dep}
      end
    end)
  end

  @impl Ltix.StorageAdapter
  def store_nonce(nonce, _registration) do
    Agent.update(get_pid(), fn state ->
      %{state | nonces: MapSet.put(state.nonces, nonce)}
    end)
  end

  @doc "Return the set of stored (unused) nonces."
  def stored_nonces do
    Agent.get(get_pid(), fn state -> state.nonces end)
  end

  @impl Ltix.StorageAdapter
  def validate_nonce(nonce, _registration) do
    Agent.get_and_update(get_pid(), fn state ->
      cond do
        MapSet.member?(state.used_nonces, nonce) ->
          {{:error, :nonce_already_used}, state}

        MapSet.member?(state.nonces, nonce) ->
          new_state = %{
            state
            | nonces: MapSet.delete(state.nonces, nonce),
              used_nonces: MapSet.put(state.used_nonces, nonce)
          }

          {:ok, new_state}

        true ->
          {{:error, :nonce_not_found}, state}
      end
    end)
  end
end
