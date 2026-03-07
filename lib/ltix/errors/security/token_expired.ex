defmodule Ltix.Errors.Security.TokenExpired do
  @moduledoc "Token exp claim is in the past [Sec §5.1.3 step 7]."
  use Splode.Error, fields: [:spec_ref], class: :security

  def message(%{spec_ref: ref}) do
    "JWT token has expired [#{ref}]"
  end
end
