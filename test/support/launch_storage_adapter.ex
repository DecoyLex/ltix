defmodule LaunchStorageAdapter do
  @moduledoc false

  # Implements only the callbacks a launch needs by calling
  # `Ltix.Test.StorageAdapter`, and sends each deployment ID it looks up and
  # each nonce it records to the calling process.

  @behaviour Ltix.StorageAdapter

  alias Ltix.Test.StorageAdapter

  @impl Ltix.StorageAdapter
  defdelegate get_registration(issuer, client_id, opts), to: StorageAdapter

  @impl Ltix.StorageAdapter
  def get_deployment(registration, deployment_id, opts) do
    send(self(), {:get_deployment, deployment_id})
    StorageAdapter.get_deployment(registration, deployment_id, opts)
  end

  @impl Ltix.StorageAdapter
  def validate_nonce(nonce, registration, expires_at, opts) do
    send(self(), {:validate_nonce, nonce, expires_at})
    StorageAdapter.validate_nonce(nonce, registration, expires_at, opts)
  end
end
