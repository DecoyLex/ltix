defmodule Ltix.Errors.Unknown.StorageError do
  @moduledoc """
  A storage adapter callback failed or returned an unexpected value.

  The following fields of this exception are public and can be accessed freely:

    * `:result` (`t:term/0`) - the value the callback returned
  """
  use Ltix.Errors, fields: [:callback, :result], class: :unknown

  def message(%{callback: callback, result: result}) do
    "Storage adapter callback #{callback} returned #{inspect(result)}"
  end
end
