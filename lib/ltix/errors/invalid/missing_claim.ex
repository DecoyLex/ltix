defmodule Ltix.Errors.Invalid.MissingClaim do
  @moduledoc "Missing required LTI claim."
  use Ltix.Errors, fields: [:claim], class: :invalid

  def message(%{claim: claim}) do
    "Missing required LTI claim: #{claim}"
  end
end
