defmodule Ltix.Errors.Invalid.ContentItemsExceedLimit do
  @moduledoc "Multiple content items returned when the platform only accepts one."
  use Ltix.Errors, fields: [:count, :spec_ref], class: :invalid

  # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
  def message(%{count: count, spec_ref: ref}) do
    "#{count} content items returned but platform does not accept multiple items [#{ref}]"
  end
end
