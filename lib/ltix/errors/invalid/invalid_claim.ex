defmodule Ltix.Errors.Invalid.InvalidClaim do
  @moduledoc "Claim present but wrong value or format."
  use Splode.Error, fields: [:claim, :value, :message, :spec_ref], class: :invalid

  def message(%{claim: claim, message: nil, value: value, spec_ref: ref}) do
    "Invalid LTI claim #{claim}: got #{inspect(value)} [#{ref}]"
  end

  def message(%{claim: claim, message: message, value: value, spec_ref: ref}) do
    "Invalid LTI claim #{claim}: #{message} (got #{inspect(value)}) [#{ref}]"
  end
end
