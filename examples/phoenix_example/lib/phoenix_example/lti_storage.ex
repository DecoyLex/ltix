defmodule PhoenixExample.LtiStorage do
  @moduledoc """
  In-memory LTI storage adapter for demo purposes.

  Stores a hardcoded registration and deployment, tracks nonces, and
  persists launch contexts in an Agent. Replace this with a
  database-backed implementation in a real application.
  """

  @behaviour Ltix.StorageAdapter

  use Agent

  # --- Demo registration ---
  # Replace these values with your platform's actual configuration.

  @demo_issuer "https://lti-ri.imsglobal.org"
  @demo_client_id "test"
  @demo_deployment_id "test-deployment"

  @demo_deployment %Ltix.Deployment{deployment_id: @demo_deployment_id}

  # --- Agent lifecycle ---

  def start_link(_opts) do
    Agent.start_link(
      fn ->
        tool_jwk = Ltix.JWK.generate()

        # Print out the JWK to the console so it can be copied into the platform's tool registration.
        IO.puts("Generated tool JWK (copy this into your platform registration):")
        tool_jwk |> Ltix.JWK.to_jwks() |> JSON.encode!() |> IO.puts()

        IO.puts("Or use the following RSA public key:")
        tool_jwk |> Ltix.JWK.to_public_key() |> IO.puts()

        %{nonces: MapSet.new(), contexts: %{}, tool_jwk: tool_jwk}
      end,
      name: __MODULE__
    )
  end

  # --- StorageAdapter callbacks ---

  @impl true
  def get_registration(@demo_issuer, _client_id) do
    tool_jwk = Agent.get(__MODULE__, & &1.tool_jwk)

    {:ok,
     %Ltix.Registration{
       issuer: @demo_issuer,
       client_id: @demo_client_id,
       auth_endpoint: "https://lti-ri.imsglobal.org/platforms/6092/authorizations/new",
       jwks_uri: "https://lti-ri.imsglobal.org/platforms/6092/platform_keys/5405.json",
       token_endpoint: "https://lti-ri.imsglobal.org/platforms/6092/access_tokens",
       tool_jwk: tool_jwk
     }}
  end

  def get_registration(_issuer, _client_id), do: {:error, :not_found}

  @impl true
  def get_deployment(
        %Ltix.Registration{issuer: @demo_issuer, client_id: @demo_client_id},
        @demo_deployment_id
      ),
      do: {:ok, @demo_deployment}

  def get_deployment(_registration, _deployment_id), do: {:error, :not_found}

  @impl true
  def store_nonce(nonce, _registration) do
    Agent.update(__MODULE__, fn state ->
      update_in(state, [:nonces], &MapSet.put(&1, nonce))
    end)

    :ok
  end

  @impl true
  def validate_nonce(nonce, _registration) do
    Agent.get_and_update(__MODULE__, fn state ->
      if MapSet.member?(state.nonces, nonce) do
        {:ok, update_in(state, [:nonces], &MapSet.delete(&1, nonce))}
      else
        {{:error, :nonce_not_found}, state}
      end
    end)
  end

  # --- Context storage (example-app specific) ---

  @doc """
  Store a launch context and return its ID.
  """
  def store_context(context) do
    context_id = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

    Agent.update(__MODULE__, fn state ->
      put_in(state, [:contexts, context_id], context)
    end)

    context_id
  end

  @doc """
  Retrieve a previously stored launch context by ID.
  """
  def get_context(context_id) do
    case Agent.get(__MODULE__, &get_in(&1, [:contexts, context_id])) do
      nil -> {:error, :not_found}
      context -> {:ok, context}
    end
  end
end
