defmodule Ltix.Errors.Security.TokenNotYetValid do
  @moduledoc "Token iat or nbf claim is in the future [Sec §5.1.3 step 8; RFC 7519 §4.1.5]."
  use Ltix.Errors, fields: [:claim, :spec_ref], class: :security

  def message(%{claim: claim, spec_ref: ref}) do
    "JWT token is not yet valid, #{claim} is in the future [#{ref}]"
  end
end
