defmodule Ltix.Errors.Invalid.MissingClaim do
  @moduledoc "Missing required LTI claim."
  use Splode.Error, fields: [:claim, :spec_ref], class: :invalid

  def message(%{claim: claim, spec_ref: ref}) do
    "Missing required LTI claim: #{claim} [#{ref}]"
  end
end
