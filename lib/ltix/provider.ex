defmodule Ltix.Provider do
  @moduledoc """
  Lets other plugins add steps, properties, or callbacks to a module of your
  plugin.

  ```elixir
  defmodule MyLibrary.Report do
    use Ltix.Provider, hook: [Ltix.Step, Ltix.Ordered]

    defstruct params: %{}, private: %{}, errors: [], plugins: nil
  end
  ```

  Other plugins add steps to it with `use MyLibrary.Report`, and your library
  runs them with `Ltix.Step.run/1`. Define callbacks of your own with
  `@callback`. When a module calls `use MyLibrary.Report` with options, every
  entry a plugin adds for the module includes them, and a plugin can't set them
  again when it adds the module.
  [Provide something for other plugins to extend](writing-plugins.md#provide-something-for-other-plugins-to-extend)
  has a complete example.

  ## Options

    * `:hook` - the behaviours that modules extending yours implement, such as
      `Ltix.Step` and `Ltix.Ordered` (defaults to `[]`)
  """

  alias Ltix.PluginSet
  alias Ltix.PluginSet.Entry

  @doc """
  Checks a plugin set as it resolves, and returns the provider's data for
  `Ltix.PluginSet.data/2`.

  Return `{:error, conflicts}` to make resolution fail. The default returns
  `{:ok, nil}`, or `{:error, conflicts}` with the conflicts that the behaviours
  in `:hook` find, such as two modules that declare the same property. To return
  data, override it and call `super/1` first.

  ```elixir
  @impl Ltix.Provider
  def resolve(plugins) do
    with {:ok, nil} <- super(plugins), do: {:ok, columns(plugins)}
  end
  ```
  """
  @callback resolve(PluginSet.t()) :: {:ok, term()} | {:error, [PluginSet.Conflict.t(), ...]}

  @optional_callbacks resolve: 1

  defmacro __using__(opts) do
    quote bind_quoted: [hook: Keyword.get(opts, :hook, [])] do
      @behaviour Ltix.Provider

      @ltix_hook hook

      @doc false
      def __ltix_hook__, do: @ltix_hook

      defmacro __using__(opts), do: Ltix.Provider.__extender__(__MODULE__, @ltix_hook, opts)

      @impl Ltix.Provider
      def resolve(plugins), do: Ltix.Provider.__resolve__(plugins, __MODULE__)

      defoverridable resolve: 1
    end
  end

  # The default `resolve/1`. Returns the conflicts of each behaviour in
  # the provider's hook that defines `conflicts/2`, such as `Ltix.Property`.
  @doc false
  @spec __resolve__(PluginSet.t(), module()) ::
          {:ok, nil} | {:error, [PluginSet.Conflict.t(), ...]}
  def __resolve__(%PluginSet{} = plugins, provider) do
    conflicts =
      for block <- provider.__ltix_hook__(),
          Code.ensure_loaded?(block) && function_exported?(block, :conflicts, 2),
          conflict <- block.conflicts(plugins, provider),
          do: conflict

    case conflicts do
      [] -> {:ok, nil}
      conflicts -> {:error, conflicts}
    end
  end

  # The providers an entry or a module extends. An anonymous step or property
  # extends the provider in its `:to` option, and another anonymous entry, such
  # as one `Ltix.Claim.add/2` adds, extends its own module. A module extends
  # the providers in its `ltix_extends` attribute.
  @doc false
  @spec extended_providers(Entry.t() | module()) :: [module()]
  def extended_providers(%Entry{module: module, opts: opts} = entry) do
    if Entry.anonymous?(entry),
      do: [Keyword.get(opts, :to, module)],
      else: extended_providers(module)
  end

  def extended_providers(module),
    do: List.flatten(Keyword.get_values(module.module_info(:attributes), :ltix_extends))

  # The options of the `use` calls that make a module extend providers. Every
  # entry of the module has them.
  @doc false
  @spec use_options(module()) :: keyword()
  def use_options(module),
    do: List.flatten(Keyword.get_values(module.module_info(:attributes), :ltix_options))

  # Whether a module calls `use Ltix.Provider`.
  @doc false
  @spec provider?(term()) :: boolean()
  def provider?(module) do
    is_atom(module) && Code.ensure_loaded?(module) &&
      function_exported?(module, :__ltix_hook__, 0)
  end

  # Whether a module is a provider whose `:hook` includes `behaviour`.
  @doc false
  @spec hook?(term(), module()) :: boolean()
  def hook?(module, behaviour), do: provider?(module) && behaviour in module.__ltix_hook__()

  # Adds the provider's hook to a module that calls `use` with the provider,
  # and records the provider and the options of `use` in the module's
  # persisted `ltix_extends` and `ltix_options` attributes.
  @doc false
  def __extender__(provider, hook, opts) do
    provider_behaviour =
      if function_exported?(provider, :behaviour_info, 1),
        do: quote(do: @behaviour(unquote(provider)))

    blocks = for block <- hook, do: quote(do: use(unquote(block), unquote(opts)))

    quote do
      unless Module.has_attribute?(__MODULE__, :ltix_extends) do
        Module.register_attribute(__MODULE__, :ltix_extends, accumulate: true, persist: true)
        Module.register_attribute(__MODULE__, :ltix_options, accumulate: true, persist: true)
      end

      @ltix_extends unquote(provider)
      unquote(provider_behaviour)
      unquote_splicing(blocks)

      # After the hook, whose `use` can import what the options call.
      @ltix_options unquote(opts)
    end
  end
end
