defmodule Ltix.PluginSet.Conflict do
  @moduledoc """
  Two or more entries in a plugin set whose declarations contradict each other.

  `c:Ltix.Provider.resolve/1` returns conflicts, with the entries that
  `Ltix.PluginSet.entries/2` returned as the parties.

      %Ltix.PluginSet.Conflict{
        parties: [tenant_entry, other_tenant_entry],
        reason: "both declare the tenant claim"
      }

  The message of `Ltix.Errors.Unknown.InvalidPluginSet` lists each party's
  module and plugin, or what an anonymous party is and its plugin, such as
  "an anonymous claim of My Library".

  ## Fields

    * `:parties` - the `Ltix.PluginSet.Entry` structs in conflict, or the
      plugins in a cycle of dependencies
    * `:reason` - what the parties do, as a phrase that follows their names,
      such as `"both declare the tenant claim"`
  """

  @enforce_keys [:parties, :reason]
  defstruct [:parties, :reason]

  @type t :: %__MODULE__{
          parties: [Ltix.PluginSet.Entry.t() | module(), ...],
          reason: String.t()
        }

  @doc ~S"""
  Returns a conflict for each value that several entries declare.

  `key` returns the value an entry declares, and `reason` returns the
  conflict's reason for a value. Entries of one module with the same options
  count once.

  ## Examples

      iex> entries = [
      ...>   %Ltix.PluginSet.Entry{module: MyLibrary.Tenant, opts: [key: :tenant]},
      ...>   %Ltix.PluginSet.Entry{module: OtherLibrary.Tenant, opts: [key: :tenant]},
      ...>   %Ltix.PluginSet.Entry{module: MyLibrary.Tenant, opts: [key: :tenant]}
      ...> ]
      iex> Ltix.PluginSet.Conflict.duplicates(
      ...>   entries,
      ...>   & &1.opts[:key],
      ...>   &"both declare the key #{inspect(&1)}"
      ...> )
      [
        %Ltix.PluginSet.Conflict{
          parties: [
            %Ltix.PluginSet.Entry{module: MyLibrary.Tenant, opts: [key: :tenant]},
            %Ltix.PluginSet.Entry{module: OtherLibrary.Tenant, opts: [key: :tenant]}
          ],
          reason: "both declare the key :tenant"
        }
      ]
  """
  @spec duplicates([Ltix.PluginSet.Entry.t()], (Ltix.PluginSet.Entry.t() -> term()), (term() ->
                                                                                        String.t())) ::
          [t()]
  def duplicates(entries, key, reason) do
    for {value, [_, _ | _] = parties} <-
          Enum.group_by(Enum.uniq_by(entries, &{&1.module, &1.opts}), key) do
      %__MODULE__{parties: parties, reason: reason.(value)}
    end
  end
end
