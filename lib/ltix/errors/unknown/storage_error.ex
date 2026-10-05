defmodule Ltix.Errors.Unknown.StorageError do
  @moduledoc """
  A storage adapter callback failed or returned an unexpected value.

  The following fields of this exception are public and can be accessed freely.

    * `:result` (`t:term/0`) - the value the callback returned
    * `:reason` (`t:String.t/0` or `nil`) - what is wrong with a result that looks successful, such as a deployment for a different `deployment_id`
  """
  use Ltix.Errors, fields: [:callback, :result, :reason], class: :unknown

  def message(%{callback: callback, reason: reason}) when is_binary(reason) do
    "Storage adapter callback #{callback} #{reason}"
  end

  def message(%{callback: callback, result: result}) do
    "Storage adapter callback #{callback} returned #{inspect(result)}"
  end
end
