defmodule Ltix.Errors.Unknown.InvalidPluginSet do
  @moduledoc """
  The plugins in a plugin set conflict, such as two plugins that declare the
  same claim.

  Every call that runs with these plugins returns it. Its message lists each
  conflict with the modules involved and the plugins that include them. Remove
  one of the conflicting plugins, or ask their authors to resolve the conflict.

  ## Fields

    * `:conflicts` - every conflict in the plugin set, as
      `t:Ltix.PluginSet.Conflict.t/0`
    * `:plugins` - the plugins in the set, as `{module, %Ltix.Plugin{}}` pairs
  """
  use Ltix.Errors, fields: [conflicts: [], plugins: []], class: :unknown

  alias Ltix.PluginSet.Entry

  def message(%{conflicts: conflicts, plugins: plugins}) do
    Enum.map_join(conflicts, "\n", fn conflict ->
      parties = Enum.map(conflict.parties, &describe(&1, plugins))
      upcase_first("#{join(parties)} #{conflict.reason}")
    end)
  end

  defp describe(%Entry{module: module, plugin: {plugin, declaration}} = entry, _plugins) do
    if Entry.anonymous?(entry),
      do: "an anonymous #{kind(module)} of #{label(plugin, declaration)}",
      else: "#{inspect(module)} (#{label(plugin, declaration)})"
  end

  defp describe(party, plugins) do
    labels =
      for {plugin, declaration} <- plugins, mentions?(plugin, declaration, party), uniq: true do
        label(plugin, declaration)
      end

    case labels do
      [] -> inspect(party)
      labels -> "#{inspect(party)} (#{Enum.join(labels, ", ")})"
    end
  end

  defp mentions?(plugin, declaration, party) do
    party == plugin || party in declaration.providers ||
      Enum.any?(declaration.entries, &(&1.module == party))
  end

  defp upcase_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest

  # What an anonymous entry is, from its module's name, such as "claim" for
  # `Ltix.Claim`.
  defp kind(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.replace("_", " ")
  end

  defp label(plugin, %{name: nil}), do: inspect(plugin)
  defp label(_plugin, %{name: name, version: nil}), do: name
  defp label(_plugin, %{name: name, version: version}), do: "#{name} #{version}"

  defp join([only]), do: only
  defp join([first, second]), do: "#{first} and #{second}"

  defp join(parties),
    do: Enum.join(Enum.drop(parties, -1), ", ") <> ", and " <> List.last(parties)
end
