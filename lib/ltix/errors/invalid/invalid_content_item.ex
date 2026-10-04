defmodule Ltix.Errors.Invalid.InvalidContentItem do
  @moduledoc """
  An item passed to `Ltix.DeepLinking.build_response/3` is not a content item.

  The following fields of this exception are public and can be accessed freely.

    * `:index` (`t:non_neg_integer/0` or `nil`) - the item's position in the list, or `nil` when the items are not a list
    * `:value` (`t:term/0`) - the item, or its `"type"` when that is invalid
  """
  use Ltix.Errors, fields: [:index, :value, :reason, :spec_ref], class: :invalid

  def message(%{index: nil, value: value, reason: reason, spec_ref: ref}) do
    "Content items #{reason}, got #{inspect(value)} [#{ref}]"
  end

  def message(%{index: index, value: value, reason: reason, spec_ref: ref}) do
    "Content item at index #{index} #{reason}, got #{inspect(value)} [#{ref}]"
  end
end
