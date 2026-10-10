defmodule PhoenixExample.LtiStorage do
  @moduledoc """
  In-memory LTI storage adapter for demo purposes.

  Stores a hardcoded registration and deployment, tracks nonces, signs with
  a generated key, and persists launch contexts in an Agent. Replace this with a
  database-backed implementation in a real application.
  """

  @behaviour Ltix.StorageAdapter

  use Agent

  require Logger

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

        # Log the JWK so it can be copied into the platform's tool registration.
        Logger.info("""
        Generated tool JWK (copy this into your platform registration):
        #{JSON.encode!(Ltix.JWK.to_jwks(tool_jwk))}

        Or use the following RSA public key:
        #{Ltix.JWK.to_public_key(tool_jwk)}
        """)

        %{used_nonces: MapSet.new(), contexts: %{}, tool_jwk: tool_jwk}
      end,
      name: __MODULE__
    )
  end

  # --- StorageAdapter callbacks ---

  @impl true
  def get_registration(@demo_issuer, _client_id, _opts) do
    {:ok,
     %Ltix.Registration{
       issuer: @demo_issuer,
       client_id: @demo_client_id,
       auth_endpoint: "https://lti-ri.imsglobal.org/platforms/6092/authorizations/new",
       jwks_uri: "https://lti-ri.imsglobal.org/platforms/6092/platform_keys/5405.json",
       token_endpoint: "https://lti-ri.imsglobal.org/platforms/6092/access_tokens"
     }}
  end

  def get_registration(_issuer, _client_id, _opts), do: {:error, :not_found}

  @impl true
  def get_deployment(
        %Ltix.Registration{issuer: @demo_issuer, client_id: @demo_client_id},
        @demo_deployment_id,
        _opts
      ),
      do: {:ok, @demo_deployment}

  def get_deployment(_registration, _deployment_id, _opts), do: {:error, :not_found}

  @impl true
  def validate_nonce(nonce, _registration, _expires_at, _opts) do
    Agent.get_and_update(__MODULE__, fn state ->
      if MapSet.member?(state.used_nonces, nonce) do
        {{:error, :nonce_already_used}, state}
      else
        {:ok, update_in(state, [:used_nonces], &MapSet.put(&1, nonce))}
      end
    end)
  end

  @impl true
  def key_id(_registration, _opts), do: {:ok, tool_jwk().kid}

  @impl true
  def sign(_registration, key_id, message, _opts) do
    case tool_jwk() do
      %Ltix.JWK{kid: ^key_id} = tool_jwk -> Ltix.JWK.sign(tool_jwk, message)
      _other_key -> {:error, :unknown_key}
    end
  end

  @doc """
  Return the key the tool signs with.
  """
  def tool_jwk, do: Agent.get(__MODULE__, & &1.tool_jwk)

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
