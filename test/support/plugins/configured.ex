defmodule TestPlugins.Configured do
  @moduledoc false
  # Enabled in `config :ltix, plugins:` by `Ltix.Plugins.ConfiguredPluginsTest`.
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Ltix.Plugin.new(name: "Configured")
    |> Ltix.Plugin.add({TestPlugins.Tenant, tenant: "configured"})
    |> Ltix.Plugin.add(TestPlugins.SubmissionType)
    |> Ltix.Plugin.add(TestPlugins.Note)
  end
end

defmodule TestPlugins.Tenant do
  @moduledoc false
  # Writes its tenant to `login.private` and sends the login to the calling process.
  use Ltix.Login

  @impl Ltix.Step
  def init(opts), do: Keyword.fetch!(opts, :tenant)

  @impl Ltix.Step
  def call(login, tenant) do
    login = put_in(login.private[:test_plugins_tenant], tenant)
    send(self(), {:login, login})
    {:ok, login}
  end

  @impl Ltix.Ordered
  def after?(Ltix.Login.RegistrationFound), do: true
  def after?(_module), do: false
end
