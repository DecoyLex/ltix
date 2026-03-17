defmodule Ltix.Errors.Security.IssuerMismatch do
  @moduledoc "JWT iss doesn't match registration [Sec §5.1.3 step 2]."
  use Ltix.Errors, fields: [:expected, :actual, :spec_ref], class: :security

  def message(%{expected: expected, actual: actual, spec_ref: ref}) do
    "Issuer mismatch: expected #{expected}, got #{actual} [#{ref}]"
  end
end
