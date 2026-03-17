defmodule Ltix.Errors.Invalid.CoupledLineItem do
  @moduledoc "Attempted to delete the platform-coupled line item without `force: true`."
  use Ltix.Errors, fields: [:line_item_url, :spec_ref], class: :invalid

  def message(%{line_item_url: url, spec_ref: ref}) do
    "Cannot delete coupled line item #{url} — this is the platform-created line item " <>
      "from the launch claim. Pass force: true to override [#{ref}]"
  end
end
