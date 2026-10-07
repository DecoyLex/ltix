defmodule Ltix.Test.StorageAdapter do
  @moduledoc """
  In-memory `StorageAdapter` for tests.

  Uses an `Agent` to store registrations, deployments, and nonces. Each
  test should start its own adapter via `start_link/1` and register it
  with `set_pid/1`.

  ## Manual usage

      {:ok, pid} = Ltix.Test.StorageAdapter.start_link(
        platforms: [platform]
      )
      Ltix.Test.StorageAdapter.set_pid(pid)
  """

  @behaviour Ltix.StorageAdapter

  use Agent

  alias Ltix.Options
  alias Ltix.Records
  alias Ltix.Test.Platform

  @pid_key :ltix_test_storage_adapter_pid

  @start_link_schema Zoi.keyword(
                       [
                         platforms: Zoi.list(Zoi.struct(Platform)),
                         registrations: Zoi.list(Zoi.any())
                       ],
                       unrecognized_keys: :error
                     )

  @doc """
  Start the storage adapter agent.

  ## Options

    * `:platforms` - list of `Ltix.Test.Platform` structs whose registration
      and deployment the adapter resolves (defaults to `[]`)
    * `:registrations` - list of structs implementing `Ltix.Registerable`
      that have no deployment (defaults to `[]`)
  """
  def start_link(opts \\ []) do
    opts = Options.parse!(opts, @start_link_schema)
    platforms = Keyword.get(opts, :platforms, [])

    registrations =
      Enum.uniq(Enum.map(platforms, & &1.registration) ++ Keyword.get(opts, :registrations, []))

    deployments =
      Map.new(platforms, fn platform ->
        deployment = ok!(Records.convert!(platform.deployment, :deployment, :platforms))
        {{registration_key(platform.registration), deployment.deployment_id}, platform.deployment}
      end)

    Agent.start_link(fn ->
      %{
        registrations: Enum.map(registrations, &{registration_key(&1), &1}),
        deployments: deployments,
        used_nonces: MapSet.new()
      }
    end)
  end

  @doc """
  Register the adapter PID in the calling process.

  Processes the caller starts, such as tasks and LiveViews, use the same
  adapter.
  """
  def set_pid(pid), do: Process.put(@pid_key, pid)

  # Finds the adapter registered in this process or the process that started it.
  defp pid do
    Process.get(@pid_key) ||
      Enum.find_value(Process.get(:"$callers", []), fn process ->
        case Process.info(process, :dictionary) do
          {:dictionary, dictionary} -> Keyword.get(dictionary, @pid_key)
          nil -> nil
        end
      end) ||
      raise "No Ltix.Test.StorageAdapter registered. Call set_pid/1 in the test process."
  end

  @impl Ltix.StorageAdapter
  def get_registration(issuer, client_id, _opts) do
    registrations = Agent.get(pid(), & &1.registrations)

    matches =
      for {{^issuer, registered_client_id}, registration} <- registrations,
          client_id in [nil, registered_client_id],
          do: registration

    case matches do
      [registration | _] -> {:ok, registration}
      [] -> {:error, :not_found}
    end
  end

  @impl Ltix.StorageAdapter
  def get_deployment(registration, deployment_id, _opts) do
    key = {registration_key(registration), deployment_id}

    Agent.get(pid(), fn state ->
      case Map.fetch(state.deployments, key) do
        {:ok, _deployment} = found -> found
        :error -> {:error, :not_found}
      end
    end)
  end

  @impl Ltix.StorageAdapter
  def validate_nonce(nonce, _registration, _expires_at, _opts) do
    Agent.get_and_update(pid(), fn state ->
      if MapSet.member?(state.used_nonces, nonce),
        do: {{:error, :nonce_already_used}, state},
        else: {:ok, %{state | used_nonces: MapSet.put(state.used_nonces, nonce)}}
    end)
  end

  @doc """
  Return the key the adapter signs with.

  The key is generated the first time it is needed, and signing works
  without starting the adapter.
  """
  @spec tool_jwk() :: Ltix.JWK.t()
  def tool_jwk do
    :persistent_term.get(__MODULE__, nil) || generate_tool_jwk()
  end

  # One process generates the key, and the others wait for it.
  defp generate_tool_jwk do
    :global.trans({__MODULE__, self()}, fn ->
      with nil <- :persistent_term.get(__MODULE__, nil) do
        tool_jwk = Ltix.JWK.generate(key_size: 2048)
        :persistent_term.put(__MODULE__, tool_jwk)
        tool_jwk
      end
    end)
  end

  @impl Ltix.StorageAdapter
  def key_id(_registration, _opts), do: {:ok, tool_jwk().kid}

  @impl Ltix.StorageAdapter
  def sign(_registration, key_id, message, _opts) do
    case tool_jwk() do
      %Ltix.JWK{kid: ^key_id} = tool_jwk -> Ltix.JWK.sign(tool_jwk, message)
      _other_key -> {:error, :unknown_key}
    end
  end

  defp registration_key(registration) do
    resolved = ok!(Records.convert!(registration, :registration, :registrations))
    {resolved.issuer, resolved.client_id}
  end

  defp ok!({:ok, value}), do: value
  defp ok!({:error, error}), do: raise(error)
end
