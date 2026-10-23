defmodule Ltix.Errors.Invalid.MediaTypeNotAccepted do
  @moduledoc """
  File content item media type not matched by the platform's `accept_media_types`.

  The following fields of this exception are public and can be accessed freely.

    * `:index` (`t:non_neg_integer/0`) - the item's position in the list passed to `Ltix.DeepLinking.build_response/3`
  """
  use Ltix.Errors, fields: [:index, :media_type, :accept_media_types], class: :invalid

  # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
  def message(%{index: index, media_type: media_type, accept_media_types: accepted}) do
    "Content item at index #{index} has media type #{inspect(media_type)}, " <>
      "which the platform does not accept. Accepted media types are #{inspect(accepted)}"
  end
end
