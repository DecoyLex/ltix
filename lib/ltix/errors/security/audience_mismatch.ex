defmodule Ltix.Errors.Security.AudienceMismatch do
  @moduledoc "Tool's client_id not the only JWT aud, or azp present and not client_id [Sec §5.1.3 step 3; Sec §5.1.3 step 5]."
  use Ltix.Errors, fields: [:claim, :expected, :actual, :spec_ref], class: :security

  def message(%{claim: claim, expected: expected, actual: actual, spec_ref: ref}) do
    "Audience mismatch: expected #{expected} in #{claim} #{inspect(actual)} [#{ref}]"
  end
end
