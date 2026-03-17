defmodule Ltix.Errors.Invalid.LineItemNotAccepted do
  @moduledoc "Content item includes a line_item but the platform does not accept line items."
  use Ltix.Errors, fields: [:spec_ref], class: :invalid

  # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
  def message(%{spec_ref: ref}) do
    "Content item includes a line_item but the platform does not accept line items [#{ref}]"
  end
end
