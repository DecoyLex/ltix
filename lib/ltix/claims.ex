defmodule Ltix.Claims do
  @moduledoc """
  Parses a message's claims with the claims a plugin set declares.

  Each claim is declared by one entry of `Ltix.Claim`, a claim module or an
  anonymous claim. Ltix parses a
  launch's claims between `Ltix.Launch.ClaimsReceived` and
  `Ltix.Launch.ClaimsParsed`, and writes them to the launch's `claims` and
  `endpoints`.

  ## Parsing

    * Each declared claim present in the message is parsed with its
      `c:Ltix.Property.parse/2`, and is in `claims` under its short name. A
      claim whose value is `null` counts as absent.
    * `claims` has a key for every declared claim. A claim the message
      doesn't have is its `:default`, such as `[]` for `:roles`, or `nil`.
    * A malformed claim is its `:default` in `claims`. It fails the call,
      unless its declaration has `strict: false`.
    * The value of an endpoint claim is also in `endpoints`, under its
      service.
    * Claims no entry declares are left out. They are still in the message's
      raw claims.

  ## Conflicts

  Resolution fails with `Ltix.Errors.Unknown.InvalidPluginSet` when two
  entries declare one claim URI, one short name, or the endpoint of one
  service. A claim module added several times with the same options, or the
  same anonymous claim added several times, doesn't conflict.
  """
  use Ltix.Provider

  alias Ltix.Claim.Declaration
  alias Ltix.Errors
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.PluginSet
  alias Ltix.PluginSet.Conflict
  alias Ltix.PluginSet.Entry

  @impl Ltix.Provider
  def resolve(plugins) do
    entries = Enum.uniq_by(PluginSet.entries(plugins, Ltix.Claim), &{&1.module, &1.opts})
    endpoints = Enum.filter(entries, &Keyword.has_key?(&1.opts, :service))

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
        )

    case conflicts do
      [] -> {:ok, Map.new(entries, &{&1.opts[:claim], declaration(&1)})}
      conflicts -> {:error, conflicts}
    end
  end

  defp declaration(%Entry{module: claim, opts: opts}) do
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
      default: Keyword.get(opts, :default)
    }
  end

  # An error refers to a claim by its registered JWT name, such as `sub`,
  # when it has one, and otherwise by its short name. A registered JWT name
  # isn't a URI.
  defp label(uri, name), do: if(String.contains?(uri, "/"), do: Atom.to_string(name), else: uri)

  @doc """
  Parses raw claims with the claims a plugin set declares.

  Returns the parsed claims keyed by short name, and the endpoints keyed by
  service. The claims have a key for every declared claim. A claim that's
  absent, `null`, or malformed is its `:default`, such as `[]` for `:roles`,
  or `nil` without one. When a claim declared without `strict: false` is
  malformed, returns the errors of every such claim, combined into one Ltix
  error, with the claims and endpoints.
  """
  @spec parse(map(), PluginSet.t()) ::
          {:ok, claims, endpoints} | {:error, Exception.t(), claims, endpoints}
        when claims: %{atom() => term()}, endpoints: %{module() => term()}
  def parse(raw, %PluginSet{} = plugins) when is_map(raw) do
    {error, sent, endpoints} = parse_sent(raw, plugins)
    claims = Map.merge(defaults(plugins), sent)

    case error do
      nil -> {:ok, claims, endpoints}
      error -> {:error, error, claims, endpoints}
    end
  end

  # Parses the declared claims a message has, and leaves out the claims it
  # doesn't have. Returns the error of the malformed claims declared without
  # `strict: false`, or `nil`, with the claims and endpoints.
  @doc false
  @spec parse_sent(map(), PluginSet.t()) ::
          {Exception.t() | nil, %{atom() => term()}, %{module() => term()}}
  def parse_sent(raw, %PluginSet{} = plugins) when is_map(raw) do
    declared = PluginSet.data(plugins, __MODULE__)

    parsed =
      for {uri, value} <- raw,
          value not in [nil, :null],
          {:ok, declaration} <- [Map.fetch(declared, uri)],
          do: {declaration, value, declaration.claim.parse(value, declaration.opts)}

    errors =
      for {declaration, value, {:error, reason}} <- parsed,
          declaration.strict,
          do: error(declaration, value, reason)

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

  # The value of each declared claim when a message doesn't have it, keyed by
  # short name.
  @doc false
  @spec defaults(PluginSet.t()) :: %{atom() => term()}
  def defaults(%PluginSet{} = plugins) do
    for {_uri, declaration} <- PluginSet.data(plugins, __MODULE__),
        into: %{},
        do: {declaration.name, declaration.default}
  end

  defp error(%{label: name}, value, reason) do
    cond do
      is_list(reason) && Enum.all?(reason, &is_struct(&1, Zoi.Error)) ->
        Errors.from_zoi(reason, value, name)

      Errors.ltix_error?(reason) ->
        reason

      true ->
        InvalidClaim.exception(claim: name, value: value, message: message(reason))
    end
  end

  defp message(reason) when is_binary(reason), do: reason
  defp message(reason) when is_exception(reason), do: Exception.message(reason)
  defp message(reason), do: inspect(reason)
end
