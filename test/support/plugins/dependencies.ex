defmodule TestPlugins.Dependency do
  @moduledoc false
  # Sends the options it was enabled with as a trace.
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(opts) do
    Ltix.Plugin.new(name: "Dependency")
    |> Ltix.Plugin.add({TestPlugins.Trace, label: {:dependency, opts}})
  end
end

defmodule TestPlugins.Dependent do
  @moduledoc false
  @behaviour Ltix.Plugin

  alias Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Plugin.new(name: "Dependent")
    |> Plugin.depend_on(TestPlugins.Dependency)
    |> Plugin.add({TestPlugins.Trace, label: :dependent})
  end
end

defmodule TestPlugins.OtherDependent do
  @moduledoc false
  @behaviour Ltix.Plugin

  alias Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Plugin.new(name: "Other dependent")
    |> Plugin.depend_on(TestPlugins.Dependency)
    |> Plugin.add({TestPlugins.Trace, label: :other_dependent})
  end
end

defmodule TestPlugins.Profile do
  @moduledoc false
  @behaviour Ltix.Plugin

  alias Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Plugin.new(name: "Profile")
    |> Plugin.depend_on(TestPlugins.Dependent)
    |> Plugin.depend_on(TestPlugins.OtherDependent)
  end
end

defmodule TestPlugins.CycleStart do
  @moduledoc false
  @behaviour Ltix.Plugin

  alias Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Plugin.new(name: "Cycle start", version: "1.0.0")
    |> Plugin.depend_on(TestPlugins.CycleEnd)
  end
end

defmodule TestPlugins.CycleEnd do
  @moduledoc false
  @behaviour Ltix.Plugin

  alias Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Plugin.new(name: "Cycle end", version: "2.0.0")
    |> Plugin.depend_on(TestPlugins.CycleStart)
  end
end

defmodule TestPlugins.SelfDependent do
  @moduledoc false
  @behaviour Ltix.Plugin

  alias Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Plugin.new(name: "Self dependent", version: "1.0.0")
    |> Plugin.depend_on(__MODULE__)
  end
end
