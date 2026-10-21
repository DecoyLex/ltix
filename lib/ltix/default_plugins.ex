defmodule Ltix.DefaultPlugins do
  @moduledoc """
  The [plugins](`Ltix.Plugin`) every plugin set includes, one for each
  specification Ltix supports.

    * `Ltix.Core` for LTI Core 1.3.0
  """
  @behaviour Ltix.Plugin

  alias Ltix.Plugin

  @version Mix.Project.config()[:version]

  @impl Ltix.Plugin
  def plugin(_opts),
    do: Plugin.depend_on(Plugin.new(name: "Ltix", version: @version), Ltix.Core)
end
