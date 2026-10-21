defmodule Ltix.PluginSet do
  @moduledoc """
  The plugins that one call into Ltix runs with.

  `resolve/1` builds a plugin set from the enabled plugins.

  ## Resolution

    * The [default plugins](`Ltix.DefaultPlugins`) come first, then the enabled
      plugins in order.
    * Each plugin comes after its dependencies.
    * A plugin enabled several times has a declaration for each entry, built with
      that entry's options.
    * Each `c:Ltix.Provider.resolve/1` runs once, in plugin order, and can read
      the data of the ones before it.

  Resolving the same plugins again returns the same plugin set without running
  plugin code. Each distinct `plugins:` list stays in memory until the node
  stops. Build these lists from a fixed set of options.

  ## Fields

    * `:plugins` - the plugins in plugin order, as `{module, %Ltix.Plugin{}}`
      pairs. A plugin's pairs are adjacent.
    * `:providers` - the provided modules

  Read the rest of a plugin set with `entries/2` and `data/2`.
  """

  alias Ltix.AppConfig
  alias Ltix.Errors.Invalid.InvalidOption
  alias Ltix.Errors.Unknown.InvalidPluginSet
  alias Ltix.Plugin
  alias Ltix.PluginSet.Conflict
  alias Ltix.PluginSet.Entry
  alias Ltix.Provider

  defstruct plugins: [], providers: [], entries: %{}, data: %{}

  @type t :: %__MODULE__{
          plugins: [{module(), Plugin.t()}],
          providers: [module()],
          entries: %{module() => [Entry.t()]},
          data: %{module() => term()}
        }

  @type enabled_plugins :: [module() | {module(), term()}]

  @doc """
  Resolves enabled plugins into a plugin set.

  Each plugin is `MyPlugin` or `{MyPlugin, opts}`, and `MyPlugin` is the same
  as `{MyPlugin, []}`. Pass `nil` for the configured plugins.
  Returns `{:ok, plugin_set}` or
  `{:error, %Ltix.Errors.Unknown.InvalidPluginSet{}}`. A plugin set passed in is
  returned unchanged.

      {:ok, plugins} = Ltix.PluginSet.resolve([{MyLibrary, tenant: "acme"}])

  An empty list gives a plugin set with only the default plugins.

      iex> {:ok, plugins} = Ltix.PluginSet.resolve([])
      iex> Enum.map(plugins.plugins, fn {module, _plugin} -> module end)
      [Ltix.Core, Ltix.DefaultPlugins]

  Raises `Ltix.Errors.Invalid.InvalidOption` when the list includes a module
  that isn't a plugin, and `ArgumentError` when a plugin's
  `c:Ltix.Plugin.plugin/1` doesn't return an `%Ltix.Plugin{}`.
  """
  @spec resolve(enabled_plugins() | t() | nil) :: {:ok, t()} | {:error, Exception.t()}
  def resolve(%__MODULE__{} = plugins), do: {:ok, plugins}
  def resolve(nil), do: resolve(AppConfig.plugins())

  def resolve(enabled) do
    enabled = normalize!(enabled)
    key = {__MODULE__, enabled}

    case :persistent_term.get(key, nil) do
      nil ->
        result = build(enabled)
        :persistent_term.put(key, result)
        result

      result ->
        result
    end
  end

  @doc """
  Returns the entries that extend `module`, as `Ltix.PluginSet.Entry` structs.

  The entries are in plugin order, or in the order their steps declare when
  they implement `Ltix.Ordered`. Returns `[]` when no plugin in the set
  provides `module`.

      iex> {:ok, plugins} = Ltix.PluginSet.resolve([])
      iex> Ltix.PluginSet.entries(plugins, Ltix.Login)
      [
        %Ltix.PluginSet.Entry{module: Ltix.Login.CheckParameters, plugin: Ltix.Core},
        %Ltix.PluginSet.Entry{module: Ltix.Login.LookUpRegistration, plugin: Ltix.Core},
        %Ltix.PluginSet.Entry{module: Ltix.Login.RegistrationFound, plugin: Ltix.Core},
        %Ltix.PluginSet.Entry{module: Ltix.Login.BuildAuthenticationRequest, plugin: Ltix.Core}
      ]
  """
  @spec entries(t(), module()) :: [Entry.t()]
  def entries(%__MODULE__{entries: entries}, module), do: Map.get(entries, module, [])

  @doc """
  Returns the data `module`'s `c:Ltix.Provider.resolve/1` returned, or `nil`
  when it has no data or isn't in the set.

      iex> {:ok, plugins} = Ltix.PluginSet.resolve([])
      iex> Ltix.PluginSet.data(plugins, Ltix.Login)
      nil
  """
  @spec data(t(), module()) :: term()
  def data(%__MODULE__{data: data}, module), do: Map.get(data, module)

  defp normalize!(enabled) when is_list(enabled), do: Enum.map(enabled, &normalize_entry!/1)
  defp normalize!(enabled), do: invalid!(enabled, "expected a list of plugins")

  defp normalize_entry!({module, opts}) do
    if Plugin.plugin?(module),
      do: {module, opts},
      else: invalid!(module, "#{inspect(module)} is not a plugin")
  end

  defp normalize_entry!(module), do: normalize_entry!({module, []})

  defp invalid!(value, reason),
    do: raise(InvalidOption, key: :plugins, value: value, reason: reason)

  defp build(enabled) do
    {plugins, cycles} = expand(enabled)

    providers =
      Enum.uniq(
        for {_plugin, declaration} <- plugins, provider <- declaration.providers, do: provider
      )

    {entries, order_conflicts} = provider_extenders(plugins, providers)
    set = %__MODULE__{plugins: plugins, providers: providers, entries: entries}

    case {cycles ++ order_conflicts, resolve_providers(set)} do
      {[], {set, []}} ->
        {:ok, set}

      {conflicts, {_set, provider_conflicts}} ->
        {:error,
         InvalidPluginSet.exception(conflicts: conflicts ++ provider_conflicts, plugins: plugins)}
    end
  end

  # Places each plugin module once, after its dependencies, with the
  # `%Ltix.Plugin{}` it returns for each time the application enables it.
  defp expand(enabled) do
    options = Enum.group_by(enabled, &elem(&1, 0), &elem(&1, 1))
    modules = Enum.uniq([Ltix.DefaultPlugins | Enum.map(enabled, &elem(&1, 0))])

    {placed, cycles} = Enum.reduce(modules, {[], []}, &place(&1, [], options, &2))
    {Enum.reverse(placed), Enum.reverse(cycles)}
  end

  defp place(module, path, options, {placed, cycles} = state) do
    cond do
      List.keymember?(placed, module, 0) ->
        state

      module in path ->
        {placed, [cycle(module, path) | cycles]}

      true ->
        declarations =
          for opts <- Map.get(options, module, [[]]), do: {module, declaration!(module, opts)}

        dependencies = Enum.uniq(Enum.flat_map(declarations, &elem(&1, 1).dependencies))

        {placed, cycles} =
          Enum.reduce(dependencies, state, &place(&1, [module | path], options, &2))

        {Enum.reverse(declarations, placed), cycles}
    end
  end

  defp declaration!(module, opts) do
    case module.plugin(opts) do
      %Plugin{} = declaration ->
        declaration

      other ->
        raise ArgumentError,
              "#{inspect(module)}.plugin/1 returned #{inspect(other)}. It must return an %Ltix.Plugin{}."
    end
  end

  # `path` is the dependency chain to `module`, nearest first.
  defp cycle(module, path) do
    case Enum.drop_while(Enum.reverse(path), &(&1 != module)) do
      [^module] -> %Conflict{parties: [module], reason: "depends on itself"}
      parties -> %Conflict{parties: parties, reason: "depend on each other in a cycle"}
    end
  end

  # Runs `init/1` only for entries that extend a provider in the set, so a
  # step that can never run isn't initialized.
  defp provider_extenders(plugins, providers) do
    entries =
      for {plugin, declaration} <- plugins,
          entry <- declaration.entries,
          extended = Enum.filter(Provider.extended_providers(entry), &(&1 in providers)),
          extended != [],
          do: {extended, %{entry | plugin: plugin, opts: init(entry.module, entry.opts)}}

    Enum.reduce(providers, {%{}, []}, fn provider, {by_provider, conflicts} ->
      extenders = for {extended, entry} <- entries, provider in extended, do: entry
      {ordered, order_conflicts} = order(provider, extenders)
      {Map.put(by_provider, provider, ordered), conflicts ++ order_conflicts}
    end)
  end

  defp init(module, opts) do
    behaviours = List.flatten(Keyword.get_values(module.module_info(:attributes), :behaviour))
    if Ltix.Step in behaviours, do: module.init(opts), else: opts
  end

  defp order(provider, extenders) do
    if Provider.hook?(provider, Ltix.Ordered),
      do: Ltix.Ordered.sort(extenders),
      else: {extenders, []}
  end

  # Runs each provider's `resolve/1` with the data of the providers before it.
  defp resolve_providers(set) do
    Enum.reduce(set.providers, {set, []}, fn provider, {set, conflicts} ->
      case resolve_provider(provider, set) do
        {:ok, data} -> {put_in(set.data[provider], data), conflicts}
        {:error, provider_conflicts} -> {set, conflicts ++ provider_conflicts}
      end
    end)
  end

  defp resolve_provider(provider, set) do
    if function_exported?(provider, :resolve, 1), do: provider.resolve(set), else: {:ok, nil}
  end
end
