defmodule Ltix.Core do
  @moduledoc """
  The default [plugin](`Ltix.Plugin`) for LTI Core 1.3.0.

  ## Extending

  Every plugin set includes Core, so a plugin can extend these modules.

    * `Ltix.Login` to add login steps
  """
  @behaviour Ltix.Plugin

  alias Ltix.Login
  alias Ltix.Plugin

  @version Mix.Project.config()[:version]

  @impl Ltix.Plugin
  def plugin(_opts) do
    [name: "LTI Core 1.3.0", version: @version]
    |> Plugin.new()
    |> add_login()
  end

  defp add_login(plugin) do
    plugin
    |> Plugin.add(Login)
    |> Plugin.add(Login.CheckParameters)
    |> Plugin.add(Login.LookUpRegistration)
    |> Plugin.add(Login.RegistrationFound)
    |> Plugin.add(Login.BuildAuthenticationRequest)
  end
end
