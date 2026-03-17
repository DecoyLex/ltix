defmodule Ltix.Errors.Security.AudienceMismatch do
  @moduledoc "Tool's client_id not in JWT aud [Sec §5.1.3 step 3]."
  use Ltix.Errors, fields: [:expected, :actual, :spec_ref], class: :security

  def message(%{expected: expected, actual: actual, spec_ref: ref}) do
    "Audience mismatch: expected #{expected} in #{inspect(actual)} [#{ref}]"
  end
end
