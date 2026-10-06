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
  def get_deployment(registration, deployment_id) do
    Agent.get(get_pid(), fn state ->
      owner =
        Enum.find(state.registrations, fn stored ->
          stored.platform_issuer == registration.issuer and
            stored.oauth_client_id == registration.client_id
        end)

      deployment =
        Enum.find(state.deployments, fn deployment ->
          owner != nil and deployment.registration_id == owner.id and
            deployment.platform_deployment_id == deployment_id
        end)

      case deployment do
        nil -> {:error, :not_found}
        deployment -> {:ok, deployment}
      end
    end)
  end

  @impl Ltix.StorageAdapter
  def validate_nonce(nonce, _registration, _expires_at) do
    Agent.get_and_update(get_pid(), fn state ->
      if MapSet.member?(state.used_nonces, nonce),
        do: {{:error, :nonce_already_used}, state},
        else: {:ok, %{state | used_nonces: MapSet.put(state.used_nonces, nonce)}}
    end)
  end
end
