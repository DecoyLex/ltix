defmodule Ltix.Errors.Invalid.MissingLineItemId do
  @moduledoc "Line item has no `id`."
  use Ltix.Errors, fields: [:line_item, :spec_ref], class: :invalid

  def message(%{spec_ref: ref}) do
    "Line item has no id. Create it with create_line_item/2 or fetch it from the platform first [#{ref}]"
  end
end
