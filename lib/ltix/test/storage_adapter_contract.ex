defmodule Ltix.Test.StorageAdapterContract do
  @moduledoc false

  alias Ltix.Deployable
  alias Ltix.Deployment
  alias Ltix.Errors.Invalid.InvalidOption
  alias Ltix.Errors.Unknown.StorageError
  alias Ltix.JWK
  alias Ltix.Options
  alias Ltix.Records
  alias Ltix.Registerable
  alias Ltix.Registration
  alias Ltix.StorageAdapter
  alias Ltix.Test.Platform

  @schema Zoi.keyword(
            [
              registration: Zoi.function(arity: 1) |> Zoi.required(),
              deployment: Zoi.function(arity: 2) |> Zoi.required(),
              registration_identity: Zoi.function(arity: 1),
              deployment_identity: Zoi.function(arity: 1),
              prepare_process: Zoi.function(arity: 0),
              jwks: Zoi.function(arity: 1),
              storage_adapter_options: Zoi.keyword(Zoi.any()) |> Zoi.default([]),
              auto_create_deployments: Zoi.boolean() |> Zoi.default(false),
              timeout:
                Zoi.integer()
                |> Zoi.min(1)
                |> Zoi.default(5000)
            ],
            unrecognized_keys: :error
          )

  @doc false
  def verify!(adapter, opts) do
    opts = Options.parse!(opts, @schema)
    validate_adapter!(adapter)
    validate_signing!(adapter, Keyword.has_key?(opts, :jwks))
    platforms = create_platforms!(opts)
    check_registrations!(adapter, platforms, opts)
    check_deployments!(adapter, platforms, opts)
    Enum.each(platforms, &check_nonces!(adapter, &1, opts))

    # After validation, the key set is given exactly when the adapter signs.
    if Keyword.has_key?(opts, :jwks) do
      platforms
      |> Enum.uniq_by(& &1.registration)
      |> Enum.each(&check_signing!(adapter, &1, opts))
    end

    :ok
  end

  defp validate_adapter!(adapter) do
    callbacks = [get_registration: 3, get_deployment: 3, validate_nonce: 4]

    unless is_atom(adapter) and Code.ensure_loaded?(adapter) and
             Enum.all?(callbacks, fn {name, arity} -> function_exported?(adapter, name, arity) end) do
      raise InvalidOption,
        key: :storage_adapter,
        value: adapter,
        reason: "must export all three Ltix.StorageAdapter callbacks"
    end
  end

  # The signing callbacks are optional. An adapter exports both or neither,
  # and the key set is given exactly when it exports them.
  defp validate_signing!(adapter, key_set_given?) do
    exported =
      Enum.count([key_id: 2, sign: 4], fn {name, arity} ->
        function_exported?(adapter, name, arity)
      end)

    validate_signing!(adapter, exported, key_set_given?)
  end

  defp validate_signing!(_adapter, 2, true), do: :ok
  defp validate_signing!(_adapter, 0, false), do: :ok

  defp validate_signing!(_adapter, 2, false) do
    raise InvalidOption,
      key: :jwks,
      reason: "the key set is required to check an adapter that exports key_id/2 and sign/4"
  end

  defp validate_signing!(_adapter, 0, true) do
    raise InvalidOption,
      key: :jwks,
      reason: "the adapter exports neither key_id/2 nor sign/4, so no signature can be checked"
  end

  defp validate_signing!(adapter, 1, _key_set_given?) do
    raise InvalidOption,
      key: :storage_adapter,
      value: adapter,
      reason: "must export both key_id/2 and sign/4, or neither"
  end

  defp create_platforms!(opts) do
    identifier = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    issuer = "https://#{identifier}.example.com/Platform"
    other_issuer = "https://other-#{identifier}.example.com/Platform"
    client_id = "Client-#{identifier}"
    deployment_id = "Deployment-#{identifier}"

    # The checks do not use the platform's key.
    jwk = JWK.generate(key_size: 2048)

    [first, second, third] =
      Enum.map(
        [
          {issuer, client_id, deployment_id},
          {issuer, "Other-#{client_id}", "Other-#{deployment_id}"},
          {other_issuer, client_id, deployment_id}
        ],
        fn {issuer, client_id, deployment_id} ->
          registration =
            Registration.new!(
              issuer: issuer,
              client_id: client_id,
              auth_endpoint: "#{issuer}/authorize",
              jwks_uri: "#{issuer}/jwks",
              token_endpoint: "#{issuer}/token"
            )

          record =
            invoke!(
              fn -> Keyword.fetch!(opts, :registration).(registration) end,
              "registration factory"
            )

          resolved = resolve!(record, Registerable, "registration factory")

          expect!(
            {resolved.issuer, resolved.client_id},
            {issuer, client_id},
            "registration factory must preserve issuer and client_id"
          )

          platform = %Platform{registration: record, deployment: nil, jwk: jwk}

          create_deployment!(platform, deployment_id, opts)
        end
      )

    [
      first,
      second,
      third,
      create_deployment!(first, "First-extra-#{deployment_id}", opts),
      create_deployment!(third, "Third-extra-#{deployment_id}", opts)
    ]
  end

  defp create_deployment!(platform, deployment_id, opts) do
    deployment = Deployment.new!(deployment_id)

    record =
      invoke!(
        fn -> Keyword.fetch!(opts, :deployment).(deployment, platform.registration) end,
        "deployment factory"
      )

    expect!(
      resolve!(record, Deployable, "deployment factory"),
      deployment,
      "deployment factory must preserve deployment_id"
    )

    %{platform | deployment: record}
  end

  defp check_registrations!(adapter, [first, second, third | _] = platforms, opts) do
    Enum.each(platforms, fn platform ->
      registration = resolve!(platform.registration, Registerable, "registration factory")
      label = "#{inspect(adapter)} get_registration/3 must match issuer and client_id"

      result =
        call!(
          adapter,
          :get_registration,
          [registration.issuer, registration.client_id],
          label,
          opts
        )

      check_record!(result, platform.registration, Registerable, label, opts)
    end)

    unique = resolve!(third.registration, Registerable, "registration factory")

    label =
      "#{inspect(adapter)} get_registration/3 must support an unambiguous issuer-only lookup"

    result = call!(adapter, :get_registration, [unique.issuer, nil], label, opts)
    check_record!(result, third.registration, Registerable, label, opts)

    shared = resolve!(first.registration, Registerable, "registration factory")
    other = resolve!(second.registration, Registerable, "registration factory")
    label = "#{inspect(adapter)} get_registration/3 must handle an ambiguous issuer-only lookup"
    result = call!(adapter, :get_registration, [shared.issuer, nil], label, opts)
    check_ambiguous!(result, [first.registration, second.registration], label, opts)

    missing_issuer =
      "https://missing-#{Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)}.example.com"

    missing_client_id =
      "Missing-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"

    Enum.each(
      [
        {missing_issuer, nil, "unknown issuer"},
        {missing_issuer, shared.client_id, "unknown issuer"},
        {shared.issuer, missing_client_id, "unknown client_id"},
        {unique.issuer, other.client_id, "unknown issuer and client_id pair"},
        {String.downcase(shared.issuer), shared.client_id, "case-sensitive issuer"},
        {shared.issuer, String.downcase(shared.client_id), "case-sensitive client_id"}
      ],
      fn {issuer, client_id, scenario} ->
        label = "#{inspect(adapter)} get_registration/3 must reject #{scenario}"

        expect!(
          call!(adapter, :get_registration, [issuer, client_id], label, opts),
          {:error, :not_found},
          label
        )
      end
    )
  end

  defp check_ambiguous!({:error, :not_found}, _records, _label, _opts), do: :ok

  defp check_ambiguous!({:ok, record}, records, label, opts) do
    resolved = resolve!(record, Registerable, label)
    expected = Enum.find(records, &(resolve!(&1, Registerable, label) == resolved))
    expect!(expected != nil, true, label)
    check_record!({:ok, record}, expected, Registerable, label, opts)
  end

  defp check_ambiguous!(result, _records, label, _opts),
    do: fail!(label, "a matching registration or {:error, :not_found}", result)

  defp check_deployments!(
         adapter,
         [first, second, third, first_extra, third_extra] = platforms,
         opts
       ) do
    label = "#{inspect(adapter)} get_deployment/3"

    ownership_visible =
      record_identity!(first.deployment, Deployable, opts, label) !=
        record_identity!(third.deployment, Deployable, opts, label)

    Enum.each(platforms, fn platform ->
      registration = stored_registration!(adapter, platform, opts)
      deployment = resolve!(platform.deployment, Deployable, "deployment factory")

      label =
        "#{inspect(adapter)} get_deployment/3 must return the deployment for this registration"

      result =
        call!(adapter, :get_deployment, [registration, deployment.deployment_id], label, opts)

      check_record!(result, platform.deployment, Deployable, label, opts)

      missing = "Missing-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      check_missing_deployment!(adapter, registration, missing, opts, "unknown deployment", nil)

      check_missing_deployment!(
        adapter,
        registration,
        String.downcase(deployment.deployment_id),
        opts,
        "case-sensitive deployment_id",
        nil
      )
    end)

    Enum.each(
      [{first, second}, {second, first}, {first, third_extra}, {third, first_extra}],
      fn {target, source} ->
        registration = stored_registration!(adapter, target, opts)
        deployment = resolve!(source.deployment, Deployable, "deployment factory")
        forbidden = if ownership_visible, do: source.deployment

        check_missing_deployment!(
          adapter,
          registration,
          deployment.deployment_id,
          opts,
          "deployment scoped to another registration or issuer",
          forbidden
        )
      end
    )

    check_concurrent_deployment!(adapter, first, opts)
  end

  defp check_missing_deployment!(adapter, registration, deployment_id, opts, scenario, forbidden) do
    label = "#{inspect(adapter)} get_deployment/3 must handle #{scenario}"
    result = call!(adapter, :get_deployment, [registration, deployment_id], label, opts)

    check_deployment_policy!(
      result,
      deployment_id,
      Keyword.fetch!(opts, :auto_create_deployments),
      label
    )

    check_created_deployment!(
      result,
      adapter,
      registration,
      deployment_id,
      opts,
      label,
      forbidden
    )
  end

  defp check_deployment_policy!(result, _deployment_id, false, label),
    do: expect!(result, {:error, :not_found}, label)

  defp check_deployment_policy!({:ok, record}, deployment_id, true, label),
    do: expect!(resolve!(record, Deployable, label), Deployment.new!(deployment_id), label)

  defp check_deployment_policy!(result, _deployment_id, true, label),
    do: fail!(label, "{:ok, a Deployable record}", result)

  defp check_created_deployment!(
         {:error, :not_found},
         _adapter,
         _registration,
         _deployment_id,
         _opts,
         _label,
         _forbidden
       ),
       do: :ok

  defp check_created_deployment!(
         {:ok, record},
         adapter,
         registration,
         deployment_id,
         opts,
         label,
         forbidden
       ) do
    if forbidden != nil do
      expect!(
        record_identity!(record, Deployable, opts, label) !=
          record_identity!(forbidden, Deployable, opts, label),
        true,
        "#{label}. The record identity must not belong to another registration"
      )
    end

    repeated = call!(adapter, :get_deployment, [registration, deployment_id], label, opts)
    check_record!(repeated, record, Deployable, "#{label} on repeated lookup", opts)
  end

  defp check_concurrent_deployment!(adapter, platform, opts) do
    check_concurrent_deployment!(
      adapter,
      platform,
      opts,
      Keyword.fetch!(opts, :auto_create_deployments)
    )
  end

  defp check_concurrent_deployment!(_adapter, _platform, _opts, false), do: :ok

  defp check_concurrent_deployment!(adapter, platform, opts, true) do
    registration = stored_registration!(adapter, platform, opts)

    deployment_id =
      "Concurrent-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"

    label = "#{inspect(adapter)} get_deployment/3"
    creation_label = "#{label} during concurrent creation"

    operation = fn ->
      call!(adapter, :get_deployment, [registration, deployment_id], creation_label, opts)
    end

    [first, second] = concurrent_results!(operation, opts, creation_label)
    check_deployment_policy!(first, deployment_id, true, creation_label)
    {:ok, record} = first
    check_record!(second, record, Deployable, "#{label} between concurrent results", opts)
    check_record!(operation.(), record, Deployable, "#{label} after concurrent creation", opts)
  end

  defp check_nonces!(adapter, platform, opts) do
    registration = stored_registration!(adapter, platform, opts)
    expires_at = DateTime.add(DateTime.utc_now(:second), 300)
    nonce = "Nonce-#{Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)}"
    label = "#{inspect(adapter)} validate_nonce/4"

    validate = fn nonce, label ->
      call!(adapter, :validate_nonce, [nonce, registration, expires_at], label, opts)
    end

    check = fn nonce, expected, requirement ->
      label = "#{label} must #{requirement}"
      expect!(validate.(nonce, label), expected, label)
    end

    check.(nonce, :ok, "accept a nonce the first time")
    check.(nonce, {:error, :nonce_already_used}, "reject a nonce already used")
    check.(String.downcase(nonce), :ok, "treat nonces as case-sensitive")

    check_concurrent_nonce!(validate, label, opts)
  end

  defp check_concurrent_nonce!(validate, label, opts) do
    nonce = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    label = "#{label} must record a nonce atomically under concurrent attempts"
    operation = fn -> validate.(nonce, label) end
    results = concurrent_results!(operation, opts, label)

    expect!(
      Enum.sort(results),
      [:ok, {:error, :nonce_already_used}],
      "#{label}. Results were #{inspect(results)}"
    )
  end

  # Signs the way the library does and verifies the result against the key
  # set the tool publishes.
  # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
  defp check_signing!(adapter, platform, opts) do
    registration = stored_registration!(adapter, platform, opts)
    jwt = sign_jwt!(adapter, registration, opts)
    %JOSE.JWS{fields: %{"kid" => key_id}} = JOSE.JWT.peek_protected(jwt)
    keys = published_keys!(registration, opts)

    label = "#{inspect(adapter)} key_id/2 must return the ID of a key in the published key set"

    public_key =
      case Enum.find(keys, &(&1["kid"] == key_id)) do
        nil -> fail!(label, "one of #{inspect(Enum.map(keys, & &1["kid"]))}", key_id)
        key -> invoke!(fn -> JOSE.JWK.from_map(key) end, "jwks option")
      end

    label =
      "#{inspect(adapter)} sign/4 must return a signature that verifies against the published key"

    case JOSE.JWS.verify_strict(public_key, ["RS256"], jwt) do
      {true, _payload, _jws} -> :ok
      _invalid -> fail!(label, "a signature by key #{inspect(key_id)}", "another signature")
    end

    label =
      "#{inspect(adapter)} sign/4 must return {:error, reason} for a key ID it can't sign with"

    unknown_key_id = "Unknown-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"

    case call!(adapter, :sign, [registration, unknown_key_id, "message"], label, opts) do
      {:error, _reason} -> :ok
      result -> fail!(label, "{:error, reason}", result)
    end
  end

  defp sign_jwt!(adapter, registration, opts) do
    label = "#{inspect(adapter)} signing"

    case invoke!(
           fn ->
             StorageAdapter.sign_jwt(
               adapter,
               registration,
               %{"sub" => "check"},
               Keyword.fetch!(opts, :storage_adapter_options)
             )
           end,
           label
         ) do
      {:ok, jwt} ->
        jwt

      {:error, %StorageError{callback: :key_id, result: result}} ->
        fail!(
          "#{inspect(adapter)} key_id/2 must return {:ok, key_id} with a non-empty string",
          "{:ok, key_id}",
          result
        )

      {:error, %StorageError{callback: :sign, result: result}} ->
        fail!(
          "#{inspect(adapter)} sign/4 must return {:ok, signature} with the RS256 signature",
          "{:ok, signature}",
          result
        )

      {:error, error} ->
        fail!(label, "{:ok, jwt}", error)
    end
  end

  # Returns the keys of the key set the `:jwks` option returns.
  defp published_keys!(registration, opts) do
    keys =
      case invoke!(fn -> Keyword.fetch!(opts, :jwks).(registration) end, "jwks option") do
        %{"keys" => keys} when is_list(keys) -> keys
        result -> fail!("The jwks option must return a key set", ~s(%{"keys" => [...]}), result)
      end

    expect!(
      Enum.any?(keys, &is_map_key(&1, "d")),
      false,
      "The jwks option must return a key set without a private key"
    )

    keys
  end

  defp concurrent_results!(operation, opts, label) do
    {:ok, supervisor} = Task.Supervisor.start_link()
    parent = self()
    reference = make_ref()
    timeout = Keyword.fetch!(opts, :timeout)
    prepare_process = Keyword.get(opts, :prepare_process, fn -> :ok end)

    tasks =
      for _ <- 1..2 do
        Task.Supervisor.async_nolink(supervisor, fn ->
          prepare_process.()
          send(parent, {reference, :ready, self()})

          receive do
            {^reference, :run} -> operation.()
          end
        end)
      end

    try do
      Enum.each(tasks, fn task ->
        receive do
          {^reference, :ready, pid} when pid == task.pid ->
            :ok

          {:DOWN, monitor, :process, pid, reason} when monitor == task.ref and pid == task.pid ->
            fail!(label, "a prepared callback process", {:exit, reason})
        after
          timeout -> fail!(label, "a prepared callback process", "prepare_process timed out")
        end
      end)

      Enum.each(tasks, &send(&1.pid, {reference, :run}))

      tasks
      |> Task.yield_many(timeout)
      |> Enum.map(fn
        {_task, {:ok, result}} -> result
        {_task, {:exit, reason}} -> fail!(label, "a callback result", {:exit, reason})
        {_task, nil} -> fail!(label, "a callback result", "callback timed out")
      end)
    after
      Enum.each(tasks, fn task ->
        Task.shutdown(task, :brutal_kill)
        Process.demonitor(task.ref, [:flush])

        receive do
          {^reference, :ready, pid} when pid == task.pid -> :ok
        after
          0 -> :ok
        end
      end)

      Supervisor.stop(supervisor)
    end
  end

  defp check_record!({:ok, record}, expected, protocol, label, opts) do
    expect!(resolve!(record, protocol, label), resolve!(expected, protocol, label), label)
    actual_identity = record_identity!(record, protocol, opts, label)
    expected_identity = record_identity!(expected, protocol, opts, label)
    expect!(actual_identity == expected_identity, true, "#{label} must preserve record identity")
  end

  defp check_record!(result, _expected, protocol, label, _opts),
    do: fail!(label, "{:ok, a #{inspect(protocol)} record}", result)

  defp record_identity!(record, protocol, opts, label) do
    identity = identity_function(opts, protocol)
    invoke!(fn -> identity.(record) end, "#{label} record identity")
  end

  defp identity_function(opts, Registerable),
    do: Keyword.get(opts, :registration_identity, fn record -> record end)

  defp identity_function(opts, Deployable),
    do: Keyword.get(opts, :deployment_identity, fn record -> record end)

  defp resolve!(record, protocol, label) do
    result =
      invoke!(fn -> convert(record, protocol) end, "#{label} #{inspect(protocol)} conversion")

    validate_resolved!(result, protocol, label)
  end

  defp convert(record, Registerable), do: Records.convert(record, :registration)
  defp convert(record, Deployable), do: Records.convert(record, :deployment)

  defp validate_resolved!({:ok, %Registration{} = registration}, Registerable, label),
    do: validated!(Registration.new(Map.from_struct(registration)), Registerable, label)

  defp validate_resolved!({:ok, %Deployment{} = deployment}, Deployable, label),
    do: validated!(Deployment.new(deployment.deployment_id), Deployable, label)

  defp validate_resolved!(result, protocol, label),
    do: fail!(label, "a valid #{inspect(protocol)} conversion", result)

  defp validated!({:ok, value}, _protocol, _label), do: value

  defp validated!(result, protocol, label),
    do: fail!(label, "a valid #{inspect(protocol)} conversion", result)

  # Returns the record the adapter's `get_registration/3` returns for a
  # platform, which is the record a launch passes to the other callbacks.
  defp stored_registration!(adapter, platform, opts) do
    label = "#{inspect(adapter)} get_registration/3 must return the registration"
    resolved = resolve!(platform.registration, Registerable, "registration factory")

    case call!(adapter, :get_registration, [resolved.issuer, resolved.client_id], label, opts) do
      {:ok, registration} -> registration
      result -> fail!(label, "{:ok, registration}", result)
    end
  end

  # Calls a callback with the storage adapter options as its last argument.
  defp call!(adapter, callback, args, label, opts) do
    args = args ++ [Keyword.fetch!(opts, :storage_adapter_options)]
    invoke!(fn -> apply(adapter, callback, args) end, label)
  end

  # User callbacks and protocol implementations can fail with any exception.
  # Preserve their stacktrace while adding the contract scenario to the failure.
  defp invoke!(function, label) do
    function.()
  rescue
    exception ->
      reraise ExUnit.AssertionError.exception(
                message: "#{label}. #{Exception.message(exception)}"
              ),
              __STACKTRACE__
  catch
    kind, reason ->
      reraise ExUnit.AssertionError.exception(
                message: "#{label}. #{Exception.format(kind, reason, __STACKTRACE__)}"
              ),
              __STACKTRACE__
  end

  defp expect!(actual, expected, _label) when actual == expected, do: :ok

  defp expect!(actual, expected, label),
    do: fail!(label, inspect(expected, limit: 10, printable_limit: 200), actual)

  defp fail!(label, expected, actual) do
    raise ExUnit.AssertionError,
      message:
        "#{label}. Expected #{expected}, got #{inspect(actual, limit: 10, printable_limit: 200)}."
  end
end
