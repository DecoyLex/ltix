defmodule TestPlugins.Unprovided do
  @moduledoc false
  # A struct with steps that no plugin provides.
  use Ltix.Provider, hook: [Ltix.Step]

  defstruct errors: [], plugins: nil
end

defmodule TestPlugins.UnprovidedStep do
  @moduledoc false
  # A step of `TestPlugins.Unprovided` that reports when its `init/1` runs.
  use TestPlugins.Unprovided

  @impl Ltix.Step
  defdelegate init(opts), to: TestPlugins.Init

  @impl Ltix.Step
  def call(struct, _opts), do: {:ok, struct}
end
