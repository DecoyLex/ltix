defmodule Ltix.Claims do
  @moduledoc """
  Parses and checks a message's raw claims with a plugin set's declared claims.

  `Ltix.Claim` describes how each claim is parsed and checked.
  """
  use Ltix.Provider

  alias Ltix.Claim.Declaration
  alias Ltix.Errors
  alias Ltix.Errors.Invalid.InvalidEndpoint
  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.PluginSet
  alias Ltix.PluginSet.Conflict
  alias Ltix.PluginSet.Entry

  @impl Ltix.Provider
  def resolve(plugins) do
    entries = unique_entries(plugins, Ltix.Claim)
    endpoints = Enum.filter(entries, &Keyword.has_key?(&1.opts, :service))
    checks = unique_entries(plugins, Ltix.Claims.Check)
    overrides = unique_entries(plugins, Ltix.Claims.Override)
    uris = MapSet.new(entries, & &1.opts[:claim])

    by_uri = Conflict.duplicates(entries, & &1.opts[:claim], &"both declare the claim #{&1}")

    # Entries that declare one URI and one short name conflict once.
    by_name =
      for conflict <-
            Conflict.duplicates(
              entries,
              & &1.opts[:name],
              &"both declare the short name #{inspect(&1)}"
            ),
          !Enum.any?(by_uri, &(&1.parties == conflict.parties)),
          do: conflict

    conflicts =
      by_uri ++
        by_name ++
        Conflict.duplicates(
          endpoints,
          & &1.opts[:service],
          &"both declare the endpoint of #{inspect(&1)}"
        ) ++
        for endpoint <- endpoints, !checkable?(endpoint.module) do
          %Conflict{
            parties: [endpoint],
            reason:
              "declares the endpoint of #{inspect(endpoint.opts[:service])}, which needs the fields option and new/1"
          }
        end ++
        for check <- checks, !MapSet.member?(uris, check.opts[:claim]) do
          %Conflict{
            parties: [check],
            reason: "checks the claim #{check.opts[:claim]}, which no plugin declares"
          }
        end ++
        override_conflicts(overrides)

    case conflicts do
      [] ->
        overrides = Enum.group_by(overrides, & &1.opts[:check])
        declarations = Enum.map(entries, &declaration(&1, checks, overrides))

        {:ok,
         %{
           by_uri: Map.new(declarations, &{&1.uri, &1}),
           by_name: Map.new(declarations, &{&1.name, &1.uri}),
           defaults: Map.new(declarations, &{&1.name, &1.default})
         }}

      conflicts ->
        {:error, conflicts}
    end
  end

  defp unique_entries(plugins, provider),
    do: Enum.uniq_by(PluginSet.entries(plugins, provider), &{&1.module, &1.opts})

  defp override_conflicts(overrides) do
    replaced =
      for override <- overrides,
          message_type <- override.opts[:message_types],
          uniq: true,
          do: {{override.opts[:check], message_type}, override}

    for {{check, message_type}, [_, _ | _] = parties} <-
          Enum.group_by(replaced, &elem(&1, 0), &elem(&1, 1)) do
      %Conflict{
        parties: parties,
        reason: "both override the check of #{inspect(check)} in #{message_type}"
      }
    end
  end

  defp declaration(%Entry{module: claim, opts: opts} = entry, checks, overrides) do
    uri = Keyword.fetch!(opts, :claim)
    name = Keyword.fetch!(opts, :name)

    %Declaration{
      claim: claim,
      opts: opts,
      uri: uri,
      name: name,
      label: label(uri, name),
      service: Keyword.get(opts, :service),
      strict: Keyword.get(opts, :strict, true),
      default: Keyword.get(opts, :default),
      checks: claim_checks(entry, checks, overrides)
    }
  end

  @doc false
  @spec declaration(PluginSet.t(), atom()) :: Declaration.t() | nil
  def declaration(%PluginSet{} = plugins, name) do
    %{by_uri: by_uri, by_name: by_name} = PluginSet.data(plugins, __MODULE__)
    Map.get(by_uri, by_name[name])
  end

  # The checks of a claim, the declaring module's first. Each has the module
  # that overrides refer to, or `nil` for an anonymous check, the message
  # types it runs in, the function that runs it, and the function of each
  # override, keyed by the message types the override lists. `overrides` are
  # grouped by the check they replace.
  defp claim_checks(%Entry{module: claim, opts: opts}, checks, overrides) do
    own =
      if function_exported?(claim, :check, 2), do: [{claim, :all, &claim.check/2}], else: []

    added =
      for %Entry{opts: check_opts} = check <- checks,
          check_opts[:claim] == opts[:claim],
          do: {check_module(check), Keyword.get(check_opts, :message_types, :all), run(check)}

    for {check, message_types, run} <- own ++ added do
      replacements =
        for override <- Map.get(overrides, check, []),
            check != nil,
            message_type <- override.opts[:message_types],
            into: %{},
            do: {message_type, run(override)}

      %{check: check, message_types: message_types, run: run, overrides: replacements}
    end
  end

  # The module of a check, or `nil` for an anonymous one.
  defp check_module(%Entry{module: module} = check),
    do: if(Entry.anonymous?(check), do: nil, else: module)

  # The function that runs a check or an override.
  defp run(%Entry{module: Ltix.Claims.Check, opts: opts}), do: Keyword.fetch!(opts, :check)
  defp run(%Entry{module: Ltix.Claims.Override, opts: opts}), do: Keyword.fetch!(opts, :with)
  defp run(%Entry{module: module}), do: &module.check/2

  # An error refers to a claim by its registered JWT name, such as `sub`,
  # when it has one, and otherwise by its short name. A registered JWT name
  # isn't a URI.
  defp label(uri, name), do: if(String.contains?(uri, "/"), do: Atom.to_string(name), else: uri)

  # Ltix checks an endpoint by building it again from its fields with `new/1`.
  defp checkable?(endpoint),
    do: function_exported?(endpoint, :__ltix_type__, 1) && function_exported?(endpoint, :new, 1)

  # Checks each endpoint with the `new/1` of the claim that declares its
  # service's endpoint. Returns the first error.
  @doc false
  @spec validate_endpoints(%{module() => term()}, PluginSet.t()) :: :ok | {:error, Exception.t()}
  def validate_endpoints(endpoints, %PluginSet{} = plugins) do
    declared =
      for %{service: service} = declaration <-
            Map.values(PluginSet.data(plugins, __MODULE__).by_uri),
          service != nil,
          into: %{},
          do: {service, declaration}

    Enum.reduce_while(endpoints, :ok, fn {service, endpoint}, :ok ->
      case validate_endpoint(Map.get(declared, service), service, endpoint) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # [Core §6.1](https://www.imsglobal.org/spec/lti/v1p3/#services-exposed-as-additional-claims)
  defp validate_endpoint(nil, service, _endpoint) do
    {:error,
     ServiceNotAvailable.exception(
       service: service,
       reason: "No plugin declares the endpoint claim of this service"
     )}
  end

  defp validate_endpoint(%{claim: claim}, _service, %claim{} = endpoint) do
    with {:ok, _endpoint} <- claim.new(Map.take(endpoint, Keyword.keys(Ltix.Type.fields(claim)))),
         do: :ok
  end

  defp validate_endpoint(_declaration, service, _endpoint),
    do: {:error, InvalidEndpoint.exception(service: service)}

  @doc """
  Parses a message's raw claims.

  Returns `{:ok, claims, endpoints}`. `claims` is keyed by short name and has a
  key for every declared claim. A claim that's absent or `null` is its
  `:default`, such as `[]` for `:roles`, or `nil` without one. Claims no plugin
  declares aren't keys. `endpoints` has the endpoint claims, keyed by service.

  When declared claims are malformed, returns
  `{:error, error, claims, endpoints}`, where `error` has the error of every
  malformed claim. When a claim is declared with
  [`strict: false`](`m:Ltix.Claim#module-options`), a malformed value is its
  `:default` and has no error.

      iex> {:ok, plugins} = Ltix.PluginSet.resolve([])
      iex> {:ok, claims, _endpoints} =
      ...>   Ltix.Claims.parse(
      ...>     %{
      ...>       "https://purl.imsglobal.org/spec/lti/claim/version" => "1.3.0",
      ...>       "https://lms.example.com/claim/unknown" => true
      ...>     },
      ...>     plugins
      ...>   )
      iex> {claims.version, claims.context, claims.roles}
      {"1.3.0", nil, []}
  """
  @spec parse(map(), PluginSet.t()) ::
          {:ok, claims, endpoints} | {:error, Exception.t(), claims, endpoints}
        when claims: %{atom() => term()}, endpoints: %{module() => term()}
  def parse(raw, %PluginSet{} = plugins) when is_map(raw) do
    {error, sent, endpoints} = parse_sent(raw, plugins)
    claims = Map.merge(PluginSet.data(plugins, __MODULE__).defaults, sent)

    case error do
      nil -> {:ok, claims, endpoints}
      error -> {:error, error, claims, endpoints}
    end
  end

  # Parses the declared claims a message has, and leaves out the claims it
  # doesn't have. Returns the error of every malformed claim, or `nil`, with
  # the claims and endpoints. A malformed claim declared with `strict: false`
  # has no error.
  @doc false
  @spec parse_sent(map(), PluginSet.t()) ::
          {Exception.t() | nil, %{atom() => term()}, %{module() => term()}}
  def parse_sent(raw, %PluginSet{} = plugins) when is_map(raw) do
    declared = PluginSet.data(plugins, __MODULE__).by_uri

    parsed =
      for {uri, value} <- raw,
          value not in [nil, :null],
          {:ok, declaration} <- [Map.fetch(declared, uri)],
          do: {declaration, value, parse_claim(declaration, value, plugins)}

    errors =
      for {declaration, value, {:error, reason}} <- parsed,
          declaration.strict,
          do: Errors.from_reason(reason, value, declaration.label)

    values = for {declaration, _value, {:ok, parsed}} <- parsed, do: {declaration, parsed}
    claims = Map.new(values, fn {declaration, parsed} -> {declaration.name, parsed} end)

    endpoints =
      for {%{service: service}, parsed} <- values,
          service != nil,
          into: %{},
          do: {service, parsed}

    case errors do
      [] -> {nil, claims, endpoints}
      errors -> {Errors.combine(errors), claims, endpoints}
    end
  end

  defp parse_claim(%{claim: claim, opts: opts} = declaration, value, plugins) do
    with {:ok, parsed} <- claim.parse(value, opts),
         do: parse_extensions(parsed, declaration, plugins)
  end

  # Parses the properties of an object claim.
  defp parse_extensions(%claim{} = parsed, %{claim: claim} = declaration, plugins),
    do: Ltix.Type.parse_extensions(parsed, plugins, name: declaration.label)

  defp parse_extensions(parsed, _declaration, _plugins), do: {:ok, parsed}

  @doc """
  Serializes parsed claims, keyed by short name, to raw claims keyed as a
  platform sends them, with the claims a plugin set declares.

  An object claim includes every property it has a value for, and a `nil`
  claim is left out. Raises `ArgumentError` for a claim no plugin in the set
  declares.

      iex> {:ok, plugins} = Ltix.PluginSet.resolve([])
      iex> Ltix.Claims.serialize(%{custom: %{"country" => "Canada"}}, plugins)
      %{"https://purl.imsglobal.org/spec/lti/claim/custom" => %{"country" => "Canada"}}
  """
  @spec serialize(%{atom() => term()}, PluginSet.t()) :: map()
  def serialize(claims, %PluginSet{} = plugins) when is_map(claims) do
    declared =
      for {uri, declaration} <- PluginSet.data(plugins, __MODULE__).by_uri,
          into: %{},
          do: {declaration.name, {uri, declaration}}

    for {name, value} <- claims, value != nil, into: %{} do
      case Map.fetch(declared, name) do
        {:ok, {uri, declaration}} -> {uri, serialize_claim(declaration, value, plugins)}
        :error -> raise ArgumentError, "no plugin declares the claim #{inspect(name)}"
      end
    end
  end

  defp serialize_claim(%{claim: claim}, %claim{} = value, plugins),
    do: Ltix.Type.to_json(value, plugins, :read)

  defp serialize_claim(%{claim: claim, opts: opts}, value, _plugins),
    do: claim.serialize(value, opts)

  @doc """
  Runs the checks of every claim in `claims` for a message of `message_type`.

  Takes the parsed claims, keyed by short name, and skips claims that are
  `nil`. Returns the errors of every check that fails, combined into one Ltix
  error.

      iex> {:ok, plugins} = Ltix.PluginSet.resolve([])
      iex> Ltix.Claims.check(%{version: "1.3.0"}, "LtiResourceLinkRequest", plugins)
      :ok
      iex> {:error, error} = Ltix.Claims.check(%{version: "1.2.0"}, "LtiResourceLinkRequest", plugins)
      iex> Exception.message(error)
      "Invalid LTI claim version: unrecognized LTI version (got \\"1.2.0\\")"
  """
  @spec check(%{atom() => term()}, String.t() | nil, PluginSet.t()) ::
          :ok | {:error, Exception.t()}
  def check(claims, message_type, %PluginSet{} = plugins) when is_map(claims),
    do: check(claims, claims, message_type, plugins)

  # Runs the checks of the claims in `sent`, each with every claim in `claims`.
  @doc false
  @spec check(%{atom() => term()}, %{atom() => term()}, String.t() | nil, PluginSet.t()) ::
          :ok | {:error, Exception.t()}
  def check(claims, sent, message_type, %PluginSet{} = plugins) do
    Errors.collect(
      for {_uri, declaration} <- PluginSet.data(plugins, __MODULE__).by_uri,
          {:ok, value} when value != nil <- [Map.fetch(sent, declaration.name)],
          entry <- declaration.checks,
          runs_in?(entry.message_types, message_type),
          run <- [Map.get(entry.overrides, message_type, entry.run)],
          {:error, reason} <- [run.(value, claims)],
          do: Errors.from_reason(reason, value, declaration.label)
    )
  end

  defp runs_in?(:all, _message_type), do: true
  defp runs_in?(message_types, message_type), do: message_type in message_types
end
