defmodule Ltix.Errors.Security.AudienceMismatch do
  @moduledoc "Tool's client ID isn't the only JWT `aud`, or `azp` is present and isn't the client ID."
  use Ltix.Errors, fields: [:claim, :expected, :actual], class: :security

  def message(%{claim: claim, expected: expected, actual: actual}) do
    "Audience mismatch: expected #{expected} in #{claim} #{inspect(actual)}"
  end
end
