defmodule Ltix.Errors.Invalid.LineItemNotAccepted do
  @moduledoc """
  Content item includes a line_item but the platform does not accept line items.

  The following fields of this exception are public and can be accessed freely.

    * `:index` (`t:non_neg_integer/0`) - the item's position in the list passed to `Ltix.DeepLinking.build_response/3`
  """
  use Ltix.Errors, fields: [:index, :spec_ref], class: :invalid

  # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
  def message(%{index: index, spec_ref: ref}) do
    "Content item at index #{index} includes a line_item " <>
      "but the platform does not accept line items [#{ref}]"
  end
end
