defmodule Ltix.Plugin do
  @moduledoc """
  A group of modules, such as login steps and claims, that an application
  enables together.

      defmodule MyLibrary do
        @behaviour Ltix.Plugin

        @impl Ltix.Plugin
        def plugin(opts) do
          Ltix.Plugin.new(name: "My Library", version: "1.0.0")
          |> Ltix.Plugin.add(MyLibrary.Report)
          |> Ltix.Plugin.add({MyLibrary.LoginTenant, tenant: opts[:tenant]})
          |> Ltix.Plugin.depend_on(OtherLibrary)
        end
      end

  An application enables plugins in its configuration or with a call's
  `plugins:` option.

      config :ltix, plugins: [{MyLibrary, tenant: "acme"}]

  [Writing Plugins](writing-plugins.md) shows how to write a plugin.

  ## Fields

    * `:name` and `:version` - the plugin's name and version
    * `:providers` - the modules the plugin provides
    * `:entries` - the modules the plugin adds that extend other modules, and
      its anonymous steps, claims, and properties, as `Ltix.PluginSet.Entry`
      structs
    * `:dependencies` - the plugins this plugin depends on
  """

  alias Ltix.Options
  alias Ltix.PluginSet.Entry
  alias Ltix.Provider

  defstruct name: nil, version: nil, providers: [], entries: [], dependencies: []

  @type t :: %__MODULE__{
          name: String.t() | nil,
          version: String.t() | nil,
          providers: [module()],
          entries: [Entry.t()],
          dependencies: [module()]
        }

  @doc """
  Returns the plugin's declaration.

  Receives the options the application enabled the plugin with. A dependency
  the application doesn't enable gets `[]`.
  """
  @callback plugin(opts :: term()) :: t()

  @new_schema Zoi.keyword(
                [name: Zoi.string() |> Zoi.optional(), version: Zoi.string() |> Zoi.optional()],
                unrecognized_keys: :error
              )

  @doc """
  Creates a plugin's declaration.

  The name and version appear in error messages, such as those of
  `Ltix.Errors.Unknown.InvalidPluginSet`. Raises
  `Ltix.Errors.Invalid.InvalidOption` for an unknown option or a value that
  isn't a string.

  ## Options

    * `:name` - the plugin's name
    * `:version` - the plugin's version

  ## Examples

      iex> Ltix.Plugin.new(name: "My Library", version: "1.0.0")
      %Ltix.Plugin{name: "My Library", version: "1.0.0"}
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []), do: struct!(__MODULE__, Options.parse!(opts, @new_schema))

  @doc """
  Adds a module to the plugin, as `MyModule` or `{MyModule, opts}`.
  `MyModule` is the same as `{MyModule, []}`.

  Add each module your plugin declares, such as a login step, a claim, or a
  content item type. A step added twice runs twice, once with each call's
  options. Add an anonymous step, claim, or property with its provider's
  function, such as `Ltix.Login.add_step/2` or `Ltix.Claim.add/2`.

  Two claims with the same URI or short name make the plugin set fail to
  resolve. See [Conflicts](`m:Ltix.Claims#module-conflicts`).

  Raises `ArgumentError` for a module that extends nothing and isn't a
  provider, for options on a module that is only a provider, and for an option
  the module's `use` already sets.

  ## Examples

      iex> Ltix.Plugin.new()
      ...> |> Ltix.Plugin.add(Ltix.Login)
      ...> |> Ltix.Plugin.add(Ltix.Login.RegistrationFound)
      %Ltix.Plugin{
        providers: [Ltix.Login],
        entries: [%Ltix.PluginSet.Entry{module: Ltix.Login.RegistrationFound}]
      }
  """
  @spec add(t(), module() | {module(), term()}) :: t()
  def add(%__MODULE__{} = plugin, {module, opts}) when is_atom(module) do
    cond do
      extender?(module) ->
        plugin = add_entry(plugin, %Entry{module: module, opts: entry_opts!(module, opts)})
        if Provider.provider?(module), do: put_provider(plugin, module), else: plugin

      !Provider.provider?(module) ->
        raise ArgumentError,
              "#{inspect(module)} doesn't extend a module or call `use Ltix.Provider`. " <>
                "Add `use` with the module it extends, such as `use Ltix.Login`, or `use Ltix.Provider` to it."

      opts == [] ->
        put_provider(plugin, module)

      true ->
        raise ArgumentError,
              "#{inspect(module)} extends no module, so it takes no options. Add it as #{inspect(module)}."
    end
  end

  def add(%__MODULE__{} = plugin, module) when is_atom(module), do: add(plugin, {module, []})

  # The options of the module's `use` calls, followed by `opts`.
  defp entry_opts!(module, opts) do
    case Provider.use_options(module) do
      [] ->
        opts

      fixed ->
        unless Keyword.keyword?(opts) do
          raise ArgumentError,
                "#{inspect(module)} sets options with `use`, so a plugin can add it only with a keyword list, got #{inspect(opts)}"
        end

        case Enum.filter(Keyword.keys(opts), &Keyword.has_key?(fixed, &1)) do
          [] ->
            fixed ++ opts

          keys ->
            keys = Enum.map_join(keys, " and ", &inspect/1)

            raise ArgumentError,
                  "#{inspect(module)} sets #{keys} with `use`, so a plugin can't add it with #{keys}"
        end
    end
  end

  defp put_provider(plugin, provider),
    do: %{plugin | providers: Enum.uniq(plugin.providers ++ [provider])}

  # Appends an entry. `add/2` and the functions that add anonymous steps, such
  # as `Ltix.Step.add/3`, call it.
  @doc false
  @spec add_entry(t(), Entry.t()) :: t()
  def add_entry(%__MODULE__{} = plugin, %Entry{} = entry),
    do: %{plugin | entries: plugin.entries ++ [entry]}

  # Returns the entries `changed` appends to the entries of `plugin`, or
  # `:error` when `changed` differs from `plugin` in any other way.
  @doc false
  @spec added_entries(t(), term()) :: {:ok, [Entry.t()]} | :error
  def added_entries(%__MODULE__{entries: entries} = plugin, %__MODULE__{} = changed) do
    {kept, added} = Enum.split(changed.entries, length(entries))

    if kept == entries && %{changed | entries: []} == %{plugin | entries: []},
      do: {:ok, added},
      else: :error
  end

  def added_entries(%__MODULE__{}, _changed), do: :error

  @doc """
  Adds a dependency to the plugin.

  [Resolution](`m:Ltix.PluginSet#module-resolution`) adds the dependency to the
  plugin set. Raises `ArgumentError` for a module that isn't a plugin.

  ## Examples

      iex> defmodule Blocklist do
      ...>   @behaviour Ltix.Plugin
      ...>   def plugin(_opts), do: Ltix.Plugin.new(name: "Blocklist")
      ...> end
      iex> plugin =
      ...>   Ltix.Plugin.new(name: "My Profile")
      ...>   |> Ltix.Plugin.depend_on(Blocklist)
      iex> plugin.dependencies
      [Blocklist]
  """
  @spec depend_on(t(), module()) :: t()
  def depend_on(%__MODULE__{} = plugin, dependency) when is_atom(dependency) do
    unless plugin?(dependency) do
      raise ArgumentError,
            "#{inspect(dependency)} is not a plugin. Add `@behaviour Ltix.Plugin` and `plugin/1` to it."
    end

    %{plugin | dependencies: plugin.dependencies ++ [dependency]}
  end

  defp extender?(module),
    do: Code.ensure_loaded?(module) && Provider.extended_providers(module) != []

  @doc false
  @spec plugin?(term()) :: boolean()
  def plugin?(module),
    do: is_atom(module) && Code.ensure_loaded?(module) && function_exported?(module, :plugin, 1)
end
