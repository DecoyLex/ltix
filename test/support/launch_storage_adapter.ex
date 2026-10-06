defmodule LaunchStorageAdapter do
  @moduledoc false

  # Implements only the callbacks a launch needs by calling
  # `Ltix.Test.StorageAdapter`, and sends each nonce it records to the
  # calling process.

  @behaviour Ltix.StorageAdapter

  alias Ltix.Test.StorageAdapter

  @impl Ltix.StorageAdapter
  defdelegate get_registration(issuer, client_id), to: StorageAdapter

  @impl Ltix.StorageAdapter
  defdelegate get_deployment(registration, deployment_id), to: StorageAdapter

  @impl Ltix.StorageAdapter
  def validate_nonce(nonce, registration, expires_at) do
    send(self(), {:validate_nonce, nonce, expires_at})
    StorageAdapter.validate_nonce(nonce, registration, expires_at)
  end
end
