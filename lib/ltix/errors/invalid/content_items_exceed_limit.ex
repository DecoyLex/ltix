defmodule Ltix.Errors.Invalid.ContentItemsExceedLimit do
  @moduledoc "Multiple content items returned when the platform only accepts one."
  use Ltix.Errors, fields: [:index, :count], class: :invalid

  # [DL, Deep linking settings](https://standards.1edtech.org/lti/specifications/launch_messages/deep_linking/lti-deep-linking-spec#deep-linking-settings)
  def message(%{count: count}) do
    "#{count} content items returned but platform does not accept multiple items"
  end
end
