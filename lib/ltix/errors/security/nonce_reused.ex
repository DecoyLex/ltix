defmodule Ltix.Errors.Security.NonceReused do
  @moduledoc "Nonce previously seen — replay attack [Sec §5.1.3 step 9]."
  use Ltix.Errors, fields: [:spec_ref], class: :security

  def message(%{spec_ref: ref}) do
    "JWT nonce has already been used [#{ref}]"
  end
end
