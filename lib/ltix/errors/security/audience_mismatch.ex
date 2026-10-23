defmodule Ltix.Errors.Security.AudienceMismatch do
  @moduledoc "Tool's client_id not the only JWT aud, or azp present and not client_id."
  use Ltix.Errors, fields: [:claim, :expected, :actual], class: :security

  def message(%{claim: claim, expected: expected, actual: actual}) do
    "Audience mismatch: expected #{expected} in #{claim} #{inspect(actual)}"
  end
end
