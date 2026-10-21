defmodule Ltix.DefaultPlugins do
  @moduledoc """
  The [plugins](`Ltix.Plugin`) every plugin set includes, one for each
  specification Ltix supports.

    * `Ltix.Core` for LTI Core 1.3.0
    * `Ltix.DeepLinking` for Deep Linking 2.0
    * `Ltix.GradeService` for Assignment and Grade Services 2.0
    * `Ltix.MembershipsService` for Names and Role Provisioning Services 2.0
  """
  @behaviour Ltix.Plugin

  alias Ltix.Plugin

  @version Mix.Project.config()[:version]

  @impl Ltix.Plugin
  def plugin(_opts) do
    Plugin.new(name: "Ltix", version: @version)
    |> Plugin.depend_on(Ltix.Core)
    |> Plugin.depend_on(Ltix.DeepLinking)
    |> Plugin.depend_on(Ltix.GradeService)
    |> Plugin.depend_on(Ltix.MembershipsService)
  end
end
