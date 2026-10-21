defmodule TestPlugins.Modules do
  @moduledoc false
  # A plugin that adds the modules its `:add` option lists, with the name its
  # `:name` option gives. Its `:build` option, a function, receives the plugin
  # after that and returns it with more added.
  @behaviour Ltix.Plugin

  alias Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(opts) do
    plugin = Plugin.new(name: Keyword.get(opts, :name, "Modules"), version: "1.0.0")
    plugin = Enum.reduce(Keyword.get(opts, :add, []), plugin, &Plugin.add(&2, &1))
    Keyword.get(opts, :build, & &1).(plugin)
  end
end
