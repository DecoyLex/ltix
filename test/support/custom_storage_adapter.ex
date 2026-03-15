defmodule CustomStorageAdapter do
  @moduledoc false

  # Storage adapter that returns custom structs with non-Ltix field names.
  # Used to verify protocols are doing the work, not coincidental field overlap.

  @behaviour Ltix.StorageAdapter

  use Agent

  def start_link(opts) do
    registrations = Keyword.fetch!(opts, :registrations)
    deployments = Keyword.fetch!(opts, :deployments)

    Agent.start_link(fn ->
      %{
        registrations: registrations,
        deployments: deployments,
        nonces: MapSet.new(),
        used_nonces: MapSet.new()
      }
    end)
  end

  def set_pid(pid), do: Process.put(:custom_storage_adapter_pid, pid)
  defp get_pid, do: Process.get(:custom_storage_adapter_pid)

  @impl Ltix.StorageAdapter
  def get_registration(issuer, client_id) do
    Agent.get(get_pid(), fn state ->
      state.registrations
      |> Enum.find(fn reg ->
        reg.platform_issuer == issuer and
          (client_id == nil or reg.oauth_client_id == client_id)
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
      |> Enum.find(fn dep -> dep.platform_deployment_id == deployment_id end)
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

  @impl Ltix.StorageAdapter
  def validate_nonce(nonce, _registration) do
    Agent.get_and_update(get_pid(), fn state ->
      cond do
        MapSet.member?(state.used_nonces, nonce) ->
          {{:error, :nonce_already_used}, state}

        MapSet.member?(state.nonces, nonce) ->
          {:ok,
           %{
             state
             | nonces: MapSet.delete(state.nonces, nonce),
               used_nonces: MapSet.put(state.used_nonces, nonce)
           }}

        true ->
          {{:error, :nonce_not_found}, state}
      end
    end)
  end
end
