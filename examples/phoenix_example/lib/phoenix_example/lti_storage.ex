defmodule PhoenixExample.LtiStorage do
  @moduledoc """
  In-memory LTI storage adapter for demo purposes.

  Stores a hardcoded registration and deployment, and tracks nonces in
  an Agent. Replace this with a database-backed implementation in a real
  application.
  """

  @behaviour Ltix.StorageAdapter

  use Agent

  # --- Demo registration ---
  # Replace these values with your platform's actual configuration.

  @demo_issuer "https://example.com"
  @demo_client_id "test"
  @demo_deployment_id "test-deployment"

  @demo_registration %Ltix.Registration{
    issuer: @demo_issuer,
    client_id: @demo_client_id,
    auth_endpoint: "https://example.com/auth",
    jwks_uri: "https://example.com/.well-known/jwks.json"
  }

  @demo_deployment %Ltix.Deployment{deployment_id: @demo_deployment_id}

  # --- Agent lifecycle ---

  def start_link(_opts) do
    Agent.start_link(fn -> MapSet.new() end, name: __MODULE__)
  end

  # --- StorageAdapter callbacks ---

  @impl true
  def get_registration(@demo_issuer, _client_id), do: {:ok, @demo_registration}
  def get_registration(_issuer, _client_id), do: {:error, :not_found}

  @impl true
  def get_deployment(@demo_registration, @demo_deployment_id), do: {:ok, @demo_deployment}
  def get_deployment(_registration, _deployment_id), do: {:error, :not_found}

  @impl true
  def store_nonce(nonce, _registration) do
    Agent.update(__MODULE__, &MapSet.put(&1, nonce))
    :ok
  end

  @impl true
  def validate_nonce(nonce, _registration) do
    Agent.get_and_update(__MODULE__, fn nonces ->
      if MapSet.member?(nonces, nonce) do
        {:ok, MapSet.delete(nonces, nonce)}
      else
        {{:error, :nonce_not_found}, nonces}
      end
    end)
  end
end
