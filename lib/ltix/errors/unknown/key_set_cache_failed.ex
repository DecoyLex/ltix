defmodule Ltix.Errors.Unknown.KeySetCacheFailed do
  @moduledoc """
  The key set cache could not get or store platform keys.

  The following fields of this exception are public and can be accessed freely:

    * `:cache` (`t:module/0`) - the `Ltix.JWT.KeySet.Cache` module
    * `:operation` (`t:atom/0`) - `:get` or `:put`
    * `:reason` (`t:term/0`) - what the cache backend reported
  """
  use Ltix.Errors, fields: [:cache, :operation, :reason], class: :unknown

  def message(%{cache: cache, operation: operation, reason: reason}) do
    "Key set cache #{inspect(cache)} failed to #{operation} keys, #{inspect(reason)}"
  end
end
