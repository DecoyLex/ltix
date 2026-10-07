defmodule CustomStorageAdapter do
  @moduledoc false

  # Storage adapter that returns custom structs with non-Ltix field names.
  # Used to verify that Ltix reads records only through the protocols.

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
  def get_registration(issuer, client_id, _opts) do
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
  def get_deployment(%CustomRegistration{id: registration_id}, deployment_id, _opts) do
    Agent.get(get_pid(), fn state ->
      deployment =
        Enum.find(state.deployments, fn deployment ->
          deployment.registration_id == registration_id and
            deployment.platform_deployment_id == deployment_id
        end)

      case deployment do
        nil -> {:error, :not_found}
        deployment -> {:ok, deployment}
      end
    end)
  end

  @impl Ltix.StorageAdapter
  def validate_nonce(nonce, %CustomRegistration{}, _expires_at, _opts) do
    Agent.get_and_update(get_pid(), fn state ->
      if MapSet.member?(state.used_nonces, nonce),
        do: {{:error, :nonce_already_used}, state},
        else: {:ok, %{state | used_nonces: MapSet.put(state.used_nonces, nonce)}}
    end)
  end
end
