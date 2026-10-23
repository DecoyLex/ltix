defmodule Ltix.Errors.Invalid.PresentationTargetNotAccepted do
  @moduledoc """
  Content item presentation not in the platform's `accept_presentation_document_targets` list.

  The following fields of this exception are public and can be accessed freely.

    * `:index` (`t:non_neg_integer/0`) - the item's position in the list passed to `Ltix.DeepLinking.build_response/3`
    * `:target` (`t:String.t/0`) - `"iframe"`, `"window"`, or `"embed"`
  """
  use Ltix.Errors,
    fields: [:index, :target, :accept_presentation_document_targets],
    class: :invalid

  # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
  def message(%{index: index, target: target} = error) do
    "Content item at index #{index} uses presentation target #{inspect(target)}, " <>
      "which the platform does not accept. Accepted presentation targets are " <>
      "#{inspect(error.accept_presentation_document_targets)}"
  end
end
