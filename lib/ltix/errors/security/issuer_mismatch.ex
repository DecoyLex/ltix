defmodule Ltix.Errors.Security.IssuerMismatch do
  @moduledoc "JWT `iss` doesn't match the registration."
  use Ltix.Errors, fields: [:expected, :actual], class: :security

  def message(%{expected: expected, actual: actual}) do
    "Issuer mismatch: expected #{expected}, got #{actual}"
  end
end
