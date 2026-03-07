defmodule Ltix.Test.TestStorageAdapter do
  @moduledoc """
  In-memory `StorageAdapter` implementation for tests.

  Uses an `Agent` to store registrations, deployments, and nonces.
  Each test should start its own adapter via `start_link/1`.
  """

  @behaviour Ltix.StorageAdapter

  use Agent

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

  def set_pid(pid), do: Process.put(:test_storage_adapter_pid, pid)
  defp get_pid, do: Process.get(:test_storage_adapter_pid)

  @impl true
  def get_registration(issuer, client_id) do
    Agent.get(get_pid(), fn state ->
      Enum.find(state.registrations, fn reg ->
        reg.issuer == issuer and (client_id == nil or reg.client_id == client_id)
      end)
      |> case do
        nil -> {:error, :not_found}
        reg -> {:ok, reg}
      end
    end)
  end

  @impl true
  def get_deployment(registration, deployment_id) do
    Agent.get(get_pid(), fn state ->
      Enum.find(state.deployments, fn dep ->
        dep.deployment_id == deployment_id
      end)
      |> case do
        nil -> {:error, :not_found}
        dep -> {:ok, dep}
      end
    end)
    |> tap(fn _ -> _ = registration end)
  end

  @impl true
  def store_nonce(nonce, _registration) do
    Agent.update(get_pid(), fn state ->
      %{state | nonces: MapSet.put(state.nonces, nonce)}
    end)
  end

  @impl true
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

  def stored_nonces do
    Agent.get(get_pid(), fn state -> state.nonces end)
  end
end
