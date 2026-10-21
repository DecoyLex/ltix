defmodule Ltix.PluginSet.Entry do
  @moduledoc """
  A module a plugin added, with its options.

  `Ltix.PluginSet.entries/2` returns a provider's entries, and a provider reads
  their options when the plugin set resolves.

  ## Fields

    * `:module` - the module the plugin added. The module of an anonymous
      entry extends nothing, such as `Ltix.Step` for an anonymous step and
      `Ltix.Claim` for an anonymous claim.
    * `:opts` - the options the plugin added it with. A step's options are what
      its `c:Ltix.Step.init/1` returned.
    * `:plugin` - the plugin that added it, as a `{module, %Ltix.Plugin{}}`
      pair from `Ltix.PluginSet`'s `:plugins`
    * `:orders` - the orders that
      [calls such as `Ltix.Login.run_after/3`](`m:Ltix.Ordered#module-order-the-steps-a-plugin-adds`)
      around it give, innermost first, such as
      `[{:after, Ltix.Login.RegistrationFound}]`
  """

  alias Ltix.Provider

  defstruct [:module, :plugin, opts: [], orders: []]

  @type order :: {:before | :after, module()}

  @type t :: %__MODULE__{
          module: module(),
          opts: term(),
          plugin: {module(), Ltix.Plugin.t()} | nil,
          orders: [order()]
        }

  # An entry is anonymous when its module extends no provider, such as
  # `Ltix.Step` for a step that `Ltix.Login.add_step/2` adds.
  @doc false
  @spec anonymous?(t()) :: boolean()
  def anonymous?(%__MODULE__{module: module}), do: Provider.extended_providers(module) == []
end
