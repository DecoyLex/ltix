defmodule Ltix.Errors.Invalid.InvalidClaim do
  @moduledoc "Claim present but wrong value or format."
  use Splode.Error, fields: [:claim, :value, :spec_ref], class: :invalid

  def message(%{claim: claim, value: value, spec_ref: ref}) do
    "Invalid LTI claim #{claim}: got #{inspect(value)} [#{ref}]"
  end
end
