defmodule Ltix.Errors.Unknown.KeySetCacheNotStarted do
  @moduledoc """
  The key set cache a launch needs is not running.

  The following fields of this exception are public and can be accessed freely:

    * `:cache` (`t:module/0`) - the `Ltix.JWT.KeySet.Cache` module
    * `:child_spec` (`t:Supervisor.module_spec/0`) - what to add to the application's supervision tree
  """
  use Ltix.Errors, fields: [:cache, :child_spec], class: :unknown

  def message(%{cache: cache, child_spec: child_spec}) do
    "Key set cache #{inspect(cache)} is not started. " <>
      "Add #{Macro.to_string(Macro.escape(child_spec))} to your application's supervision tree."
  end
end
