defmodule Ltix.Integration.StorageAdapterContractTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.InvalidOption

  @moduletag capture_log: true

  defmodule ScriptedAdapter do
    @moduledoc false
    @behaviour Ltix.StorageAdapter

    @impl Ltix.StorageAdapter
    def get_registration(issuer, client_id, opts) do
      result = CustomStorageAdapter.get_registration(issuer, client_id, opts)
      registration_result(Process.get(:contract_failure), issuer, client_id, result)
    end

    defp registration_result(:issuer_only, _issuer, nil, _result), do: {:error, :not_found}

    defp registration_result(:ignore_client, issuer, client_id, _result) when client_id != nil,
      do: CustomStorageAdapter.get_registration(issuer, nil, [])

    defp registration_result(:ignore_issuer, _issuer, client_id, _result) do
      records = Agent.get(Process.get(:contract_adapter_pid), & &1.registrations)
      found(Enum.find(records, &(&1.oauth_client_id == client_id)))
    end

    defp registration_result(:protocol_raise, _issuer, _client_id, {:ok, _}),
      do: {:ok, %RaisingRegistration{}}

    defp registration_result(:registration_raise, _issuer, _client_id, _result),
      do: raise(RuntimeError, "database unavailable")

    defp registration_result(:case_fold_registration, issuer, client_id, _result) do
      records = Agent.get(Process.get(:contract_adapter_pid), & &1.registrations)

      found(
        Enum.find(records, fn record ->
          String.downcase(record.platform_issuer) == String.downcase(issuer) and
            (client_id == nil or
               String.downcase(record.oauth_client_id) == String.downcase(client_id))
        end)
      )
    end

    defp registration_result(:registration_fields, _issuer, _client_id, {:ok, record}),
      do: {:ok, %{record | tenant_id: :loaded}}

    defp registration_result(:invalid_registration, issuer, _client_id, {:ok, _}),
      do: {:ok, %{issuer: issuer}}

    defp registration_result(:invalid_registration_fields, _issuer, _client_id, {:ok, record}),
      do: {:ok, %{record | oidc_auth_url: "http://insecure.example.com"}}

    defp registration_result(:registration_error, _issuer, _client_id, _result),
      do: {:error, :database_unavailable}

    defp registration_result(:ambiguous_not_found, issuer, nil, _result) do
      records = Agent.get(Process.get(:contract_adapter_pid), & &1.registrations)

      case Enum.filter(records, &(&1.platform_issuer == issuer)) do
        [record] -> {:ok, record}
        _ -> {:error, :not_found}
      end
    end

    defp registration_result(_mode, _issuer, _client_id, result), do: result

    @impl Ltix.StorageAdapter
    def get_deployment(registration, deployment_id, opts) do
      result = CustomStorageAdapter.get_deployment(registration, deployment_id, opts)
      deployment_result(Process.get(:contract_failure), registration, deployment_id, result)
    end

    defp deployment_result(:ignore_deployment_registration, _registration, deployment_id, _result) do
      records = Agent.get(Process.get(:contract_adapter_pid), & &1.deployments)
      found(Enum.find(records, &(&1.platform_deployment_id == deployment_id)))
    end

    defp deployment_result(:case_insensitive, _registration, deployment_id, {:error, :not_found}) do
      records = Agent.get(Process.get(:contract_adapter_pid), & &1.deployments)

      found(
        Enum.find(records, fn deployment ->
          String.downcase(deployment.platform_deployment_id) == String.downcase(deployment_id)
        end)
      )
    end

    defp deployment_result(:deployment_fields, _registration, _deployment_id, {:ok, record}),
      do: {:ok, %{record | label: "Loaded association"}}

    defp deployment_result(
           :auto_create_global_fallback,
           registration,
           deployment_id,
           {:error, :not_found}
         ) do
      records = Agent.get(Process.get(:contract_adapter_pid), & &1.deployments)

      case Enum.find(records, &(&1.platform_deployment_id == deployment_id)) do
        nil ->
          {:ok, create_deployment(Ltix.Deployment.new!(deployment_id), registration)}

        record ->
          {:ok, record}
      end
    end

    defp deployment_result(
           :auto_create_unstored,
           registration,
           deployment_id,
           {:error, :not_found}
         ) do
      {:ok,
       %CustomDeployment{
         id: System.unique_integer([:positive]),
         registration_id: registration.id,
         platform_deployment_id: deployment_id
       }}
    end

    defp deployment_result(:invalid_deployment, _registration, deployment_id, {:ok, _}),
      do: {:ok, %{deployment_id: deployment_id}}

    defp deployment_result(:wrong_deployment, _registration, _deployment_id, {:ok, record}),
      do: {:ok, %{record | platform_deployment_id: "wrong-deployment"}}

    defp deployment_result(
           :auto_create_concurrent_duplicates,
           registration,
           deployment_id,
           {:error, :not_found}
         ) do
      if Process.get(:contract_worker) == true and
           String.starts_with?(deployment_id, "Concurrent-") do
        race_deployment(registration, deployment_id)
      else
        deployment_result(:auto_create, registration, deployment_id, {:error, :not_found})
      end
    end

    defp deployment_result(:auto_create, registration, deployment_id, {:error, :not_found}) do
      {:ok, create_deployment(Ltix.Deployment.new!(deployment_id), registration)}
    end

    defp deployment_result(_mode, _registration, _deployment_id, result), do: result

    defp found(nil), do: {:error, :not_found}
    defp found(record), do: {:ok, record}

    @impl Ltix.StorageAdapter
    def validate_nonce(nonce, registration, expires_at, opts) do
      case {Process.get(:contract_failure), Process.get(:contract_worker)} do
        {:concurrent_replay, true} ->
          race_nonce(nonce)

        {:worker_timeout, true} ->
          Process.sleep(:infinity)

        {:worker_exit, true} ->
          exit(:database_unavailable)

        {:replay, _} ->
          :ok

        {:wrong_nonce_result, _} ->
          {:ok, nonce}

        {:case_fold_nonce, _} ->
          CustomStorageAdapter.validate_nonce(
            String.downcase(nonce),
            registration,
            expires_at,
            opts
          )

        _ ->
          CustomStorageAdapter.validate_nonce(nonce, registration, expires_at, opts)
      end
    end

    defp race_deployment(registration, deployment_id) do
      synchronize_reads(deployment_id)

      record = %CustomDeployment{
        id: System.unique_integer([:positive]),
        registration_id: registration.id,
        platform_deployment_id: deployment_id
      }

      Agent.update(
        Process.get(:contract_adapter_pid),
        &%{&1 | deployments: [record | &1.deployments]}
      )

      {:ok, record}
    end

    defp race_nonce(nonce) do
      pid = Process.get(:contract_adapter_pid)
      used = Agent.get(pid, &MapSet.member?(&1.used_nonces, nonce))
      synchronize_reads(nonce)
      Agent.update(pid, &%{&1 | used_nonces: MapSet.put(&1.used_nonces, nonce)})
      if used, do: {:error, :nonce_already_used}, else: :ok
    end

    defp synchronize_reads(key) do
      worker = self()

      action =
        Agent.get_and_update(Process.get(:contract_adapter_pid), fn state ->
          case Map.get(state, :waiting_reader) do
            nil -> {:wait, Map.put(state, :waiting_reader, worker)}
            waiting -> {{:release, waiting}, Map.delete(state, :waiting_reader)}
          end
        end)

      release_reader(action, key)
    end

    defp release_reader({:release, waiting}, key), do: send(waiting, {:storage_read, key})

    defp release_reader(:wait, key) do
      receive do
        {:storage_read, ^key} -> :ok
      end
    end

    defp create_deployment(deployment, registration) do
      record = %CustomDeployment{
        id: System.unique_integer([:positive]),
        registration_id: registration.id,
        platform_deployment_id: deployment.deployment_id
      }

      Agent.get_and_update(Process.get(:contract_adapter_pid), fn state ->
        case Enum.find(state.deployments, fn stored ->
               stored.registration_id == registration.id and
                 stored.platform_deployment_id == deployment.deployment_id
             end) do
          nil -> {record, %{state | deployments: [record | state.deployments]}}
          existing -> {existing, state}
        end
      end)
    end
  end

  # Adds the signing callbacks to `CustomStorageAdapter`, signing with the
  # key and failure mode the test sets.
  defmodule SigningAdapter do
    @moduledoc false
    @behaviour Ltix.StorageAdapter

    @impl Ltix.StorageAdapter
    defdelegate get_registration(issuer, client_id, opts), to: CustomStorageAdapter

    @impl Ltix.StorageAdapter
    defdelegate get_deployment(registration, deployment_id, opts), to: CustomStorageAdapter

    @impl Ltix.StorageAdapter
    defdelegate validate_nonce(nonce, registration, expires_at, opts), to: CustomStorageAdapter

    @impl Ltix.StorageAdapter
    def key_id(%CustomRegistration{}, _opts) do
      case Process.get(:signing_failure) do
        :blank_key_id -> {:ok, ""}
        :unpublished_key_id -> {:ok, Process.get(:other_key).kid}
        _ -> {:ok, Process.get(:signing_key).kid}
      end
    end

    @impl Ltix.StorageAdapter
    def sign(%CustomRegistration{}, key_id, message, _opts) do
      signing_key = Process.get(:signing_key)
      other_key = Process.get(:other_key)

      case Process.get(:signing_failure) do
        :unpublished_key_id when key_id == other_key.kid -> Ltix.JWK.sign(other_key, message)
        :sign_error -> {:error, :database_unavailable}
        :wrong_key -> Ltix.JWK.sign(other_key, message)
        :ignore_key_id -> Ltix.JWK.sign(signing_key, message)
        _ when key_id == signing_key.kid -> Ltix.JWK.sign(signing_key, message)
        _ -> {:error, :unknown_key}
      end
    end
  end

  # Finds records only when called with the tenant the test stored them for.
  defmodule TenantAdapter do
    @moduledoc false
    @behaviour Ltix.StorageAdapter

    @impl Ltix.StorageAdapter
    def get_registration(issuer, client_id, opts) do
      scoped(opts, fn -> CustomStorageAdapter.get_registration(issuer, client_id, opts) end)
    end

    @impl Ltix.StorageAdapter
    def get_deployment(registration, deployment_id, opts) do
      scoped(opts, fn ->
        CustomStorageAdapter.get_deployment(registration, deployment_id, opts)
      end)
    end

    @impl Ltix.StorageAdapter
    def validate_nonce(nonce, registration, expires_at, opts) do
      scoped(opts, fn ->
        CustomStorageAdapter.validate_nonce(nonce, registration, expires_at, opts)
      end)
    end

    defp scoped(opts, lookup) do
      if opts[:tenant] == "acme", do: lookup.(), else: {:error, :not_found}
    end
  end

  # Exports one of the two signing callbacks.
  defmodule HalfSigningAdapter do
    @moduledoc false

    defdelegate get_registration(issuer, client_id, opts), to: CustomStorageAdapter
    defdelegate get_deployment(registration, deployment_id, opts), to: CustomStorageAdapter
    defdelegate validate_nonce(nonce, registration, expires_at, opts), to: CustomStorageAdapter
    def key_id(_registration, _opts), do: {:ok, "key"}
  end

  setup_all do
    %{
      signing_key: Ltix.JWK.generate(key_size: 2048),
      other_key: Ltix.JWK.generate(key_size: 2048)
    }
  end

  setup do
    pid = start_supervised!({CustomStorageAdapter, registrations: [], deployments: []})
    CustomStorageAdapter.set_pid(pid)
    Process.put(:contract_adapter_pid, pid)

    registration = fn registration ->
      record = %CustomRegistration{
        id: System.unique_integer([:positive]),
        platform_issuer: registration.issuer,
        oauth_client_id: registration.client_id,
        oidc_auth_url: registration.auth_endpoint,
        platform_jwks_url: registration.jwks_uri,
        platform_token_url: registration.token_endpoint
      }

      Agent.update(pid, &%{&1 | registrations: [record | &1.registrations]})
      record
    end

    deployment = fn deployment, registration ->
      record = %CustomDeployment{
        id: System.unique_integer([:positive]),
        registration_id: registration.id,
        platform_deployment_id: deployment.deployment_id
      }

      Agent.update(pid, &%{&1 | deployments: [record | &1.deployments]})
      record
    end

    prepare_process = fn ->
      CustomStorageAdapter.set_pid(pid)
      Process.put(:contract_adapter_pid, pid)
      Process.put(:contract_worker, true)
    end

    %{
      opts: [
        registration: registration,
        deployment: deployment,
        prepare_process: prepare_process
      ]
    }
  end

  test "accepts custom records and repeat runs in the same storage", %{opts: opts} do
    assert :ok = Ltix.Test.assert_storage_adapter!(CustomStorageAdapter, opts)
    assert :ok = Ltix.Test.assert_storage_adapter!(CustomStorageAdapter, opts)
  end

  test "calls the adapter with the storage adapter options", %{opts: opts} do
    assert :ok =
             Ltix.Test.assert_storage_adapter!(
               TenantAdapter,
               opts ++ [storage_adapter_options: [tenant: "acme"]]
             )

    assert_raise ExUnit.AssertionError, ~r/get_registration\/3/, fn ->
      Ltix.Test.assert_storage_adapter!(TenantAdapter, opts)
    end
  end

  test "accepts ambiguous_not_found", %{opts: opts} do
    Process.put(:contract_failure, :ambiguous_not_found)
    assert :ok = Ltix.Test.assert_storage_adapter!(ScriptedAdapter, opts)
  end

  test "accepts explicitly enabled automatic deployment creation", %{opts: opts} do
    opts = scripted_options(opts, :auto_create)

    assert :ok =
             Ltix.Test.assert_storage_adapter!(
               ScriptedAdapter,
               opts ++ [auto_create_deployments: true]
             )
  end

  for {mode, message} <- [
        issuer_only: "get_registration/3.*issuer-only",
        ignore_client: "get_registration/3.*client",
        ignore_issuer: "get_registration/3.*issuer",
        registration_raise: "get_registration/3.*database unavailable",
        protocol_raise: "get_registration/3.*Registerable.*registration conversion failed",
        case_fold_registration: "get_registration/3.*case-sensitive",
        registration_fields: "get_registration/3.*record identity",
        deployment_fields: "get_deployment/3.*record identity",
        invalid_registration: "get_registration/3.*Registerable",
        invalid_registration_fields: "get_registration/3.*Registerable",
        registration_error: "get_registration/3.*database_unavailable",
        ignore_deployment_registration: "get_deployment/3.*registration",
        case_insensitive: "get_deployment/3.*case-sensitive",
        invalid_deployment: "get_deployment/3.*Deployable",
        wrong_deployment: "get_deployment/3.*deployment",
        auto_create: "get_deployment/3.*not_found",
        wrong_nonce_result: "validate_nonce/4.*first time",
        case_fold_nonce: "validate_nonce/4.*case-sensitive",
        replay: "validate_nonce/4.*already used",
        concurrent_replay: "validate_nonce/4.*atomically",
        worker_timeout: "validate_nonce/4.*callback timed out",
        worker_exit: "validate_nonce/4.*database_unavailable"
      ] do
    test "rejects #{mode} with a useful assertion failure", %{opts: opts} do
      opts = scripted_options(opts, unquote(mode))

      opts =
        if unquote(mode) == :worker_timeout,
          do: Keyword.put(opts, :timeout, 100),
          else: opts

      assert_raise ExUnit.AssertionError, Regex.compile!(unquote(message), "s"), fn ->
        Ltix.Test.assert_storage_adapter!(ScriptedAdapter, opts)
      end
    end
  end

  for mode <- [:auto_create_global_fallback, :auto_create_unstored] do
    test "rejects #{mode} in automatic creation mode", %{opts: opts} do
      opts = scripted_options(opts, unquote(mode))
      opts = Keyword.put(opts, :auto_create_deployments, true)

      assert_raise ExUnit.AssertionError, ~r/get_deployment\/3.*record identity/s, fn ->
        Ltix.Test.assert_storage_adapter!(ScriptedAdapter, opts)
      end
    end
  end

  test "rejects duplicate stored records from concurrent deployment creation", %{opts: opts} do
    opts = scripted_options(opts, :auto_create_concurrent_duplicates)
    opts = Keyword.put(opts, :auto_create_deployments, true)

    assert_raise ExUnit.AssertionError, ~r/get_deployment\/3.*between concurrent results/s, fn ->
      Ltix.Test.assert_storage_adapter!(ScriptedAdapter, opts)
    end

    assert [first, second] =
             Agent.get(Process.get(:contract_adapter_pid), fn state ->
               Enum.filter(
                 state.deployments,
                 &String.starts_with?(&1.platform_deployment_id, "Concurrent-")
               )
             end)

    refute first.id == second.id
    assert first.registration_id == second.registration_id
    assert first.platform_deployment_id == second.platform_deployment_id
  end

  for {mode, option} <- [
        registration_fields: :registration_identity,
        deployment_fields: :deployment_identity
      ] do
    test "accepts #{mode} when its stored identity is unchanged", %{opts: opts} do
      opts = scripted_options(opts, unquote(mode))
      opts = Keyword.put(opts, unquote(option), & &1.id)
      assert :ok = Ltix.Test.assert_storage_adapter!(ScriptedAdapter, opts)
    end
  end

  test "requires multiple deployments per registration", %{opts: opts} do
    factory = Keyword.fetch!(opts, :deployment)
    parent = self()

    opts =
      Keyword.put(opts, :deployment, fn deployment, registration ->
        send(parent, {:deployment_created, registration.id, deployment.deployment_id})
        factory.(deployment, registration)
      end)

    assert :ok = Ltix.Test.assert_storage_adapter!(CustomStorageAdapter, opts)
    assert_receive {:deployment_created, registration, first}
    assert_receive {:deployment_created, ^registration, second}
    refute first == second
  end

  describe "signing callbacks" do
    setup %{opts: opts, signing_key: signing_key, other_key: other_key} do
      Process.put(:signing_key, signing_key)
      Process.put(:other_key, other_key)

      %{opts: opts ++ [jwks: fn %CustomRegistration{} -> Ltix.JWK.to_jwks(signing_key) end]}
    end

    test "accepts signatures that verify against the published key set", %{opts: opts} do
      assert :ok = Ltix.Test.assert_storage_adapter!(SigningAdapter, opts)
    end

    for {failure, message} <- [
          blank_key_id: "key_id/2.*non-empty string",
          unpublished_key_id: "key_id/2.*key set",
          sign_error: "sign/4.*database_unavailable",
          wrong_key: "sign/4.*verifies",
          ignore_key_id: "sign/4.*key ID it can't sign with"
        ] do
      test "rejects #{failure} with a useful assertion failure", %{opts: opts} do
        Process.put(:signing_failure, unquote(failure))

        assert_raise ExUnit.AssertionError, Regex.compile!(unquote(message), "s"), fn ->
          Ltix.Test.assert_storage_adapter!(SigningAdapter, opts)
        end
      end
    end

    test "rejects a published key set that includes a private key", %{opts: opts} do
      signing_key = Process.get(:signing_key)
      {_type, private_key} = JOSE.JWK.to_map(JOSE.JWK.from_pem(signing_key.private_key_pem))
      opts = Keyword.put(opts, :jwks, fn _registration -> %{"keys" => [private_key]} end)

      assert_raise ExUnit.AssertionError, ~r/jwks.*private key/s, fn ->
        Ltix.Test.assert_storage_adapter!(SigningAdapter, opts)
      end
    end

    test "requires the jwks option when the adapter signs", %{opts: opts} do
      assert_raise InvalidOption, ~r/jwks.*key_id\/2 and sign\/4/s, fn ->
        Ltix.Test.assert_storage_adapter!(SigningAdapter, Keyword.delete(opts, :jwks))
      end
    end

    test "rejects the jwks option for an adapter that doesn't sign", %{opts: opts} do
      assert_raise InvalidOption, ~r/jwks.*neither key_id\/2 nor sign\/4/s, fn ->
        Ltix.Test.assert_storage_adapter!(CustomStorageAdapter, opts)
      end
    end

    test "rejects an adapter that exports only one signing callback", %{opts: opts} do
      assert_raise InvalidOption, ~r/storage_adapter.*key_id\/2 and sign\/4/s, fn ->
        Ltix.Test.assert_storage_adapter!(HalfSigningAdapter, opts)
      end
    end
  end

  test "reports invalid factory results as fixture failures", %{opts: opts} do
    opts = Keyword.put(opts, :registration, fn _ -> {:ok, :not_a_record} end)

    assert_raise ExUnit.AssertionError, ~r/registration factory.*Registerable/s, fn ->
      Ltix.Test.assert_storage_adapter!(CustomStorageAdapter, opts)
    end
  end

  test "rejects factories that change generated lookup identifiers", %{opts: opts} do
    factory = Keyword.fetch!(opts, :registration)

    opts =
      Keyword.put(opts, :registration, fn reg -> factory.(%{reg | client_id: "fixed"}) end)

    assert_raise ExUnit.AssertionError, ~r/registration factory.*client_id/s, fn ->
      Ltix.Test.assert_storage_adapter!(CustomStorageAdapter, opts)
    end
  end

  test "rejects modules missing callbacks before writing records", %{opts: opts} do
    assert_raise InvalidOption, ~r/storage_adapter.*callbacks/s, fn ->
      Ltix.Test.assert_storage_adapter!(String, opts)
    end

    assert [] = Agent.get(Process.get(:contract_adapter_pid), & &1.registrations)
  end

  test "reports invalid deployment factory results", %{opts: opts} do
    opts = Keyword.put(opts, :deployment, fn _, _ -> :not_a_record end)

    assert_raise ExUnit.AssertionError, ~r/deployment factory.*Deployable/s, fn ->
      Ltix.Test.assert_storage_adapter!(CustomStorageAdapter, opts)
    end
  end

  test "rejects deployment factories that change the identifier", %{opts: opts} do
    factory = Keyword.fetch!(opts, :deployment)

    opts =
      Keyword.put(opts, :deployment, fn dep, reg ->
        factory.(%{dep | deployment_id: "fixed"}, reg)
      end)

    assert_raise ExUnit.AssertionError, ~r/deployment factory.*deployment_id/s, fn ->
      Ltix.Test.assert_storage_adapter!(CustomStorageAdapter, opts)
    end
  end

  for {failure, message} <- [timeout: "prepare_process timed out", exit: "sandbox_unavailable"] do
    test "reports worker preparation #{failure} and stops validation processes", %{
      opts: opts
    } do
      parent = self()
      barrier = start_supervised!({Agent, fn -> nil end})

      opts =
        Keyword.put(opts, :prepare_process, fn ->
          send(parent, {:validation_worker, self()})
          synchronize_preparation(barrier)

          case unquote(failure) do
            :timeout -> Process.sleep(:infinity)
            :exit -> exit(:sandbox_unavailable)
          end
        end)

      opts =
        if unquote(failure) == :timeout, do: Keyword.put(opts, :timeout, 100), else: opts

      assert_raise ExUnit.AssertionError, Regex.compile!(unquote(message)), fn ->
        Ltix.Test.assert_storage_adapter!(CustomStorageAdapter, opts)
      end

      for _ <- 1..2 do
        assert_receive {:validation_worker, pid}
        refute Process.alive?(pid)
      end

      refute_receive {:DOWN, _, :process, _, _}
      refute_receive {_, :ready, _}
    end
  end

  test "validates options before writing records", %{opts: opts} do
    for invalid <- [
          Keyword.delete(opts, :registration),
          Keyword.put(opts, :deployment, fn _ -> :wrong_arity end),
          Keyword.put(opts, :prepare_process, nil),
          Keyword.put(opts, :timeout, 0),
          Keyword.put(opts, :unknown, true)
        ] do
      assert_raise InvalidOption, fn ->
        Ltix.Test.assert_storage_adapter!(CustomStorageAdapter, invalid)
      end
    end

    assert [] = Agent.get(Process.get(:contract_adapter_pid), & &1.registrations)
  end

  defp synchronize_preparation(barrier) do
    worker = self()
    waiting = Agent.get_and_update(barrier, fn waiting -> {waiting, worker} end)

    case waiting do
      nil ->
        receive do
          :preparation_ready -> :ok
        end

      waiting ->
        send(waiting, :preparation_ready)
    end
  end

  defp scripted_options(opts, mode) do
    Process.put(:contract_failure, mode)
    prepare_process = Keyword.fetch!(opts, :prepare_process)

    Keyword.put(opts, :prepare_process, fn ->
      prepare_process.()
      Process.put(:contract_failure, mode)
    end)
  end
end
