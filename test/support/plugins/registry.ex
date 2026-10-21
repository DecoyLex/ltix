defmodule TestPlugins.Registry do
  @moduledoc false
  # A provider whose entries each declare a key with the `:key` option. Two
  # entries declaring one key conflict.
  use Ltix.Provider

  alias Ltix.PluginSet
  alias Ltix.PluginSet.Conflict

  @impl Ltix.Provider
  def resolve(set) do
    send(self(), {:resolved, __MODULE__})

    entries = PluginSet.entries(set, __MODULE__)

    conflicts =
      Conflict.duplicates(entries, & &1.opts[:key], &"both declare the key #{inspect(&1)}")

    case conflicts do
      [] -> {:ok, Map.new(entries, &{&1.opts[:key], &1.module})}
      conflicts -> {:error, conflicts}
    end
  end
end

defmodule TestPlugins.TenantKey do
  @moduledoc false
  use TestPlugins.Registry, key: :tenant
end

defmodule TestPlugins.OtherTenantKey do
  @moduledoc false
  use TestPlugins.Registry, key: :tenant
end

defmodule TestPlugins.RegistryStep do
  @moduledoc false
  # Extends the registry and login.
  use TestPlugins.Registry, key: :registry_step
  use Ltix.Login

  @impl Ltix.Step
  def call(login, _opts) do
    send(self(), {:trace, :registry_step})
    {:ok, login}
  end
end
