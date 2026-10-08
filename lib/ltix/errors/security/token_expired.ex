defmodule Ltix.Errors.Security.TokenExpired do
  @moduledoc "Token exp claim is in the past, or iat claim is older than the maximum token age [Sec §5.1.3 steps 7-8]."
  use Ltix.Errors, fields: [:spec_ref], class: :security

  def message(%{spec_ref: ref}) do
    "JWT token has expired [#{ref}]"
  end
end
