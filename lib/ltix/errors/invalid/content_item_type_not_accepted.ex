defmodule Ltix.Errors.Invalid.ContentItemTypeNotAccepted do
  @moduledoc """
  Content item type not in the platform's `accept_types` list.

  The following fields of this exception are public and can be accessed freely.

    * `:index` (`t:non_neg_integer/0`) - the item's position in the list passed to `Ltix.DeepLinking.build_response/3`
  """
  use Ltix.Errors, fields: [:index, :type, :accept_types], class: :invalid

  # [DL, Deep linking settings](https://standards.1edtech.org/lti/specifications/launch_messages/deep_linking/lti-deep-linking-spec#deep-linking-settings)
  def message(%{index: index, type: type, accept_types: accepted}) do
    "Content item type #{inspect(type)} at index #{index} is not accepted; " <>
      "platform accepts: #{inspect(accepted)}"
  end
end
