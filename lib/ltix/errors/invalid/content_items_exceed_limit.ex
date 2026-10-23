defmodule Ltix.Errors.Invalid.ContentItemsExceedLimit do
  @moduledoc "Multiple content items returned when the platform only accepts one."
  use Ltix.Errors, fields: [:count], class: :invalid

  # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
  def message(%{count: count}) do
    "#{count} content items returned but platform does not accept multiple items"
  end
end
